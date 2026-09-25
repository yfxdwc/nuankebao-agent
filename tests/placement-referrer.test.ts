// ============================================
// 客户标识体系 Phase B §6 「落位时选择直推者」单测
// ============================================
// 设计: docs/customer-identity-system.md §6 / E1 / E2
// 落地:
//   - migration 0027: franchise_placement_request.referrer_fid (nullable)
//   - createPlacementRequest 校验: 候选链 = targetParentFid + 上层直系 3 层
//   - 默认值: 未传 → initiatorFid (若在链) 否则 = targetParentFid
//   - 执行段 (kind='create'): referrerId = raw.referrerFid ?? raw.initiatorFid
//
// 测试覆盖 (5 例, 任务书):
//   ① 显式选祖先链上的某上层 → 落位后 referrer_id = 她
//   ② 不传 → 默认 = 发起人 (initiator) [若不在链则回退 targetParent]
//   ③ 传一个不在祖先链上的人 → 被拒 (400 语义: "直推者必须在落位后她的祖先链上")
//   ④ 点位父与直推者不同 (BFS 顺延场景) 能正确落库
//   ⑤ 搬树后 referrer 不在链 → 巡检报告为信息级不改数据 (断言 audit 脚本输出含 "允许的例外")
//
// ⚠ 真 DB 测试 (与 tests/customer-audit / idor-follow-up / billing-integration 同模式)
//   不 TRUNCATE 别人的数据; afterAll 按 id 精确删除自己造的。
//
// 每个测试自己造: admin user + 一个独立的 sales user + referral code (目标被推荐人)
// 这样 5 个测试之间不撞唯一索引, 清理也容易。
// ============================================

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { and, eq, inArray, isNull, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  customer,
  franchisee,
  franchisePlacementConfirm,
  franchisePlacementRequest,
  referralCode,
  user,
} from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import { createPlacementRequest } from "@/lib/db/queries/franchisee-placement";
import { adminReparentNode } from "@/lib/db/queries/franchisee-reparent";
import type { AuditContext } from "@/lib/audit/context";

const TAG = `placement-referrer-${Date.now()}`;
const PHONE_ROOT = "13900003301"; // 树根 A
const PHONE_MID = "13900003302"; // 中层 B
const PHONE_LEAF = "13900003303"; // 叶 C

let rootUid: bigint;
let midUid: bigint;
let leafUid: bigint;

let rootFid: bigint;
let midFid: bigint;
let leafFid: bigint;
let rootCustomerId: bigint;
let midCustomerId: bigint;
let leafCustomerId: bigint;
let rootReferralCode: string;

async function mkUserWithCustomer(
  name: string,
  phone: string,
  role: "sales" | "admin" = "sales",
): Promise<{ uid: bigint; cid: bigint }> {
  const phoneHash = hashForLookup(phone);
  const phoneEnc = encryptField(phone);
  const [u] = await db
    .insert(user)
    .values({
      name,
      phoneEncrypted: phoneEnc,
      phoneHash,
      role,
    })
    .returning({ id: user.id });
  const uid = u.id;

  let cid: bigint | null = null;
  if (role !== "admin") {
    const [c] = await db
      .insert(customer)
      .values({
        name,
        phoneEncrypted: phoneEnc,
        phoneHash,
        createdBy: uid,
      })
      .returning({ id: customer.id });
    cid = c.id;
    await db.update(user).set({ customerId: cid }).where(eq(user.id, uid));
  }

  return { uid, cid: cid ?? BigInt(0) };
}

/** 建一个 sales user + 分配邀请码 (不建 franchisee — 由落位来建) */
async function mkSalesUserWithReferralCode(
  suffix: string,
): Promise<{ uid: bigint; cid: bigint; phoneHash: string; referralCode: string }> {
  const phone = `13902${suffix.padStart(7, '0').slice(-7)}`;
  const r = await mkUserWithCustomer(
    `${TAG}-sales-${suffix}`,
    phone,
    "sales",
  );
  const code = `${TAG.slice(-6).toUpperCase()}S${suffix.padStart(2, '0').slice(-2)}`;
  await db
    .insert(referralCode)
    .values({ userId: r.uid, code })
    .onConflictDoNothing();
  return { uid: r.uid, cid: r.cid, phoneHash: hashForLookup(phone), referralCode: code };
}

