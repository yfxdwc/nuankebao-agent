// ============================================
// 建号不变量冒烟 (dev only) — 主人 2026-09-19 拍
//
// 验: ① 非 admin 无推荐码 → 拒  ② 建号即强制建客户档案 (+ 自己的推荐码 + 推荐人归属)
//     ③ 客户图谱推荐人 = 空 (no_link)  ④ admin 免推荐码 **且豁免建档** (ADR-0015 Q5, 2026-09-22)
//
// 跑: npx tsx scripts/smoke-registration.ts   (幂等, 跑完自己清理)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { user, customer, referralCode, referralReward, membership } from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile, RegistrationError } from "@/lib/auth/registration";

const PHONE1 = "13900007701";
const PHONE2 = "13900007702";
let pass = 0, fail = 0;
const ck = (n: string, ok: boolean, extra = "") => { console.log(`${ok ? "✅" : "❌"} ${n}${extra ? " — " + extra : ""}`); ok ? pass++ : fail++; };

async function cleanup() {
  for (const p of [PHONE1, PHONE2]) {
    const h = hashForLookup(p);
    const us = await db.select({ id: user.id }).from(user).where(eq(user.phoneHash, h));
    for (const u of us) {
      await db.delete(referralReward).where(eq(referralReward.refereeUserId, u.id));
      await db.delete(referralReward).where(eq(referralReward.referrerUserId, u.id));
      await db.delete(referralCode).where(eq(referralCode.userId, u.id));
      await db.delete(membership).where(eq(membership.userId, u.id));
      await db.delete(user).where(eq(user.id, u.id));
    }
    await db.delete(customer).where(eq(customer.phoneHash, h));
  }
}

(async () => {
  await cleanup();

  // ① 非 admin 无推荐码 → 拒
  try {
    await createAccountWithProfile({ name: "测试-无码", phone: PHONE1, password: "Test1234", actorUserId: BigInt(1) });
    ck("非 admin 无推荐码 → 应被拒", false, "居然成功了");
  } catch (e) {
    ck("非 admin 无推荐码 → 被拒", e instanceof RegistrationError && e.message.includes("必须填推荐码"), (e as Error).message);
  }

  // ② 带推荐码建号 → 账号 + 客户档案 + 自己的码 + 推荐人
  const r = await createAccountWithProfile({
    name: "测试-有码", phone: PHONE1, password: "Test1234",
    referralCode: "WRJZAN", actorUserId: BigInt(1),
  });
  ck("建号成功, 客户档案已建", r.customerCreated === true, `customerId=${r.customerId}`);
  ck("推荐码已受理, 推荐人 = user 1", r.referralAccepted && String(r.referrerUserId) === "1", `referrer=${r.referrerUserId}`);
  ck("自己也被分配推荐码", (r.ownReferralCode ?? "").length === 6, r.ownReferralCode);
  const [c1] = await db
    .select({ id: customer.id, referrerId: customer.referrerId })
    .from(customer)
    .where(eq(customer.phoneHash, hashForLookup(PHONE1)));
  ck("客户档案存在", !!c1);
  ck(
    "客户图谱推荐人 = 空 (主人拍: no_link)",
    (c1?.referrerId ?? null) == null,
    `referrerId=${c1?.referrerId ?? "null"}`
  );

  // ③ 重复手机号 → 409
  try {
    await createAccountWithProfile({ name: "测试-重复", phone: PHONE1, password: "Test1234", referralCode: "WRJZAN", actorUserId: BigInt(1) });
    ck("重复手机号 → 应被拒", false);
  } catch (e) {
    ck("重复手机号 → 被拒", e instanceof RegistrationError && e.status === 409, (e as Error).message);
  }

  // ④ admin 无码 (allowNoReferral) → 放行 + **豁免建档** (ADR-0015 Q5, 2026-09-22 拍)
  const r2 = await createAccountWithProfile({
    name: "测试-admin", phone: PHONE2, role: "admin", password: "Test1234",
    allowNoReferral: true, actorUserId: BigInt(1),
  });
  ck("admin 无推荐码 → 放行", r2.referralAccepted || r2.referralRejectedReason == null, `reason=${r2.referralRejectedReason}`);
  ck(
    "admin 豁免建档 (不建客户档案, customerId=null)",
    r2.customerCreated === false && r2.customerId == null,
    `customerId=${r2.customerId} customerCreated=${r2.customerCreated}`
  );
  const [adminProfile] = await db
    .select({ id: customer.id })
    .from(customer)
    .where(eq(customer.phoneHash, hashForLookup(PHONE2)));
  ck("DB 确认: admin 手机号名下无客户档案", !adminProfile, `customerId=${adminProfile?.id ?? "无"}`);

  await cleanup();
  console.log(`\n${fail === 0 ? "🎉 全过" : "⚠️ 有失败"} pass=${pass} fail=${fail}`);
  process.exit(fail === 0 ? 0 : 1);
})();
