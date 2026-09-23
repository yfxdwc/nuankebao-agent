// ============================================
// 「绑定 app 身份」冒烟 (dev) — 主人 2026-09-22 场景
// ============================================
// 场景: 销售先**手工建档**一位客户 (手机号可能是随手记的/写错的) → 这位客户后来
//       自己注册了 app (用她自己的号) → 系统按她的号**又自动建了一条空档案** →
//       两边散着。销售在客户详情页填她的**邀请码 (身份识别码)** → 绑定身份。
//
// 验:
//   ① 绑定成功: user.customer_id 指向**手工那条** (不是系统那条)
//   ② 接管: 系统自动建的那条空档案被删掉 (不丢数据 —— 它本来没记录)
//   ③ 手机号对齐: 手工档案的手机号更新成她账号里的真号
//   ④ 列表标识: 该客户 hasAccount = true (UI 显示「已注册」)
//   ⑤ 幂等: 再绑一次 → alreadyBound, 不报错
//   ⑥ 拒绝: 不存在的码 → CODE_NOT_FOUND; 别人已绑的号 → BOUND_TO_OTHER
//
// 跑: npx tsx scripts/smoke-bind-account.ts   (幂等, 跑完自己清理)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { and, eq, isNull, sql } from "drizzle-orm";

import { db } from "@/lib/db";
import {
  customer,
  entitlementGrant,
  membership,
  referralCode,
  referralReward,
  user,
} from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile } from "@/lib/auth/registration";
import {
  bindCustomerAccount,
  createCustomer,
  describeExistingCustomerByPhone,
  listCustomers,
} from "@/lib/db/queries/customer";

const OWNER_PHONE = "13900002201"; // 建号的"销售" (演员)
const TARGET_PHONE = "13900002202"; // 客户注册时用的真号
const WRONG_PHONE = "13900002203"; // 销售建档时写错的号
const OWNER_NAME = "冒烟-绑定-销售";
const TARGET_NAME = "冒烟-绑定-客户";

let pass = 0;
let fail = 0;
const ck = (n: string, ok: boolean, extra = "") => {
  console.log(`${ok ? "✅" : "❌"} ${n}${extra ? ` — ${extra}` : ""}`);
  ok ? pass++ : fail++;
};

async function cleanup(): Promise<void> {
  const hashes = [OWNER_PHONE, TARGET_PHONE, WRONG_PHONE].map(hashForLookup);
  const users = await db
    .select({ id: user.id, cid: user.customerId })
    .from(user)
    .where(sql`${user.phoneHash} IN (${sql.join(hashes.map((h) => sql`${h}`), sql`, `)})`);
  for (const u of users) {
    await db.delete(referralReward).where(eq(referralReward.refereeUserId, u.id));
    await db.delete(referralCode).where(eq(referralCode.userId, u.id));
    await db.delete(entitlementGrant).where(eq(entitlementGrant.userId, u.id));
    await db.delete(membership).where(eq(membership.userId, u.id));
    await db.update(user).set({ customerId: null }).where(eq(user.id, u.id));
    await db.delete(user).where(eq(user.id, u.id));
  }
  await db.delete(customer).where(sql`${customer.phoneHash} IN (${sql.join(hashes.map((h) => sql`${h}`), sql`, `)})`);
  // 顺带清掉可能残留的"接管目标"档案
  await db.delete(customer).where(sql`${customer.name} = ${TARGET_NAME}`);
}

