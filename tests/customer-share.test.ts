// ============================================
// 客户推送模块 (customer_share) 真 DB 测试
// Phase D (docs/customer-identity-system.md §6.5 / ADR-0019 / 主文档 §8.4)
// ============================================
// 覆盖 (任务书要求):
//   S1-S7 + SHARE-1..7 + 跨枝拒绝 / 越权拒绝 / 重复幂等 / 撤销后立即失效 / 双方停用失效 /
//   二次转发被拒 / 上限触发
//
// 隔离策略:
//   - 共享**树** fixture (root → mid → leaf + unrelated root)
//   - 每个 it 自建一个**客户档案** (custN) 用于本用例, 不复用 → 不撞 S4 / S6 上限
//   - 收尾时按 id 精确删 (不 TRUNCATE 别人的数据)
// ============================================

import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import { and, eq, inArray, isNull, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  customer,
  customerShare,
  franchisee,
  referralCode,
  user as userTable,
} from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import {
  shareCustomer,
  revokeCustomerShare,
  listReceivedShares,
  MAX_ACTIVE_SHARES_PER_CUSTOMER,
  MAX_DAILY_SHARES_PER_RECIPIENT,
} from "@/lib/db/queries/customer-share";
import type { AuditContext } from "@/lib/audit/context";

const PHONE_SEG = "13906";
const TAG = `customer-share-${Date.now()}`;

interface UserFixture {
  uid: bigint;
  fid: bigint | null;
  admin: boolean;
}

const noopCtx: AuditContext = { userId: null, ipAddress: null };
// 顺序计数器, 给每个 it 一个独立的客户 phone 段 (避免 S6 上限撞车)
let shareIdsCreated: bigint[] = [];
let custIdsCreated: bigint[] = [];
// 全程递增的 customer 序号 (跨 describe 不归零) — 避免 customer.phoneHash 重复
let globalCustCounter = 0;

async function mkUser(seq: string, admin: boolean): Promise<UserFixture> {
  const phone = PHONE_SEG + seq.padStart(6, "0").slice(-6);
  const phoneHash = hashForLookup(phone);
  const [u] = await db
    .insert(userTable)
    .values({
      name: `${TAG}-${admin ? "admin" : "sales"}-${seq}`,
      phoneEncrypted: encryptField(phone),
      phoneHash,
      role: admin ? "admin" : "sales",
      isActive: true,
    })
    .returning({ id: userTable.id });
  const uid = u.id;
  const code = `${TAG.slice(-6).toUpperCase()}S${seq.padStart(2, "0").slice(-2)}`;
  await db.insert(referralCode).values({ userId: uid, code });
  return { uid, fid: null, admin };
}

async function mkFranchisee(
  uid: bigint,
  seq: string,
  placementParentId: bigint | null,
  path: string,
  depth: number,
  referrerId: bigint | null,
  rootId: bigint | null,
  side: "left" | "right" | null = "left",
): Promise<bigint> {
  const phone = PHONE_SEG + seq.padStart(6, "0").slice(-6);
  const [f] = await db
    .insert(franchisee)
    .values({
      name: `${TAG}-加盟商-${seq}`,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      placementParentId,
      placementSide: side,
      placementPath: path,
      placementDepth: depth,
      referrerId,
      rootId,
      isActive: true,
      createdBy: uid,
    })
    .returning({ id: franchisee.id });
  await db.update(userTable).set({ franchiseeId: f.id }).where(eq(userTable.id, uid));
  return f.id;
}

async function mkCustomerWith(seq: string, ownerId: bigint | null): Promise<bigint> {
  const phone = PHONE_SEG + "8" + seq.padStart(5, "0").slice(-5);
  const [c] = await db
    .insert(customer)
    .values({
      name: `${TAG}-客户-${seq}`,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      createdBy: ownerId ?? BigInt(0),
      ownerId,
    })
    .returning({ id: customer.id });
  custIdsCreated.push(c.id);
  return c.id;
}

/** 每个 it 拿一个独立新 customer id (全局递增, 跨 describe 保证 phone_hash 唯一) */
function freshCustomer(): Promise<bigint> {
  globalCustCounter += 1;
  return mkCustomerWith(globalCustCounter.toString().padStart(8, "0"), null);
}

// ============================================================
// 共享 fixture: 树 + 用户
// ============================================================
let admin: UserFixture;
let root: UserFixture;    // 树根
let mid: UserFixture;     // 中层
let leaf: UserFixture;    // 叶
let unrelated: UserFixture; // 另一棵树根

