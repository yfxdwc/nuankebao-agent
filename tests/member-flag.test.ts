// ============================================
// 会员标识 (member flag) — 纯函数口径 + 真库 SQL 一致性
// ============================================
// 主人 2026-09-21 拍: 「会员在别人的图谱 / 列表里也要有明显标识, 实时同步的
//   (充值转会员 / 到期掉会员, 图谱和列表都要跟着变)」
//
// 这里验两件事:
//   1. JS 口径 memberFlagOf (纯函数, 10 个边界)
//   2. SQL 口径 memberExistsSql 与 JS 口径**等价**, 且同一节点随 member_until
//      变化实时翻转 (不落库、不缓存 → 充值/到期立刻反映)
//
// ⚠ 本文件往真 DB 写测试数据 (手机号 139000021xx 段), 结束按 id / hash 精确删除

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { eq, inArray, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer, franchisee, membership, user } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import {
  memberExistsSql,
  memberFlagByCustomerId,
  memberFlagByUserId,
  memberFlagOf,
} from "@/lib/billing/member-flag";
import { grantDays } from "@/lib/billing/entitlements";

const TAG = `member-flag-${Date.now()}`;
const PHONE_MEMBER = "13900002101"; // 有会员的账号
const PHONE_ADMIN = "13900002102"; // 管理员 (角色即规则)
const PHONE_EXPIRED = "13900002103"; // 会员已到期
const PHONE_FREE = "13900002104"; // 从没充值过

let uidMember: bigint;
let uidAdmin: bigint;
let uidExpired: bigint;
let uidFree: bigint;
let fidMember: bigint;
let fidNoAccount: bigint;
let cidMember: bigint;
let cidFree: bigint;
let cidNoAccount: bigint;

async function mkUser(name: string, phone: string, role = "sales"): Promise<bigint> {
  const [row] = await db
    .insert(user)
    .values({
      name,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      role,
    })
    .returning({ id: user.id });
  return row.id;
}

/** 直接写 member_until (不走 grantDays 的幂等/审计, 测 read 侧口径用) */
async function setMemberUntil(uid: bigint, until: Date | null) {
  await db
    .insert(membership)
    .values({ userId: uid, memberUntil: until })
    .onConflictDoUpdate({
      target: membership.userId,
      set: { memberUntil: until },
    });
}

/** 节点 → 绑定账号 的会员标识 (与查询层同一 SQL 表达式) */
async function franchiseeMemberFlag(fid: bigint): Promise<boolean> {
  const [row] = await db
    .select({ m: memberExistsSql(sql`u.franchisee_id = ${franchisee.id}`) })
    .from(franchisee)
    .where(eq(franchisee.id, fid));
  return row?.m === true;
}

/** 客户 → 同手机号账号 的会员标识 (与查询层同一 SQL 表达式) */
async function customerMemberFlag(cid: bigint): Promise<boolean> {
  const [row] = await db
    .select({ m: memberExistsSql(sql`u.phone_hash = ${customer.phoneHash}`) })
    .from(customer)
    .where(eq(customer.id, cid));
  return row?.m === true;
}

beforeAll(async () => {
  uidMember = await mkUser(`${TAG}-会员`, PHONE_MEMBER);
  uidAdmin = await mkUser(`${TAG}-管理员`, PHONE_ADMIN, "admin");
  uidExpired = await mkUser(`${TAG}-过期`, PHONE_EXPIRED);
  uidFree = await mkUser(`${TAG}-免费`, PHONE_FREE);

  // 当前有效会员 / 已过期会员 / 免费
  await setMemberUntil(uidMember, new Date(Date.now() + 30 * 86400_000));
  await setMemberUntil(uidExpired, new Date(Date.now() - 86400_000));

  // 加盟节点: 一个挂会员账号, 一个没账号
  const [f1] = await db
    .insert(franchisee)
    .values({
      name: `${TAG}-加盟(会员)`,
      phoneEncrypted: encryptField(PHONE_MEMBER),
      phoneHash: hashForLookup(PHONE_MEMBER),
      placementPath: "",
      placementDepth: 0,
      createdBy: uidAdmin,
    })
    .returning({ id: franchisee.id });
  const [f2] = await db
    .insert(franchisee)
    .values({
      name: `${TAG}-加盟(无账号)`,
      phoneEncrypted: encryptField("13900002109"),
      phoneHash: hashForLookup("13900002109"),
      placementPath: "L.",
      placementDepth: 1,
      createdBy: uidAdmin,
    })
    .returning({ id: franchisee.id });
  fidMember = f1.id;
  fidNoAccount = f2.id;
  await db.update(user).set({ franchiseeId: fidMember }).where(eq(user.id, uidMember));

  // 客户档案: 同手机号有会员账号 / 无账号
  const [c1] = await db
    .insert(customer)
    .values({
      name: `${TAG}-客户(会员)`,
      phoneEncrypted: encryptField(PHONE_MEMBER),
      phoneHash: hashForLookup(PHONE_MEMBER),
      createdBy: uidMember,
    })
    .returning({ id: customer.id });
  const [c2] = await db
    .insert(customer)
    .values({
      name: `${TAG}-客户(免费)`,
      phoneEncrypted: encryptField(PHONE_FREE),
      phoneHash: hashForLookup(PHONE_FREE),
      createdBy: uidMember,
    })
    .returning({ id: customer.id });
  const [c3] = await db
    .insert(customer)
    .values({
      name: `${TAG}-客户(无账号)`,
      phoneEncrypted: encryptField("13900002108"),
      phoneHash: hashForLookup("13900002108"),
      createdBy: uidMember,
    })
    .returning({ id: customer.id });
  cidMember = c1.id;
  cidFree = c2.id;
  cidNoAccount = c3.id;
});

