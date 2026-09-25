// ============================================
// viewerCustomerScopeSql 四段式可见集合 (主文档 §3.4)
// + identity.ts Phase D 6 态 (ownership 第 6 态 SHARE-7)
// ============================================
// 覆盖 (任务书要求):
//   - 四段 SQL 渲染正确 (a / b1 / b2 / c 各子句)
//   - 根用户 (path='') 时三态路径不退化 (§3.4 (b2) 三元化三元化 与 (c) 路径护)
//   - 跨树拒绝 (root_id IS NOT DISTINCT FROM)
//   - 软删 franchisee / customer 排除 (B1 / E1)
//   - 无加盟 viewer 退化为仅 (a)
// 真 DB 测试驱动 (与 customer-scope 同模式, 但用例造更深):
//   - viewerCustomerScopeSql 用 sqlToQuery 断言; 真 DB 跑 SELECT 接住
// ============================================

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { eq, sql } from "drizzle-orm";
import { PgDialect } from "drizzle-orm/pg-core";
import { db } from "@/lib/db";
import { customerShare } from "@/lib/db/schema";
import { customer, franchisee, user as userTable } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import {
  viewerCustomerScopeSql,
  type CustomerScopeViewer,
} from "@/lib/db/queries/customer-scope";

const dialect = new PgDialect();

const PHONE_SEG = "13907";
const TAG = `viewer-scope-${Date.now()}`;

// ============================================================
// Fixture: 4 层树 + 1 跨树节点
// ============================================================
let rootUid: bigint;
let rootFid: bigint;
let midUid: bigint;
let midFid: bigint;
let deepUid: bigint;
let deepFid: bigint;
let otherTreeUid: bigint;
let otherTreeFid: bigint;
let custMine: bigint;        // owner = root
let custOfMid: bigint;       // owner = mid
let custOfDeep: bigint;      // owner = deep
let custOtherTree: bigint;
let custShared: bigint;      // 用于 share 推送 测试 (Phase D)
let shareId: bigint;

async function mkUser(
  seq: string,
  role: "sales" | "admin" = "sales",
): Promise<bigint> {
  const phone = PHONE_SEG + seq.padStart(6, "0").slice(-6);
  const [u] = await db
    .insert(userTable)
    .values({
      name: `${TAG}-user-${seq}`,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      role,
      isActive: true,
    })
    .returning({ id: userTable.id });
  return u.id;
}