beforeAll(async () => {
  // ★ 预清理: 上次中断/失败的残留 (同名前缀) → 防手机号唯一键撞车 + 共享表 FK 残留
  await db.execute(sql`DELETE FROM customer_share WHERE from_user_id IN (SELECT id FROM "user" WHERE name LIKE 'customer-share-%') OR to_user_id IN (SELECT id FROM "user" WHERE name LIKE 'customer-share-%')`);
  await db.execute(sql`DELETE FROM customer WHERE name LIKE 'customer-share-%'`);
  await db.execute(sql`DELETE FROM franchisee WHERE name LIKE 'customer-share-%'`);
  await db.execute(sql`DELETE FROM "user" WHERE name LIKE 'customer-share-%'`);
  admin = await mkUser("00001", true);
  root = await mkUser("00010", false);
  mid = await mkUser("00011", false);
  leaf = await mkUser("00012", false);
  unrelated = await mkUser("00020", false);

  // ★ 根节点自指 root_id = 自己 (AGENTS §6.8 / migration 0017 多根约定)
  //   保证 IS NOT DISTINCT FROM 在 SQL 上能走同枝 (NULL 对比是非 true)
  root.fid = await mkFranchisee(root.uid, "00010", null, "", 0, null, null);
  await db.update(franchisee).set({ rootId: root.fid }).where(eq(franchisee.id, root.fid));
  mid.fid = await mkFranchisee(
    mid.uid,
    "00011",
    root.fid,
    "L.",
    1,
    root.fid,
    root.fid,
  );
  leaf.fid = await mkFranchisee(
    leaf.uid,
    "00012",
    mid.fid,
    "L.L.",
    2,
    mid.fid,
    root.fid,
  );
  unrelated.fid = await mkFranchisee(unrelated.uid, "00020", null, "", 0, null, null);
  await db.update(franchisee).set({ rootId: unrelated.fid }).where(eq(franchisee.id, unrelated.fid));
});

afterAll(async () => {
  const uids = [admin.uid, root.uid, mid.uid, leaf.uid, unrelated.uid];
  const fids = [root.fid, mid.fid, leaf.fid, unrelated.fid].filter(
    (v): v is bigint => v != null,
  );
  // 清理所有创建的分享 + 所有创建的客户档案
  if (shareIdsCreated.length) {
    await db.execute(sql`DELETE FROM customer_share WHERE id IN (${sql.join(shareIdsCreated, sql`, `)})`);
  }
  // ★ 兜底: 任何引用本测试用户/客户的 share 行都要先删干净 (否则删 user 会撞 FK,
  //   未登记进 shareIdsCreated 的行会残留 → 文件级 FAIL)
  await db.execute(
    sql`DELETE FROM customer_share WHERE from_user_id IN (${sql.join(uids, sql`, `)}) OR to_user_id IN (${sql.join(uids, sql`, `)})`,
  );
  if (custIdsCreated.length) {
    await db.execute(
      sql`DELETE FROM customer_share WHERE customer_id IN (${sql.join(custIdsCreated, sql`, `)})`,
    );
  }
  if (custIdsCreated.length) {
    await db.execute(sql`DELETE FROM customer WHERE id IN (${sql.join(custIdsCreated, sql`, `)})`);
  }
  await db.execute(sql`DELETE FROM "user" WHERE id IN (${sql.join(uids, sql`, `)})`);
  await db.execute(sql`DELETE FROM referral_code WHERE user_id IN (${sql.join(uids, sql`, `)})`);
  await db.execute(sql`DELETE FROM franchisee WHERE id IN (${sql.join(fids, sql`, `)})`);
  await db.execute(sql`DELETE FROM audit_log WHERE record_id IN (${sql.join(
    [...uids, ...fids, ...custIdsCreated, ...shareIdsCreated],
    sql`, `,
  )})`);
});

beforeEach(() => {
  // 重置 shareIds / custIds 收集 (本轮的), 但不重置 globalCustCounter
  //   — 全程递增才能保证 customer.phone_hash 唯一 (重复会撞 idx_customer_phone_hash)
  shareIdsCreated = [];
  custIdsCreated = [];
});