async function mkFranchisee(
  uid: bigint,
  phone: string,
  name: string,
  placementParentId: bigint | null,
  placementSide: "left" | "right" | null,
  placementPath: string,
  placementDepth: number,
  referrerId: bigint | null,
  rootId: bigint | null,
): Promise<bigint> {
  const phoneHash = hashForLookup(phone);
  const [f] = await db
    .insert(franchisee)
    .values({
      name,
      phoneEncrypted: encryptField(phone),
      phoneHash,
      referrerId,
      placementParentId,
      placementSide,
      placementPath,
      placementDepth,
      rootId,
      isActive: true,
      createdBy: uid,
    })
    .returning({ id: franchisee.id });
  const fid = f.id;
  await db.update(user).set({ franchiseeId: fid }).where(eq(user.id, uid));
  return fid;
}

beforeAll(async () => {
  // 1) 建账号 + 客户档案
  const r = await mkUserWithCustomer(`${TAG}-根A`, PHONE_ROOT, "sales");
  rootUid = r.uid;
  rootCustomerId = r.cid;
  const m = await mkUserWithCustomer(`${TAG}-中层B`, PHONE_MID, "sales");
  midUid = m.uid;
  midCustomerId = m.cid;
  const l = await mkUserWithCustomer(`${TAG}-叶C`, PHONE_LEAF, "sales");
  leafUid = l.uid;
  leafCustomerId = l.cid;

  // 2) 给 root 发邀请码
  const [rc] = await db
    .insert(referralCode)
    .values({ userId: rootUid, code: `${TAG.slice(-6).toUpperCase()}RA` })
    .returning({ code: referralCode.code });
  rootReferralCode = rc.code;

  // 3) 手工插树 (避免 createPlacementRequest 三方确认耗时)
  rootFid = await mkFranchisee(
    rootUid,
    PHONE_ROOT,
    `${TAG}-根A`,
    null,
    null,
    "",
    0,
    null,
    null,
  );
  await db
    .update(franchisee)
    .set({ rootId: rootFid })
    .where(eq(franchisee.id, rootFid));

  midFid = await mkFranchisee(
    midUid,
    PHONE_MID,
    `${TAG}-中层B`,
    rootFid,
    "left",
    "L.",
    1,
    rootFid,
    rootFid,
  );

  leafFid = await mkFranchisee(
    leafUid,
    PHONE_LEAF,
    `${TAG}-叶C`,
    midFid,
    "right", // 放在 right (left 留给新节点落位测试)
    "L.R.",
    2,
    midFid,
    rootFid,
  );
});

afterAll(async () => {
  // ★ 防泄露: 用本测试 TAG 一次性清干净 (避免某次 cleanup 漏字段导致后续 run 报 unique violation)
  const tagPattern = `%${TAG}%`;
  const myUsers = await db
    .select({ id: user.id })
    .from(user)
    .where(sql`name LIKE ${tagPattern}`);
  const myUserIds = myUsers.map((u) => u.id);
  if (myUserIds.length) {
    await db.delete(customer).where(inArray(customer.createdBy, myUserIds));
    await db.delete(customer).where(sql`name LIKE ${tagPattern}`);
    await db.execute(
      sql`DELETE FROM franchise_placement_confirm WHERE confirmer_user_id IN (${sql.join(myUserIds, sql`, `)})`,
    );
    await db.execute(
      sql`DELETE FROM franchise_placement_request WHERE initiator_user_id IN (${sql.join(myUserIds, sql`, `)}) OR result_fid IN (SELECT id FROM franchisee WHERE name LIKE ${tagPattern})`,
    );
    await db.delete(franchisee).where(sql`name LIKE ${tagPattern}`);
    await db.delete(referralCode).where(inArray(referralCode.userId, myUserIds));
    await db.execute(
      sql`DELETE FROM audit_log WHERE record_id IN (${sql.join(myUserIds, sql`, `)})`,
    );
    await db.delete(user).where(inArray(user.id, myUserIds));
  }
});