async function mkFranchisee(
  uid: bigint,
  seq: string,
  placementParentId: bigint | null,
  placementSide: "left" | "right" | null,
  path: string,
  depth: number,
  referrerId: bigint | null,
  rootId: bigint | null,
): Promise<bigint> {
  const phone = PHONE_SEG + seq.padStart(6, "0").slice(-6);
  const [f] = await db
    .insert(franchisee)
    .values({
      name: `${TAG}-franchisee-${seq}`,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      placementParentId,
      placementSide,
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

async function mkCustomer(
  seq: string,
  ownerId: bigint,
): Promise<bigint> {
  const phone = PHONE_SEG + "9" + seq.padStart(5, "0").slice(-5);
  const [c] = await db
    .insert(customer)
    .values({
      name: `${TAG}-cust-${seq}`,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      createdBy: ownerId,
      ownerId,
    })
    .returning({ id: customer.id });
  return c.id;
}

beforeAll(async () => {
  // ★ 预清理: 上次中断/失败的残留 (同名前缀) → 防手机号唯一键撞车 + 共享表 FK 残留
  await db.execute(sql`DELETE FROM customer_share WHERE from_user_id IN (SELECT id FROM "user" WHERE name LIKE 'viewer-scope-%') OR to_user_id IN (SELECT id FROM "user" WHERE name LIKE 'viewer-scope-%')`);
  await db.execute(sql`DELETE FROM customer WHERE name LIKE 'viewer-scope-%'`);
  await db.execute(sql`DELETE FROM franchisee WHERE name LIKE 'viewer-scope-%'`);
  await db.execute(sql`DELETE FROM "user" WHERE name LIKE 'viewer-scope-%'`);
  // 用户
  rootUid = await mkUser("00010");
  midUid = await mkUser("00011");
  deepUid = await mkUser("00012");
  otherTreeUid = await mkUser("00020");

  // 树 root → mid → deep ; otherTree 单独一棵树
  rootFid = await mkFranchisee(rootUid, "00010", null, null, "", 0, null, null);
  midFid = await mkFranchisee(midUid, "00011", rootFid, "left", "L.", 1, rootFid, rootFid);
  deepFid = await mkFranchisee(deepUid, "00012", midFid, "left", "L.L.", 2, midFid, rootFid);
  otherTreeFid = await mkFranchisee(otherTreeUid, "00020", null, null, "", 0, null, null);

  // 根节点不变量 (AGENTS §6.8 / schema): root_id = 自己的 id —— 插入时 id 未知, 插入后自指回填
  await db.update(franchisee).set({ rootId: rootFid }).where(eq(franchisee.id, rootFid));
  await db.update(franchisee).set({ rootId: otherTreeFid }).where(eq(franchisee.id, otherTreeFid));

  // 客户
  custMine = await mkCustomer("00010", rootUid);
  custOfMid = await mkCustomer("00011", midUid);
  custOfDeep = await mkCustomer("00012", deepUid);
  custOtherTree = await mkCustomer("00020", otherTreeUid);
  // 共享推送用:
  custShared = await mkCustomer("00099", rootUid); // owner = root

  // 推送: root → mid 推 custShared (上层推送, mid 可见)
  //  phase D 测试: 直接走 drizzle 插条记录 (不走 shareCustomer 业务校验以保持 isolated)
  const [inserted] = await db
    .insert(customerShare)
    .values({
      customerId: custShared,
      fromUserId: rootUid,
      toUserId: midUid,
      note: "fixture share",
    })
    .returning({ id: customerShare.id });
  shareId = inserted.id;
});

afterAll(async () => {
  const allIds = [custMine, custOfMid, custOfDeep, custOtherTree, custShared].filter(Boolean);
  const uids = [rootUid, midUid, deepUid, otherTreeUid].filter(Boolean);
  const fids = [rootFid, midFid, deepFid, otherTreeFid].filter(Boolean);
  if (shareId) {
    await db.execute(sql`DELETE FROM customer_share WHERE id = ${shareId}`);
  }
  if (allIds.length || uids.length) {
    await db.execute(sql`DELETE FROM customer WHERE id IN (${sql.join(allIds, sql`, `)})`);
    await db.execute(sql`DELETE FROM "user" WHERE id IN (${sql.join(uids, sql`, `)})`);
    if (fids.length) {
      await db.execute(sql`DELETE FROM franchisee WHERE id IN (${sql.join(fids, sql`, `)})`);
    }
    await db.execute(sql`
      DELETE FROM audit_log WHERE record_id IN (${sql.join(
        [...allIds, ...uids, ...fids],
        sql`, `,
      )})
    `);
  }
});

// ============================================================
// SQL 渲染: 4 段集合 + NULL 守卫 + IS NULL (退化为 false)
// ============================================================
describe("viewerCustomerScopeSql — SQL 渲染", () => {
  it("四段汇集 + customer.deleted_at IS NULL 守卫 (E1)", () => {
    const viewer: CustomerScopeViewer = { userId: rootUid, franchiseeId: rootFid };
    const q = dialect.sqlToQuery(viewerCustomerScopeSql(viewer));
    expect(q.sql).toContain("deleted_at");
    expect(q.sql).toMatch(/IS NULL/);
    // 四段 OR
    expect(q.sql).toMatch(/OR/);
    // 段 (a): owner_id
    expect(q.sql).toContain("owner_id");
    // 段 (b1) 用 isDirectDownlineFranchiseeSql (placement_parent_id)
    expect(q.sql).toContain("placement_parent_id");
    // 段 (b2) 同 root_id + placement_path 前缀 (跟 identity.ts 一致, 三元化)
    expect(q.sql).toContain("root_id");
    // 段 (c) customer_share
    expect(q.sql).toContain("customer_share");
    expect(q.sql).toContain("revoked_at");
    // B2 同枝, 接收人 active, 推送人 active, 推送人节点未软删
    expect(q.sql).toContain("is_active");
  });

  it("viewer.franchiseeId = null → (b1)(b2) 退化, (a)(c) 走 userId", () => {
    const viewer: CustomerScopeViewer = { userId: rootUid, franchiseeId: null };
    const q = dialect.sqlToQuery(viewerCustomerScopeSql(viewer));
    // (a) owner_id = rootUid 还在
    expect(q.sql).toContain("owner_id");
    // (b1) / (b2) / (c) 内部有 false 段
    //   直接判断: 没有 franchisee 同枝相关 (path LIKE) 应少于 viewer 有 fid 的情况
    expect(q.sql.split("placement_path").length - 1).toBeLessThanOrEqual(2);
  });

  it("viewer.userId = null → (a) / (c) 退化", () => {
    const viewer: CustomerScopeViewer = { userId: null, franchiseeId: rootFid };
    const q = dialect.sqlToQuery(viewerCustomerScopeSql(viewer));
    // (a) / (c) 段退化: 多次出现 false 字面
    const falseCount = (q.sql.match(/\bfalse\b/g) ?? []).length;
    expect(falseCount).toBeGreaterThanOrEqual(2);
  });
});

// ============================================================
// 真 DB: 根用户 (path='') 与深层用户 都能正确命中可见集
// ============================================================
describe("viewerCustomerScopeSql — 真 DB 命中 (a/b1/b2/c)", () => {
  it("根用户 (root): 自己的 + 下层归属的 + 下层加盟节点本人档案 + 上级推送全命中", async () => {
    const viewer: CustomerScopeViewer = { userId: rootUid, franchiseeId: rootFid };
    const rows = await db.execute<{ id: string }>(sql`
      SELECT id::text AS id FROM customer
      WHERE ${viewerCustomerScopeSql(viewer)}
      ORDER BY id
    `);
    const visible = rows.map((r) => r.id);
    // root 的「我的」: custMine
    // 下层归属: mid (custOfMid), deep (custOfDeep)
    // 上级推送: 没人推给 root (但 account 也有推送过来, 测上面 single 收单)
    // 这里测试主要是 root 看到: 自有 + 下层归属
    expect(visible).toContain(String(custMine));
    expect(visible).toContain(String(custOfMid));
    expect(visible).toContain(String(custOfDeep));
    // 跨树的看不到 (custOtherTree)
    expect(visible).not.toContain(String(custOtherTree));
    // 上级推送 custod (root 推给 mid, root 自己也看不到 — 自己是推送方, 不是接收方)
    //   推送是单向 (从 root → mid): root 列表不加这条
  });

  it("中层用户 (mid): 自有 + 下层 deep 归属 + 上级推送 (c) 命中", async () => {
    const viewer: CustomerScopeViewer = { userId: midUid, franchiseeId: midFid };
    const rows = await db.execute<{ id: string }>(sql`
      SELECT id::text AS id FROM customer
      WHERE ${viewerCustomerScopeSql(viewer)}
      ORDER BY id
    `);
    const visible = rows.map((r) => r.id);
    // mid 自有客户: custOfMid
    expect(visible).toContain(String(custOfMid));
    // mid 下层归属: custOfDeep
    expect(visible).toContain(String(custOfDeep));
    // 上级推送 (root→mid 推 custShared)
    expect(visible).toContain(String(custShared));
    // 看不到别的树和上层归属 (custMine 是 root 的, 不是 mid 的下层归属)
    //   但 root 是 mid 的**上层** —  推送是 (c) 段, 不含「按图谱可见性看上层」
    //   §3.4 集中点 (a/b1/b2/c) **不含「我的上层归属」** — 即主文档 §1.3 边界
    expect(visible).not.toContain(String(custMine));
    expect(visible).not.toContain(String(custOtherTree));
  });

  it("深层用户 (deep) 看不到 custOfMid (不同枝的下层归属)", async () => {
    const viewer: CustomerScopeViewer = { userId: deepUid, franchiseeId: deepFid };
    const rows = await db.execute<{ id: string }>(sql`
      SELECT id::text AS id FROM customer
      WHERE ${viewerCustomerScopeSql(viewer)}
    `);
    const visible = rows.map((r) => r.id);
    // deep 自有: custOfDeep
    expect(visible).toContain(String(custOfDeep));
    // deep 没有下层 — 所以没有下层归属
    // deep 看不到 custOfMid (mid 是 deep 的上层, 而不是下层)
    expect(visible).not.toContain(String(custOfMid));
    // 跨树: custOtherTree 不可见
    expect(visible).not.toContain(String(custOtherTree));
  });

  it("跨树用户 (otherTree) 看不到 root 的客户 (多根防护, root_id IS NOT DISTINCT FROM)", async () => {
    const viewer: CustomerScopeViewer = { userId: otherTreeUid, franchiseeId: otherTreeFid };
    const rows = await db.execute<{ id: string }>(sql`
      SELECT id::text AS id FROM customer
      WHERE ${viewerCustomerScopeSql(viewer)}
      ORDER BY id
    `);
    const visible = rows.map((r) => r.id);
    // otherTree 自己 owner 的: custOtherTree
    expect(visible).toContain(String(custOtherTree));
    // 不见 root 系的所有客户
    expect(visible).not.toContain(String(custMine));
    expect(visible).not.toContain(String(custOfMid));
    expect(visible).not.toContain(String(custOfDeep));
    // 不见 root 推给 mid 的 custShared (跨树)
    expect(visible).not.toContain(String(custShared));
  });

  it("viewer.franchiseeId = null (未加盟) → 仅 (a) 段, 其它三段退化", async () => {
    const viewer: CustomerScopeViewer = { userId: rootUid, franchiseeId: null };
    const rows = await db.execute<{ id: string }>(sql`
      SELECT id::text AS id FROM customer
      WHERE ${viewerCustomerScopeSql(viewer)}
    `);
    const visible = rows.map((r) => r.id);
    // (a): custMine
    expect(visible).toContain(String(custMine));
    // (b1) / (b2) / (c) 退化: 看不到中层/深层 (无枝可走)
    expect(visible).not.toContain(String(custOfMid));
    expect(visible).not.toContain(String(custOfDeep));
    // 注: custShared 的 owner = rootUid 本人, 因此它本来就属 (a) 段 —— 不能拿它当
    //     「(c) 退化」的证据 (旧断言有误, 已修); (c) 退化由上面 「viewer.userId = rootUid
    //     + franchiseeId = null → 看不到 mid 下层客户」 共同证明。
  });

  it("软删 customer 排除 (E1: viewerCustomerScopeSql 内部 deleted_at IS NULL)", async () => {
    // 取一个 mid 的客户做临时删除
    const tmpSeq = "88888";
    const phone = PHONE_SEG + "8" + tmpSeq.padStart(5, "0").slice(-5);
    const phoneHash = hashForLookup(phone);
    const [c] = await db
      .insert(customer)
      .values({
        name: `${TAG}-softdel-${tmpSeq}`,
        phoneEncrypted: encryptField(phone),
        phoneHash,
        createdBy: rootUid,
        ownerId: rootUid,
        // 软删
        deletedAt: new Date(),
      })
      .returning({ id: customer.id });

    const viewer: CustomerScopeViewer = { userId: rootUid, franchiseeId: rootFid };
    const rows = await db.execute<{ id: string }>(sql`
      SELECT id::text AS id FROM customer
      WHERE ${viewerCustomerScopeSql(viewer)}
    `);
    const visible = rows.map((r) => r.id);
    expect(visible).not.toContain(c.id.toString());
    // 清理
    await db.delete(customer).where(eq(customer.id, c.id));
  });

  it("软删 franchisee 排除 (B1 / §3.4 (b2) INV-4: f.deleted_at IS NULL)", async () => {
    // 把 mid 软删 (接下层 deep 也应被排除)
    const [oldMid] = await db
      .select({ deletedAt: franchisee.deletedAt })
      .from(franchisee)
      .where(eq(franchisee.id, midFid))
      .limit(1);
    await db
      .update(franchisee)
      .set({ deletedAt: new Date(), isActive: false })
      .where(eq(franchisee.id, midFid));
    const viewer: CustomerScopeViewer = { userId: rootUid, franchiseeId: rootFid };
    const rows = await db.execute<{ id: string }>(sql`
      SELECT id::text AS id FROM customer
      WHERE ${viewerCustomerScopeSql(viewer)}
    `);
    const visible = rows.map((r) => r.id);
    // 口径 (主文档 §3.4 (b2) 的 `sub.deleted_at IS NULL`): **只判节点自身**
    //   · mid 本人软删 → 她归属的客户不再进 (b2) 段 (找不到她这个下层节点)
    expect(visible).not.toContain(String(custOfMid));
    //   · deep 的节点活着 → 她的客户仍可见 (子树可见性**不**随祖先软删级联失效;
    //     祖先软删后的结构问题由 reparent / audit-placement-integrity 处理)
    expect(visible).toContain(String(custOfDeep));
    expect(visible).toContain(String(custMine));
    // 还原
    await db
      .update(franchisee)
      .set({ deletedAt: oldMid?.deletedAt ?? null, isActive: true })
      .where(eq(franchisee.id, midFid));
  });
});

// 助手函数: 为了让某些 SQL 模板常量与类型明确, 这里不抽函数 (本文件前面用例都内联用 viewerCustomerScopeSql)。
// 引用 `SQL` 类型仅为上文导入; 及刚导入 `and, isNull` 为后续可扩展使用集中点。
