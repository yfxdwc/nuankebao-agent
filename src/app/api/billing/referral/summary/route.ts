// GET /api/billing/referral/summary — 我的推荐码 + 进度 (ADR-0012 §6)
//
// 返回:
//   code           我的固定 6 位推荐码
//   grantedDays    我通过推荐累计拿到的天数
//   invitedCount   我推荐过的人 (含 pending)
//   rewardedCount  已经发放奖励的人数 (被推荐人成为加盟者的)
//   remainingThisMonth / remainingTotal  本月/累计还能推荐几次 (封顶 D22)

import { NextResponse } from "next/server";
import { and, count, eq, sql } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { entitlementGrant, referralReward } from "@/lib/db/schema";
import {
  ensureReferralCode,
  referralUsage,
} from "@/lib/billing/entitlements";
import { REFERRAL_MONTHLY_CAP, REFERRAL_TOTAL_CAP } from "@/lib/billing/referral";

export async function GET() {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }
  const userId = BigInt(session.user.id);

  const [code, usage] = await Promise.all([
    ensureReferralCode(userId),
    referralUsage(userId),
  ]);

  const [invited] = await db
    .select({ n: count() })
    .from(referralReward)
    .where(eq(referralReward.referrerUserId, userId));

  const [granted] = await db
    .select({ days: sql<number>`COALESCE(SUM(${entitlementGrant.days}), 0)::int` })
    .from(entitlementGrant)
    .where(eq(entitlementGrant.userId, userId));

  return NextResponse.json({
    code,
    grantedDays: Number(granted?.days ?? 0),
    invitedCount: Number(invited?.n ?? 0),
    rewardedCount: usage.usedTotal,
    remainingThisMonth: Math.max(0, REFERRAL_MONTHLY_CAP - usage.usedThisMonth),
    remainingTotal: Math.max(0, REFERRAL_TOTAL_CAP - usage.usedTotal),
    caps: { monthly: REFERRAL_MONTHLY_CAP, total: REFERRAL_TOTAL_CAP },
  });
}