// helpers: admin 立即落位 (省掉三方确认等待)
async function adminCreate(input: {
  adminId: bigint;
  targetParentFid: bigint;
  newReferralCode: string;
  referrerFid?: bigint;
}) {
  return createPlacementRequest(
    {
      kind: "create",
      initiatorFid: null, // admin 没加盟节点 (Q5)
      initiatorUserId: input.adminId,
      initiatorIsAdmin: true,
      targetParentFid: input.targetParentFid,
      targetSide: "left",
      newReferralCode: input.newReferralCode,
      referrerFid: input.referrerFid,
    },
    { userId: input.adminId, ipAddress: "127.0.0.1" } satisfies AuditContext,
  );
}

// helper: 建一个 admin user (不绑 franchisee / customer, 用于发起)
async function mkAdmin(suffix: string): Promise<bigint> {
  const phone = `13903${suffix.padStart(7, '0').slice(-7)}`;
  const [u] = await db
    .insert(user)
    .values({
      name: `${TAG}-admin-${suffix}`,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      role: "admin",
    })
    .returning({ id: user.id });
  return u.id;
}

// helper: 删除 test 期间产生的所有临时数据 (新节点 + customer + 关联 referral_code)
async function cleanupTestUser(adminId: bigint, salesUid: bigint, salesCid: bigint, salesPhoneHash: string) {
  // 删除新创建的 franchisee (基于 phoneHash 找)
  const newFids = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(eq(franchisee.phoneHash, salesPhoneHash));
  for (const f of newFids) {
    await db
      .delete(franchisePlacementConfirm)
      .where(
        sql`${franchisePlacementConfirm.requestId} IN (SELECT id FROM franchise_placement_request WHERE result_fid = ${f.id})`,
      );
    await db
      .delete(franchisePlacementRequest)
      .where(eq(franchisePlacementRequest.resultFid, f.id));
    await db.delete(franchisee).where(eq(franchisee.id, f.id));
  }
  await db.delete(customer).where(eq(customer.phoneHash, salesPhoneHash));
  await db.delete(referralCode).where(eq(referralCode.userId, salesUid));
  await db.delete(user).where(eq(user.id, salesUid));
  await db.delete(user).where(eq(user.id, adminId));
}

