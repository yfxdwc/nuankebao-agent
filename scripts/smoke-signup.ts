// ============================================
// 自助注册 (凭推荐码) 冒烟 (dev only) — 主人 2026-09-19/20 拍
//
// 验: ① 注册成功 → 建了 user  ② 同时建了客户档案 (list 里能看到)
//     ③ 客户档案是**普通客户** (is_seed=false)
//     ④ referrer_id **不写** (no_link: 账号推荐关系 ≠ 客户图谱老带新 — ADR-0013 D4, 主人 2026-09-19 拍)
//     ⑤ 手机号重复 → 409
//
// 跑: npx tsx scripts/smoke-signup.ts   (幂等, 跑完自己清理)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { and, eq, isNull } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer, membership, referralCode, referralReward, user } from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { registerWithReferral } from "@/lib/billing/signup";
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
      deletedAt: customer.deletedAt,
    })
    .from(customer)
    .where(and(eq(customer.phoneHash, hashForLookup(PHONE)), isNull(customer.deletedAt)))
    .limit(1);
  ck("建号同时建了客户档案", !!c, `customerId=${c?.id}`);

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