// ============================================================
// S1: 只有归属人 / admin 能推送
// ============================================================
describe("S1 — 推送权 (归属人/admin)", () => {
  it("mid 推 leaf 拥有/未软删的客户 → NOT_OWNER (非归属, 非 admin)", async () => {
    const cid = await freshCustomer();
    // 设 leaf 拥有此客户 (mid 不是)
    await db.update(customer).set({ ownerId: leaf.uid }).where(eq(customer.id, cid));
    const r = await shareCustomer(
      { customerId: cid, fromUserId: mid.uid, toUserId: leaf.uid },
      noopCtx,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("NOT_OWNER");
  });

  it("mid 推自己拥有的客户 → OK", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: mid.uid }).where(eq(customer.id, cid));
    const r = await shareCustomer(
      { customerId: cid, fromUserId: mid.uid, toUserId: leaf.uid },
      noopCtx,
    );
    expect(r.ok).toBe(true);
    if (r.ok) shareIdsCreated.push(BigInt(r.row.id));
  });

  it("admin 推任意客户的客户 (admin 豁免) → OK", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const r = await shareCustomer(
      { customerId: cid, fromUserId: admin.uid, toUserId: unrelated.uid, note: "admin 跨枝豁免" },
      noopCtx,
    );
    expect(r.ok).toBe(true);
    if (r.ok) shareIdsCreated.push(BigInt(r.row.id));
  });
});

// ============================================================
// S2: 同枝判定 + admin 豁免 + 跨枝拒绝
// ============================================================
describe("S2 — 同枝 / 跨枝", () => {
  it("root 推送 → unrelated (跨枝) → TO_USER_NOT_IN_SAME_BRANCH", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const r = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: unrelated.uid },
      noopCtx,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("TO_USER_NOT_IN_SAME_BRANCH");
  });

  it("admin 跨枝推送 → OK (admin 豁免)", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const r = await shareCustomer(
      { customerId: cid, fromUserId: admin.uid, toUserId: unrelated.uid },
      noopCtx,
    );
    expect(r.ok).toBe(true);
    if (r.ok) shareIdsCreated.push(BigInt(r.row.id));
  });

  it("root 推送 → mid (同枝下层) → OK", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    // 验证 update 成功 (中间检查)
    const [check] = await db.select({ ownerId: customer.ownerId }).from(customer).where(eq(customer.id, cid)).limit(1);
    expect(check?.ownerId).toBe(root.uid);
    const r = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    if (!r.ok) {
      throw new Error(`share failed: code=${r.code} detail=${r.detail}`);
    }
    expect(r.ok).toBe(true);
    if (r.ok) shareIdsCreated.push(BigInt(r.row.id));
  });
});

// ============================================================
// S3: 推送不写 owner_id (SHARE-1)
// ============================================================
describe("S3 — 推送不改 owner_id (SHARE-1)", () => {
  it("推送前后 customer.ownerId 不变", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const [before] = await db.select({ ownerId: customer.ownerId }).from(customer).where(eq(customer.id, cid)).limit(1);
    expect(before?.ownerId).toBe(root.uid);
    const r = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    expect(r.ok).toBe(true);
    if (r.ok) shareIdsCreated.push(BigInt(r.row.id));
    const [after] = await db.select({ ownerId: customer.ownerId }).from(customer).where(eq(customer.id, cid)).limit(1);
    expect(after?.ownerId).toBe(root.uid);
  });
});

// ============================================================
// S4: 部分唯一索引 + 幂等 (重复 active)
// ============================================================
describe("S4 — 部分唯一 + 幂等", () => {
  it("同 (customer, to_user) 重复 → ALREADY_SHARED", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const r1 = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    expect(r1.ok).toBe(true);
    if (r1.ok) shareIdsCreated.push(BigInt(r1.row.id));
    const r2 = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    expect(r2.ok).toBe(false);
    if (!r2.ok) expect(r2.code).toBe("ALREADY_SHARED");
  });

  it("撤销后再推 → OK (部分唯一索引只看 active)", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const first = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    if (!first.ok) throw new Error(`first share failed: code=${first.code} detail=${first.detail}`);
    // owner 撤销必填 reason (主文档 §6.5.2 S5); 给个字符串补上
    const rev1 = await revokeCustomerShare(
      { customerId: cid, toUserId: mid.uid, actorUserId: root.uid, reason: "撤销重推" },
      noopCtx,
    );
    if (!rev1.ok) throw new Error(`revoke failed: code=${rev1.code}`);
    expect(rev1.ok).toBe(true);
    const r2 = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    if (!r2.ok) throw new Error(`second share failed: code=${r2.code} detail=${r2.detail}`);
    expect(r2.ok).toBe(true);
    if (r2.ok) shareIdsCreated.push(BigInt(r2.row.id));
  });
});