// ============================================
// ① 显式选祖先链上的某上层 → referrer_id = 她
// ============================================
describe("Phase B §6 E1 — 直推者选择", () => {
  it("① 显式选 midFid (B, 上 1 层) 作为新节点的直推者 → 新节点 referrer_id = B", async () => {
    const adminId = await mkAdmin("1");
    const sales = await mkSalesUserWithReferralCode("01");

    const view = await adminCreate({
      adminId,
      targetParentFid: midFid,
      newReferralCode: sales.referralCode,
      referrerFid: midFid,
    });
    expect(view.kind).toBe("create");
    expect(view.status).toBe("executed"); // admin 立即落位

    // 落库: 新节点 referrer_id = midFid, placement_parent_id = midFid
    const [newNode] = await db
      .select({
        id: franchisee.id,
        referrerId: franchisee.referrerId,
        placementParentId: franchisee.placementParentId,
        placementPath: franchisee.placementPath,
      })
      .from(franchisee)
      .where(eq(franchisee.phoneHash, sales.phoneHash))
      .limit(1);
    expect(newNode).toBeDefined();
    expect(newNode?.referrerId).toBe(midFid);
    expect(newNode?.placementParentId).toBe(midFid);
    // path = midFid.path + 'L.' = 'L.L.'
    expect(newNode?.placementPath).toBe("L.L.");

    // request 行 referrer_fid 也存了
    const [req] = await db
      .select({ referrerFid: franchisePlacementRequest.referrerFid })
      .from(franchisePlacementRequest)
      .where(eq(franchisePlacementRequest.id, BigInt(view.id)))
      .limit(1);
    expect(req?.referrerFid).toBe(midFid);

    await cleanupTestUser(adminId, sales.uid, sales.cid, sales.phoneHash);
  });

  it("② 不传 referrerFid → 默认 = initiator (admin → 回退到 targetParent)", async () => {
    const adminId = await mkAdmin("2");
    const sales = await mkSalesUserWithReferralCode("02");

    const view = await adminCreate({
      adminId,
      targetParentFid: midFid,
      newReferralCode: sales.referralCode,
      // 不传 referrerFid
    });
    expect(view.status).toBe("executed");

    // 默认值: initiator 是 admin (fid=null), 不在候选链 → 走 targetParentFid = midFid
    // (admin 发起时 initiatorFid=null, resolveReferrerCandidate 直接回退到 targetParent)
    const [newNode] = await db
      .select({
        id: franchisee.id,
        referrerId: franchisee.referrerId,
        placementParentId: franchisee.placementParentId,
      })
      .from(franchisee)
      .where(eq(franchisee.phoneHash, sales.phoneHash))
      .limit(1);
    expect(newNode?.referrerId).toBe(midFid); // admin 发起时默认 = targetParent
    expect(newNode?.placementParentId).toBe(midFid);

    await cleanupTestUser(adminId, sales.uid, sales.cid, sales.phoneHash);
  });

  it("③ 传一个不在祖先链上的人 → 被拒 (人话错误: '直推者必须在落位后她的祖先链上')", async () => {
    const adminId = await mkAdmin("3");
    const sales = await mkSalesUserWithReferralCode("03");

    // 单独建一个 outsider franchisee (另一棵树的 root) → 不在 midFid 祖先链
    const outsiderSales = await mkSalesUserWithReferralCode("03o");
    const outsiderFid = await mkFranchisee(
      outsiderSales.uid,
      `13904${"03o".padStart(7, '0').slice(-7)}`,
      `${TAG}-外人`,
      null,
      null,
      "", // 另一棵树的 root
      0,
      null,
      null,
    );
    await db
      .update(franchisee)
      .set({ rootId: outsiderFid })
      .where(eq(franchisee.id, outsiderFid));

    // outsiderFid 不在 midFid 祖先链 → 校验必拒
    await expect(
      adminCreate({
        adminId,
        targetParentFid: midFid,
        newReferralCode: sales.referralCode,
        referrerFid: outsiderFid,
      }),
    ).rejects.toThrow(/直推者必须在落位后她的祖先链上/);

    // 清理: outsider + sales
    await db.delete(franchisee).where(eq(franchisee.id, outsiderFid));
    await db
      .delete(customer)
      .where(
        eq(customer.phoneHash, hashForLookup(`13904${"03o".padStart(7, '0').slice(-7)}`)),
      );
    await db
      .delete(referralCode)
      .where(eq(referralCode.userId, outsiderSales.uid));
    await db.delete(user).where(eq(user.id, outsiderSales.uid));
    await cleanupTestUser(adminId, sales.uid, sales.cid, sales.phoneHash);
  });

  it("④ 点位父与直推者不同 (显式选 rootFid 当直推, 但落位在 midFid 左) → 正确落库", async () => {
    const adminId = await mkAdmin("4");
    const sales = await mkSalesUserWithReferralCode("04");

    const view = await adminCreate({
      adminId,
      targetParentFid: midFid,
      newReferralCode: sales.referralCode,
      referrerFid: rootFid, // ★ 直推者 = 根 (BFS 顺延场景的模拟)
    });
    expect(view.status).toBe("executed");

    // placement_parent_id = midFid (落位处), 但 referrer_id = rootFid (拆栏允许两者不同)
    const [newNode] = await db
      .select({
        id: franchisee.id,
        referrerId: franchisee.referrerId,
        placementParentId: franchisee.placementParentId,
      })
      .from(franchisee)
      .where(eq(franchisee.phoneHash, sales.phoneHash))
      .limit(1);
    expect(newNode?.placementParentId).toBe(midFid);
    expect(newNode?.referrerId).toBe(rootFid);
    // ★ 这是拆栏的核心: referrer 与 placement_parent **允许不同**
    expect(newNode?.referrerId).not.toBe(newNode?.placementParentId);

    await cleanupTestUser(adminId, sales.uid, sales.cid, sales.phoneHash);
  });

  it("⑤ 搬树后 referrer 不在链 → 巡检报告为信息级, 不改数据 (E2 允许的例外)", async () => {
    const adminId = await mkAdmin("5");
    const sales = await mkSalesUserWithReferralCode("05");

    // 5.1 落位到 leafFid.left (空位), 显式选 midFid 当直推
    const view = await adminCreate({
      adminId,
      targetParentFid: leafFid,
      newReferralCode: sales.referralCode,
      referrerFid: midFid,
    });
    expect(view.status).toBe("executed");

    const [movedNode] = await db
      .select({ id: franchisee.id, referrerId: franchisee.referrerId })
      .from(franchisee)
      .where(eq(franchisee.phoneHash, sales.phoneHash))
      .limit(1);
    expect(movedNode?.referrerId).toBe(midFid);
    const movedFid = movedNode!.id;
    const movedReqId = BigInt(view.id);

    // 5.2 搬到另一棵树 (用 outsider sales 当新根)
    const outsiderSales = await mkSalesUserWithReferralCode("05o");
    const outsiderFid = await mkFranchisee(
      outsiderSales.uid,
      `13905${"05o".padStart(7, '0').slice(-7)}`,
      `${TAG}-外人`,
      null,
      null,
      "",
      0,
      null,
      null,
    );
    await db
      .update(franchisee)
      .set({ rootId: outsiderFid })
      .where(eq(franchisee.id, outsiderFid));

    await adminReparentNode(
      {
        moveFid: movedFid,
        newParentFid: outsiderFid,
        side: "left",
        reason: "Phase B §6 E2 验证: 搬到另一棵树 → referrer 必然不在链",
        adminUserId: adminId,
      },
      { userId: adminId, ipAddress: "127.0.0.1" } satisfies AuditContext,
    );

    // 5.3 验证: referrer 字段没动 (还是 midFid), 但 rootId 变成 outsiderFid 这棵树
    const [finalState] = await db
      .select({
        id: franchisee.id,
        referrerId: franchisee.referrerId,
        placementParentId: franchisee.placementParentId,
        rootId: franchisee.rootId,
        placementPath: franchisee.placementPath,
      })
      .from(franchisee)
      .where(eq(franchisee.id, movedFid))
      .limit(1);
    // referrer 不级联改 (E2, 保拆栏)
    expect(finalState?.referrerId).toBe(midFid);
    expect(finalState?.rootId).toBe(outsiderFid); // 搬到了 outsiderFid 这棵树
    // placement_path 也变了 (搬走后 = outsiderFid.path + 'L.' = 'L.')
    expect(finalState?.placementPath).toBe("L.");

    // 5.4 验证巡检脚本的同口径 SQL 能查到这条记录 (E2 允许的例外, 不报错)
    const referrerNotInChain = await db.execute<{
      n: number;
    } & Record<string, unknown>>(sql`
      SELECT count(*)::int AS n FROM franchisee child
      WHERE child.deleted_at IS NULL
        AND child.referrer_id IS NOT NULL
        AND child.id = ${movedFid}
        AND NOT EXISTS (
          SELECT 1 FROM franchisee anc
          WHERE anc.deleted_at IS NULL
            AND anc.root_id IS NOT DISTINCT FROM child.root_id
            AND child.placement_path LIKE (anc.placement_path || '%')
            AND anc.id = child.referrer_id
        )
    `);
    expect(referrerNotInChain[0]?.n).toBe(1); // 命中 1 条例外 (信息级, 不级联改)

    // 5.5 清理
    await db
      .delete(franchisePlacementConfirm)
      .where(eq(franchisePlacementConfirm.requestId, movedReqId));
    await db
      .delete(franchisePlacementRequest)
      .where(eq(franchisePlacementRequest.id, movedReqId));
    await db.delete(franchisee).where(eq(franchisee.id, movedFid));
    await db.delete(franchisee).where(eq(franchisee.id, outsiderFid));
    await db.delete(customer).where(eq(customer.phoneHash, sales.phoneHash));
    await db
      .delete(customer)
      .where(
        eq(customer.phoneHash, hashForLookup(`13905${"05o".padStart(7, '0').slice(-7)}`)),
      );
    await db
      .delete(referralCode)
      .where(eq(referralCode.userId, outsiderSales.uid));
    await db.delete(user).where(eq(user.id, outsiderSales.uid));
    await db.delete(referralCode).where(eq(referralCode.userId, sales.uid));
    await db.delete(user).where(eq(user.id, sales.uid));
    await db.delete(user).where(eq(user.id, adminId));
  });
});