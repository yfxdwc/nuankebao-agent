// ============================================
// dev-fallback-user: dev skip-auth 模式下, 从 DB 拿 admin user.id 兜底
// ============================================
//
// 背景:
//   middleware 跳过 /admin/* 的登录检查 (DEV_SKIP_AUTH=1 + NODE_ENV !== production)
//   → 主人浏览器能直接进 admin 页; 但浏览器**没有** session cookie
//   → API route 里 `await auth()` 返回 null, session?.user?.id = undefined
//   → 我自己写 API 时直接 401, 主人浏览器看不到数据
//
//   方案: dev skip-auth + 无 session → 兜底查 DB 拿 role='admin' 的第一个 user.id
//   注意:
//     - 生产 (NODE_ENV=production) 永远走真 session, 不会走这个兜底
//     - dev skip-auth 必须显式 opt-in (DEV_SKIP_AUTH=1), 不会误触发
//     - 多 admin 时取 LIMIT 1 (主人机器只有一个 admin, 实测)
//
//   ⚠ 仅 admin 自用端点调用 (主人拍板 Q5: "仅 admin (主人自己)")
//     非 admin 端点不要用, 不然 manager/sales 角色也被赋予 admin 视角
// ============================================

import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { user } from "@/lib/db/schema";
import { isAuthSkipped } from "./skip-auth";

/**
 * dev skip-auth 时, 从 DB 取第一个 admin user.id 兜底
 * 返回 null = 兜底失败 (DB 没 admin 行, 或生产模式)
 */
export async function getDevFallbackAdminUserId(): Promise<bigint | null> {
  if (!isAuthSkipped()) return null;
  try {
    const [row] = await db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.role, "admin"))
      .limit(1);
    return row?.id ?? null;
  } catch {
    return null;
  }
}