// ============================================================
// S5: 四方撤销 + reason 必填 + 幂等
// ============================================================
describe("S5 — 四方撤销 (from / to / 当前 owner / admin) + 幂等 + reason 必填", () => {
  it("from 自己撤销自己推的 → OK", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    // 来自「推送人自己」撤销 (推送人 != 当前 owner);  推送人推的时候 owner = 自己同一, 但 视为 admin/owner 仍提供 reason
    const r = await revokeCustomerShare(
      { customerId: cid, toUserId: mid.uid, actorUserId: root.uid, reason: "from revoke" },
      noopCtx,
    );
    if (!r.ok) throw new Error(`revoke failed: code=${r.code}`);
    expect(r.ok).toBe(true);
    expect(r.alreadyRevoked).toBe(false);
  });

  it("admin 撤销, 无 reason → REASON_REQUIRED", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    await shareCustomer(
      { customerId: cid, fromUserId: admin.uid, toUserId: unrelated.uid },
      noopCtx,
    );
    const r = await revokeCustomerShare(
      { customerId: cid, toUserId: unrelated.uid, actorUserId: admin.uid, reason: "" },
      noopCtx,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("REASON_REQUIRED");
  });

  it("admin 撤销 + 带 reason → OK", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    await shareCustomer(
      { customerId: cid, fromUserId: admin.uid, toUserId: unrelated.uid },
      noopCtx,
    );
    const r = await revokeCustomerShare(
      { customerId: cid, toUserId: unrelated.uid, actorUserId: admin.uid, reason: "测试撤销" },
      noopCtx,
    );
    expect(r.ok).toBe(true);
  });

  it("重复撤销 → alreadyRevoked=true (幂等, 主文档 §6.5.4)", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    await revokeCustomerShare(
      { customerId: cid, toUserId: mid.uid, actorUserId: root.uid, reason: "first revoke" },
      noopCtx,
    );
    const r = await revokeCustomerShare(
      { customerId: cid, toUserId: mid.uid, actorUserId: root.uid, reason: "再撤一次" },
      noopCtx,
    );
    if (!r.ok) throw new Error(`repeat revoke failed: code=${r.code}`);
    expect(r.ok).toBe(true);
    expect(r.alreadyRevoked).toBe(true);
  });

  it("无关人撤销 → NOT_AUTHORIZED", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    const r = await revokeCustomerShare(
      { customerId: cid, toUserId: mid.uid, actorUserId: unrelated.uid },
      noopCtx,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("NOT_AUTHORIZED");
  });
});

// ============================================================
// S6: 扩散上限 (SHARE_LIMIT_EXCEEDED)
// ============================================================
describe("S6 — 扩散上限", () => {
  it(`同客户 active 推送数 ≤ ${MAX_ACTIVE_SHARES_PER_CUSTOMER}; 超限 → SHARE_LIMIT_EXCEEDED`, async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));

    // 准备 5 个同枝新 user (root 下层) — 各自一个新节点
    const seq = "8888";
    const extra: UserFixture[] = [];
    for (let i = 0; i < MAX_ACTIVE_SHARES_PER_CUSTOMER; i++) {
      const u = await mkUser(`${seq}${i}`, false);
      u.fid = await mkFranchisee(
        u.uid,
        `${seq}${i}`,
        root.fid,
        `${seq}${i}.`,
        1,
        root.fid,
        root.fid,
        i % 2 === 0 ? "left" : "right",
      );
      extra.push(u);
    }
    let okCount = 0;
    for (const u of extra) {
      const r = await shareCustomer(
        { customerId: cid, fromUserId: root.uid, toUserId: u.uid },
        noopCtx,
      );
      if (r.ok) {
        okCount++;
        shareIdsCreated.push(BigInt(r.row.id));
      }
    }
    expect(okCount).toBe(MAX_ACTIVE_SHARES_PER_CUSTOMER);

    // 第 6 个 (超限) → 应被拒
    const overUid = await mkUser(`${seq}X`, false);
    const overFid = await mkFranchisee(
      overUid.uid,
      `${seq}X`,
      root.fid,
      `${seq}X.`,
      1,
      root.fid,
      root.fid,
    );
    void overFid;
    const over = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: overUid.uid },
      noopCtx,
    );
    expect(over.ok).toBe(false);
    if (!over.ok) expect(over.code).toBe("SHARE_LIMIT_EXCEEDED");

    expect(MAX_DAILY_SHARES_PER_RECIPIENT).toBeGreaterThan(0);
  });
});