async function main(): Promise<void> {
  await cleanup();
  const ctx = { userId: 1n, ipAddress: null };

  // ── 演员 ──
  const owner = await createAccountWithProfile({
    name: OWNER_NAME,
    phone: OWNER_PHONE,
    password: "Test12345",
    role: "sales",
    allowNoReferral: true,
    actorUserId: 1n,
  });
  ck("销售账号就绪", !!owner.userId, `userId=${owner.userId}`);

  // ① 销售手工建档 (手机号是"错的", 与她后来注册的号不一致)
  const manual = await createCustomer(
    { name: TARGET_NAME, phone: WRONG_PHONE, isSeed: false },
    ctx,
    owner.userId
  );
  const manualId = BigInt(manual.id);
  ck("手工建档成功 (手机号与本人不符)", manual.id.length > 0, `customerId=${manual.id}`);

  // ② 她后来自己注册 app (用她的真号) → 系统按她的号自动建了另一条空档案
  const target = await createAccountWithProfile({
    name: TARGET_NAME,
    phone: TARGET_PHONE,
    password: "Test12345",
    role: "sales",
    allowNoReferral: true,
    actorUserId: owner.userId,
  });
  const autoProfileId = target.customerId!;
  ck(
    "她注册后系统自动建了另一条档案 (两边散着)",
    autoProfileId !== manualId,
    `自动档案=${autoProfileId} ≠ 手工档案=${manualId}`
  );

  const [rc] = await db
    .select({ code: referralCode.code })
    .from(referralCode)
    .where(eq(referralCode.userId, target.userId));
  ck("拿到她的邀请码", !!rc?.code, rc?.code);

  // ③ 绑定: 填她的邀请码
  const res = await bindCustomerAccount(manualId, rc!.code, {}, ctx);
  ck("绑定成功", res.ok === true, res.ok ? "ok" : res.code);
  if (!res.ok) {
    await cleanup();
    process.exit(1);
  }
  ck("接管了她注册时自动建的空档案", res.replacedEmptyProfile === true);
  ck("手机号已对齐成她的真号", res.phoneSynced === true, `mismatch=${res.phoneMismatch}`);

  // ④ DB 核对
  const [u] = await db
    .select({ customerId: user.customerId })
    .from(user)
    .where(eq(user.id, target.userId))
    .limit(1);
  ck("user.customer_id 指向**手工那条**", String(u?.customerId) === String(manualId), `customer_id=${u?.customerId}`);
  const [stale] = await db
    .select({ id: customer.id })
    .from(customer)
    .where(eq(customer.id, autoProfileId))
    .limit(1);
  ck("自动建的空档案已删除 (腾出手机号)", stale == null);

  const [manualRow] = await db
    .select({ phoneHash: customer.phoneHash })
    .from(customer)
    .where(eq(customer.id, manualId))
    .limit(1);
  ck(
    "手工档案的手机号 = 她的真号",
    manualRow?.phoneHash === hashForLookup(TARGET_PHONE)
  );

  // ⑤ 列表标识: 该档案 hasAccount = true
  const listed = await listCustomers({
    search: TARGET_NAME,
    viewerFranchiseeId: null,
  });
  const me = listed.items.find((i) => i.id === manualId.toString());
  ck("列表里该客户 已注册 (hasAccount)", me?.hasAccount === true);

  // ⑥ 幂等
  const again = await bindCustomerAccount(manualId, rc!.code, {}, ctx);
  ck("重复绑定 → 幂等 (alreadyBound)", again.ok === true && again.alreadyBound === true);

  // ⑦ 错误分支
  const bad = await bindCustomerAccount(manualId, "ZZZZZZ", {}, ctx);
  ck("不存在的码 → CODE_NOT_FOUND", bad.ok === false && bad.code === "CODE_NOT_FOUND");

  // 别人已绑的档案: 拿销售自己的档案试 (她的账号已绑自己的档案)
  const ownerProfile = await describeExistingCustomerByPhone(hashForLookup(OWNER_PHONE));
  const [ownerCode] = await db
    .select({ code: referralCode.code })
    .from(referralCode)
    .where(eq(referralCode.userId, owner.userId));
  if (ownerProfile && ownerCode) {
    const conflict = await bindCustomerAccount(manualId, ownerCode.code, {}, ctx);
    ck(
      "账号已绑别人的档案 → BOUND_TO_OTHER",
      conflict.ok === false && conflict.code === "BOUND_TO_OTHER",
      conflict.ok ? "ok(不应该)" : conflict.code
    );
  }

  await cleanup();
  console.log(`\n${fail === 0 ? "🎉 全过" : "⚠️ 有失败"} pass=${pass} fail=${fail}`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error("❌ 失败:", e instanceof Error ? e.message : String(e));
  await cleanup().catch(() => {});
  process.exit(1);
});
