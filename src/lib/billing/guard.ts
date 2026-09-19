// ============================================
// 会员判权的 route 级守卫 (Next.js)
// ============================================
// 用法 (每个会员功能 route 的第一行, 紧跟登录校验之后):
//
//   const gate = await featureGuard(session?.user?.id, FEATURES.AI_FOLLOW_UP);
//   if (gate) return gate;
//
// 为什么单独一个文件: entitlements.ts 是纯业务层 (不 import next/server),
// 方便单测与脚本复用; 只有 route 才需要 NextResponse

import { NextResponse } from "next/server";
import { BillingError, requireFeature } from "./entitlements";
import type { FeatureKey } from "./features";

/**
 * 会员功能守门
 *
 * 返回 null = 放行; 返回 NextResponse = 直接 return 给客户端
 *
 * 边界:
 *   - sessionUserId 为空 (dev DEV_SKIP_AUTH / 未登录) → 放行, 各 route 自己已有的
 *     auth 分支负责 401 (不在这里重复判断, 保持行为兼容)
 *   - sessionUserId 不是数字 → 当未登录处理 (放行, 让业务层报 401/404)
 *   - 非会员 → 402 + code=MEMBERSHIP_REQUIRED (客户端据此弹"开通会员")
 */
export async function featureGuard(
  sessionUserId: string | null | undefined,
  key: FeatureKey
): Promise<NextResponse | null> {
  if (!sessionUserId || !/^\d+$/.test(sessionUserId)) return null;

  try {
    await requireFeature(BigInt(sessionUserId), key);
    return null;
  } catch (e) {
    if (e instanceof BillingError) {
      return NextResponse.json(
        { error: e.message, code: e.code },
        { status: e.status }
      );
    }
    throw e;
  }
}

/**
 * 非抛异常版判权 (给"读数据时降级"的场景用, 如生日提醒字段)
 *
 * 返回 true = 有权限 (或 dev 无 session, 与 featureGuard 口径一致不拦)
 * 返回 false = 非会员 → 调用方把该字段读成 null / 隐藏入口
 */
export async function hasFeatureAccess(
  sessionUserId: string | null | undefined,
  key: FeatureKey
): Promise<boolean> {
  if (!sessionUserId || !/^\d+$/.test(sessionUserId)) return true;
  try {
    await requireFeature(BigInt(sessionUserId), key);
    return true;
  } catch (e) {
    if (e instanceof BillingError) return false;
    throw e;
  }
}

/** 会员功能被拒时的统一响应体 (客户端文案用) */
export const MEMBERSHIP_REQUIRED_CODE = "MEMBERSHIP_REQUIRED";
