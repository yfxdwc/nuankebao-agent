// POST /api/billing/referral/claim — 新用户填推荐码 (ADR-0012 §6)
//
// 规则 (主人 2026-09-19 拍):
//   - 注册时可选填; 注册后不可补填 (本接口只应在注册流程里调, 二次调用会被唯一索引挡住)
//   - 被推荐人: 立即得 15 天会员权益
//   - 推荐人: **被推荐人成为加盟者后**才发 (D23) → 这里只建 pending 关系
//
// 边界:
//   - 不能推荐自己 / 同一手机号 hash / 同一 IP → 待人工审 (见 checkReferralEligibility)
//   - 一人一生只能被推荐一次 ((referrer, referee) 唯一索引兜底)
//   - 奖励是**服务权益**, 不可提现/转让/折现

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { claimReferralCode } from "@/lib/billing/entitlements";
import { hashForLookup } from "@/lib/crypto/field";
import { logger } from "@/lib/errors";

const Schema = z.object({
  code: z.string().min(1).max(20),
  /** 可选: 注册时填的手机号明文 → 只用来算 hash 做反作弊, 用完即丢不落库 */
  phone: z.string().regex(/^1[3-9]\d{9}$/).optional(),
});

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    // dev DEV_SKIP_AUTH 下没有身份, 谈不上"谁被谁推荐"
    return NextResponse.json(
      { error: "需要登录后才能使用推荐码" },
      { status: 401 }
    );
  }

  try {
    const body = await request.json();
    const input = Schema.parse(body);

    const result = await claimReferralCode({
      refereeUserId: BigInt(session.user.id),
      rawCode: input.code,
      refereePhoneHash: input.phone ? hashForLookup(input.phone) : null,
      refereeIp:
        request.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
        request.headers.get("x-real-ip") ??
        null,
    });

    return NextResponse.json(result, { status: result.accepted ? 200 : 400 });
  } catch (e) {
    if (e instanceof z.ZodError) {
      return NextResponse.json(
        { error: "推荐码格式不对", details: e.errors },
        { status: 400 }
      );
    }
    logger.error("POST /api/billing/referral/claim failed", {}, e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
