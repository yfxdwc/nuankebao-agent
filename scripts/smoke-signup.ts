// ============================================
// 自助注册 (凭推荐码) 冒烟 (dev only) — 主人 2026-09-19/20 拍
//
// 验: ① 注册成功 → 建了 user  ② 同时建了客户档案 (list 里能看到)
//     ③ 客户档案是**普通客户** (is_seed=false)
//     ④ referrer_id **不写** (no_link: 账号推荐关系 ≠ 客户图谱老带新 — ADR-0013 D4, 主人 2026-09-19 拍)
//     ⑤ 归属 owner_id = **null** + 建档人 = 本人 (建号不自动归属推荐人 — ADR-0015 Q12, 2026-09-22 拍)
//     ⑥ 手机号重复 → 409
//
// 跑: npx tsx scripts/smoke-signup.ts   (幂等, 跑完自己清理)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { and, count, eq, isNull } from "drizzle-orm";
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
import { confirmReferral, registerWithReferral } from "@/lib/billing/signup";
import { REFERRAL_GRANT_DAYS } from "@/lib/billing/referral";
import { resolveCustomerType } from "@/lib/db/queries/customer";

const PHONE = "13900006622";
const NAME = "冒烟-自助注册";
const PWD = "Test12345";
let pass = 0, fail = 0;
const ck = (n: string, ok: boolean, extra = "") => {
  console.log(`${ok ? "✅" : "❌"} ${n}${extra ? ` — ${extra}` : ""}`);
  ok ? pass++ : fail++;
};

async function cleanup() {
  const h = hashForLookup(PHONE);
  const us = await db.select({ id: user.id }).from(user).where(eq(user.phoneHash, h));
  for (const u of us) {
    await db.delete(referralReward).where(eq(referralReward.refereeUserId, u.id));
    await db.delete(referralCode).where(eq(referralCode.userId, u.id));
    await db.delete(membership).where(eq(membership.userId, u.id));
    await db.delete(user).where(eq(user.id, u.id));
  }
  await db.delete(customer).where(eq(customer.phoneHash, h));
}

(async () => {
  await cleanup();
  // 推荐人 = user 1 (有推荐码 WRJZAN + 有客户档案)
  const [refUser] = await db
    .select({ id: user.id, phoneHash: user.phoneHash })
    .from(user)
    .where(eq(user.id, BigInt(1)))
    .limit(1);
  const [refCode] = await db
    .select({ code: referralCode.code })
    .from(referralCode)
    .where(eq(referralCode.userId, BigInt(1)))
    .limit(1);
  ck("推荐人有推荐码可用", !!refCode?.code, refCode?.code);

  const res = await registerWithReferral({
    rawCode: refCode!.code,
    rawName: NAME,
    rawPhone: PHONE,
    password: PWD,
  });
  ck("注册成功", !!res.userId, `userId=${res.userId}`);

  const [c] = await db
    .select({
      id: customer.id,
      name: customer.name,
      isSeed: customer.isSeed,
      referrerId: customer.referrerId,
      ownerId: customer.ownerId,
      createdBy: customer.createdBy,
      deletedAt: customer.deletedAt,
    })
    .from(customer)
    .where(and(eq(customer.phoneHash, hashForLookup(PHONE)), isNull(customer.deletedAt)))
    .limit(1);
  ck("建号同时建了客户档案", !!c, `customerId=${c?.id}`);

  // 归属 = NULL (ADR-0015 Q12, 主人 2026-09-22 拍): 建号**不自动**归属推荐人 ——
  //   推荐人在「我推荐的人」页显式添加; 建号只保证"有档案" (AGENTS §6.6)
  ck(
    "客户档案归属为空 (owner_id = null, 等推荐人显式添加)",
    c?.ownerId == null,
    `owner_id=${c?.ownerId ?? "null"} created_by=${c?.createdBy ?? "null"} (建档人应为本人)`
  );
  ck(
    "建档人 = 本人 (自助注册, 档案随她的账号产生)",
    c?.createdBy != null && String(c.createdBy) === String(res.userId),
    `created_by=${c?.createdBy ?? "null"} userId=${res.userId}`
  );

  const [refCustomer] = await db
    .select({ id: customer.id })
    .from(customer)
    .where(and(eq(customer.phoneHash, refUser.phoneHash), isNull(customer.deletedAt)))
    .limit(1);
  // ⚠ no_link (ADR-0013 D4): 推荐码**不写** customer.referrer_id ——
  //   「账号/会员层的推荐关系」和「客户图谱的老带新」是两条线, 各自独立
  ck(
    "客户档案**不挂**推荐人名下 (referrer_id = null, no_link)",
    c?.referrerId == null,
    `referrer_id=${c?.referrerId ?? "null"} 推荐人客户档案=${refCustomer?.id ?? "无"} (故意不挂)`
  );

  // 走真实口径 (resolveCustomerType: 加盟 > 种子 > 普通); 新注册不是加盟 → 看 is_seed
  const t = resolveCustomerType({ isSeed: c!.isSeed }, false);
  ck("列表口径 = 普通客户", t === "normal", `customerType=${t} isSeed=${c!.isSeed}`);

  // ★ 自助注册语义必须保持 (ADR-0015 Q7 建号合并后): source=self_signup + **不立即发权益**
  //   （防码被转发到群里被陌生人白嫖; 主人 2026-09-20 拍）
  const [reward] = await db
    .select({
      id: referralReward.id,
      source: referralReward.source,
      status: referralReward.status,
    })
    .from(referralReward)
    .where(eq(referralReward.refereeUserId, res.userId))
    .limit(1);
  ck(
    "推荐关系 source = self_signup (等推荐人确认才发权益)",
    reward?.source === "self_signup",
    `source=${reward?.source} status=${reward?.status}`
  );
  const [grantBefore] = await db
    .select({ n: count() })
    .from(entitlementGrant)
    .where(eq(entitlementGrant.userId, res.userId));
  ck(
    "确认前: 被推荐人**没**拿到权益 (合并不能变成立即发)",
    Number(grantBefore?.n ?? 0) === 0,
    `grants=${grantBefore?.n ?? 0}`
  );
  // 推荐人点「这是我朋友」→ 被推荐人立刻拿 15 天
  const conf = await confirmReferral({
    referrerUserId: refUser.id,
    rewardId: reward!.id,
  });
  ck(
    "推荐人确认后: 被推荐人拿到 15 天",
    conf.grantedDays === REFERRAL_GRANT_DAYS,
    `grantedDays=${conf.grantedDays} ok=${conf.ok}`
  );

  // 重复手机号 → 拒
  let dupRejected = false;
  try {
    await registerWithReferral({ rawCode: refCode!.code, rawName: NAME, rawPhone: PHONE, password: PWD });
  } catch (e) {
    dupRejected = true;
    console.log("  重复手机号 →", (e as Error).message);
  }
  ck("重复手机号被拒", dupRejected);

  await cleanup();
  console.log(`\n${fail === 0 ? "🎉 全过" : "⚠️ 有失败"} pass=${pass} fail=${fail}`);
  process.exit(fail === 0 ? 0 : 1);
})();