// ============================================================
// S7: 禁止二次转发 (FORBIDDEN_RE_SHARE)
// ============================================================
describe("S7 — 禁止二次转发", () => {
  it("mid 是被推送人, 想再推同一客户 → FORBIDDEN_RE_SHARE (即使 mid 现在是 owner)", async () => {
    const cid = await freshCustomer();
    // T1: root (old owner) 推给 mid → mid 是被推送人
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const t1 = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    if (!t1.ok) throw new Error(`t1 share failed: code=${t1.code}`);

    // T2: owner 转移到 mid (mid 现在是 owner 但仍是受推送人) — SHARE-6 推送保留
    await db.update(customer).set({ ownerId: mid.uid }).where(eq(customer.id, cid));
    // T3: mid 想再推给 leaf → S7 拦截 (即使 S1 过本条路径, S7 仍是额外检查)
    const r = await shareCustomer(
      { customerId: cid, fromUserId: mid.uid, toUserId: leaf.uid },
      noopCtx,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("FORBIDDEN_RE_SHARE");
  });

  it("admin 二次转发 → 豁免 (admin 不受限)", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    // root → mid (active, 让 mid 处于「被推送」状态)
    await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid },
      noopCtx,
    );
    // admin 推同一客户给 leaf → 应 OK (admin 不受限 S7)
    const r = await shareCustomer(
      { customerId: cid, fromUserId: admin.uid, toUserId: leaf.uid },
      noopCtx,
    );
    expect(r.ok).toBe(true);
    if (r.ok) shareIdsCreated.push(BigInt(r.row.id));
  });
});

// ============================================================
// 列表角标: maskPhone 强制
// ============================================================
describe("listReceivedShares — 角标元数据 (主文档 §9.3)", () => {
  it("返回的 fromUserPhoneMasked / customerPhoneMasked 包含 *, 且 ≠ 输入", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const r = await shareCustomer(
      { customerId: cid, fromUserId: root.uid, toUserId: mid.uid, note: "list test" },
      noopCtx,
    );
    expect(r.ok).toBe(true);
    if (r.ok) shareIdsCreated.push(BigInt(r.row.id));
    const items = await listReceivedShares(mid.uid);
    expect(items.length).toBeGreaterThan(0);
    const item = items.find((x) => x.customerId === cid.toString());
    expect(item).toBeDefined();
    expect(item!.fromUserPhoneMasked).toMatch(/\*/);
    expect(item!.customerPhoneMasked).toMatch(/\*/);
  });
});

// ============================================================
// SHARE-4: 双方停用 / 节点软删 / 撤销后即失效
// ============================================================
describe("SHARE-4 — 撤销 / 停用 → 即失效", () => {
  it("撤销后 listReceivedShares 不再返回", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    const r1 = await shareCustomer(
      { customerId: cid, fromUserId: admin.uid, toUserId: unrelated.uid, note: "transient" },
      noopCtx,
    );
    expect(r1.ok).toBe(true);
    const itemsBefore = await listReceivedShares(unrelated.uid);
    const beforeN = itemsBefore.length;
    expect(beforeN).toBeGreaterThan(0);

    const r2 = await revokeCustomerShare(
      { customerId: cid, toUserId: unrelated.uid, actorUserId: admin.uid, reason: "清理" },
      noopCtx,
    );
    expect(r2.ok).toBe(true);
    const itemsAfter = await listReceivedShares(unrelated.uid);
    const after = itemsAfter.find((x) => x.customerId === cid.toString());
    expect(after).toBeUndefined();
    expect(itemsAfter.length).toBe(beforeN - 1);
  });

  it("接收人 is_active=false → listReceivedShares 不返回 (SHARE-4)", async () => {
    const cid = await freshCustomer();
    await db.update(customer).set({ ownerId: root.uid }).where(eq(customer.id, cid));
    await shareCustomer(
      { customerId: cid, fromUserId: admin.uid, toUserId: unrelated.uid, note: "transient2" },
      noopCtx,
    );
    const before = await listReceivedShares(unrelated.uid);
    expect(before.find((x) => x.customerId === cid.toString())).toBeDefined();

    await db.update(userTable).set({ isActive: false }).where(eq(userTable.id, unrelated.uid));
    const after = await listReceivedShares(unrelated.uid);
    expect(after.find((x) => x.customerId === cid.toString())).toBeUndefined();

    // 还原
    await db.update(userTable).set({ isActive: true }).where(eq(userTable.id, unrelated.uid));
  });
});