afterAll(async () => {
  const uids = [uidMember, uidAdmin, uidExpired, uidFree].filter((v) => typeof v === "bigint");
  const hashes = [PHONE_MEMBER, PHONE_ADMIN, PHONE_EXPIRED, PHONE_FREE, "13900002108", "13900002109"].map(
    (p) => hashForLookup(p)
  );
  if (uids.length) {
    await db.update(user).set({ franchiseeId: null }).where(inArray(user.id, uids));
    await db.delete(membership).where(inArray(membership.userId, uids));
    await db.delete(user).where(inArray(user.id, uids));
  }
  await db.delete(franchisee).where(inArray(franchisee.phoneHash, hashes));
  await db.delete(customer).where(inArray(customer.phoneHash, hashes));
});

describe("memberFlagOf (纯函数口径)", () => {
  const now = new Date("2026-09-21T00:00:00Z");

  it("role=admin → 永久会员 (角色即规则, 与 getMembership 一致)", () => {
    expect(memberFlagOf("admin", null, now)).toBe(true);
    expect(memberFlagOf("admin", new Date("2020-01-01"), now)).toBe(true);
  });

  it("member_until 在未来 → 会员", () => {
    expect(memberFlagOf("sales", new Date("2026-10-01"), now)).toBe(true);
  });

  it("member_until 已过期 → 非会员 (到期掉标识)", () => {
    expect(memberFlagOf("sales", new Date("2026-09-20"), now)).toBe(false);
  });

  it("member_until = null / undefined / 脏值 → 非会员 (不炸)", () => {
    expect(memberFlagOf("sales", null, now)).toBe(false);
    expect(memberFlagOf("sales", undefined, now)).toBe(false);
    expect(memberFlagOf("sales", "not-a-date", now)).toBe(false);
  });

  it("接受 ISO 字符串 (API 层反序列化后的形态)", () => {
    expect(memberFlagOf("sales", "2026-10-01T00:00:00Z", now)).toBe(true);
    expect(memberFlagOf("sales", "2026-09-01T00:00:00Z", now)).toBe(false);
  });

  it("到期瞬间 (member_until == now) → 非会员 (边界: 严格大于)", () => {
    expect(memberFlagOf("sales", now, now)).toBe(false);
  });
});

describe("memberExistsSql (查询层 SQL) 与口径一致 + 实时翻转", () => {
  it("加盟节点: 绑定的账号是会员 → true", async () => {
    expect(await franchiseeMemberFlag(fidMember)).toBe(true);
  });

  it("加盟节点: 节点没有绑定账号 → false (不炸, 不算会员)", async () => {
    expect(await franchiseeMemberFlag(fidNoAccount)).toBe(false);
  });

  it("客户档案: 同手机号的账号是会员 → true", async () => {
    expect(await customerMemberFlag(cidMember)).toBe(true);
  });

  it("客户档案: 同手机号账号是免费档 → false", async () => {
    expect(await customerMemberFlag(cidFree)).toBe(false);
  });

  it("客户档案: 没有对应账号 → false", async () => {
    expect(await customerMemberFlag(cidNoAccount)).toBe(false);
  });

  it("★ 实时同步: 同一节点 非会员 → 充值转会员 → 到期掉会员 (无需同步任务)", async () => {
    // 1. 先让会员账号过期 → 节点标识消失
    await setMemberUntil(uidMember, new Date(Date.now() - 1000));
    expect(await franchiseeMemberFlag(fidMember)).toBe(false);

    // 2. 送 30 天 (走真实发放路径) → 标识出现
    await grantDays({
      userId: uidMember,
      days: 30,
      reason: "manual",
      idempotencyKey: `${TAG}-flip`,
    });
    expect(await franchiseeMemberFlag(fidMember)).toBe(true);
    expect(await customerMemberFlag(cidMember)).toBe(true);

    // 3. 再到期 → 标识消失
    await setMemberUntil(uidMember, new Date(Date.now() - 1000));
    expect(await franchiseeMemberFlag(fidMember)).toBe(false);
    expect(await customerMemberFlag(cidMember)).toBe(false);
  });

  it("单条判定 (详情页 / 新建客户响应): 走 ID, 不走手机号 (ADR-0016 D3)", async () => {
    await setMemberUntil(uidMember, new Date(Date.now() + 86400_000));
    // 客户档案侧: user.customer_id 连接
    expect(await memberFlagByCustomerId(cidMember)).toBe(true);
    expect(await memberFlagByCustomerId(cidFree)).toBe(false);
    // 账号侧: 直接比 user id
    expect(await memberFlagByUserId(uidMember)).toBe(true);
    expect(await memberFlagByUserId(uidFree)).toBe(false);
    // 不存在的 id → false (不炸)
    expect(await memberFlagByUserId(BigInt(999999))).toBe(false);
  });

  it("管理员账号 (没充值) → true (角色即规则)", async () => {
    const [f] = await db
      .insert(franchisee)
      .values({
        name: `${TAG}-加盟(管理员)`,
        phoneEncrypted: encryptField(PHONE_ADMIN),
        phoneHash: hashForLookup(PHONE_ADMIN),
        placementPath: "R.",
        placementDepth: 1,
        createdBy: uidAdmin,
      })
      .returning({ id: franchisee.id });
    await db.update(user).set({ franchiseeId: f.id }).where(eq(user.id, uidAdmin));
    expect(await franchiseeMemberFlag(f.id)).toBe(true);
    await db.update(user).set({ franchiseeId: null }).where(eq(user.id, uidAdmin));
    await db.delete(franchisee).where(eq(franchisee.id, f.id));
  });
});
