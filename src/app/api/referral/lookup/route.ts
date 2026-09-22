// ============================================
// GET /api/referral/lookup?code=XXXXXX — 按推荐码查人 (身份识别)
// ============================================
// 主人 2026-09-22 拍 (ADR-0015 Q10):
//   推荐码职责 ① = **身份唯一性识别** → 新建客户时填对方推荐码, 快速找到这个人
//
// 返回 (**最小字段**, 不外泄完整手机号 / 健康数据):
//   found      码是否存在 (不存在也返回 200, 前端好渲染"码不对")
//   name       真实姓名
//   phoneMasked 打码手机号 (138****8000)
//   isMember   会员标识 (口径 = member-flag.ts)
//   customerId 对方客户档案 id (admin 豁免建档 → null)
//   claimState claimable | mine | others | no_profile | self
//
// 安全:
//   - 必须登录 (有"我"才有归属口径; claimState 也依赖"我")
//   - **限流 10 次/分钟/用户** (防枚举: 32^6 空间 + 限流 → 暴力遍历不可行)
//   - **审计**: 每次命中写一条 audit_log (table=referral_code, operation=lookup)
//     —— 「按码查人」是新的敏感读路径, 留痕便于事后追查
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { and, eq, isNull } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { auditLog, customer, referralCode, user } from "@/lib/db/schema";
import {
  isValidReferralCodeShape,
  normalizeReferralCode,
} from "@/lib/billing/referral";
import { memberFlagByPhoneHash } from "@/lib/billing/member-flag";
import { decryptField } from "@/lib/crypto/field";
import { maskPhone } from "@/lib/utils";
import { rateLimit, RateLimits, rateLimitResponse } from "@/lib/rate-limit";
import { resolveViewerPhoneHash } from "@/lib/auth/viewer";
import { getAuditContextFromRequest } from "@/lib/audit/context";

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }
  const userId = BigInt(session.user.id);

  // 限流 (按用户, 不按 IP —— 本接口必须登录)
  const limit = rateLimit(`referral-lookup:${userId}`, RateLimits.referralLookup);
  if (!limit.allowed) return rateLimitResponse(limit);

  const raw = new URL(request.url).searchParams.get("code");
  const code = normalizeReferralCode(raw);
  if (!isValidReferralCodeShape(code)) {
    return NextResponse.json(
      { error: "推荐码格式不对 (6 位字母数字)" },
      { status: 400 }
    );
  }

  // 码 → 账号 (只认启用账号)
  const [owner] = await db
    .select({
      id: user.id,
      name: user.name,
      phoneEncrypted: user.phoneEncrypted,
      phoneHash: user.phoneHash,
    })
    .from(referralCode)
    .innerJoin(user, eq(user.id, referralCode.userId))
    .where(and(eq(referralCode.code, code), eq(user.isActive, true)))
    .limit(1);

  if (!owner) {
    return NextResponse.json({ found: false, code });
  }

  // 客户档案 (建号即建档 §6.6; admin 豁免建档 Q5 → null)
  const [profile] = await db
    .select({ id: customer.id, ownerId: customer.ownerId })
    .from(customer)
    .where(and(eq(customer.phoneHash, owner.phoneHash), isNull(customer.deletedAt)))
    .limit(1);

  const myPhoneHash = await resolveViewerPhoneHash(session.user.id);
  const isSelf = myPhoneHash != null && myPhoneHash === owner.phoneHash;

  const claimState = isSelf
    ? "self"
    : profile == null
      ? "no_profile"
      : profile.ownerId == null
        ? "claimable"
        : profile.ownerId === userId
          ? "mine"
          : "others";

  // 审计: 谁 (userId) 在什么时候查了谁的码 (target = 码主人)
  const auditCtx = getAuditContextFromRequest(request, session);
  await db.insert(auditLog).values({
    tableName: "referral_code",
    recordId: owner.id,
    operation: "lookup",
    userId: auditCtx.userId,
    changedFields: { code, claimState },
    ipAddress: auditCtx.ipAddress,
  });

  return NextResponse.json({
    found: true,
    code,
    name: owner.name,
    phoneMasked: maskPhone(decryptField(owner.phoneEncrypted)),
    isMember: await memberFlagByPhoneHash(owner.phoneHash),
    customerId: profile?.id?.toString() ?? null,
    claimState,
  });
}
