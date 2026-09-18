// ============================================
// viewer 上下文 (当前登录者的业务身份)
// ============================================
// 用途: 客户列表的「加盟」类型判定 = 「这位客户是不是**我的下级**加盟商」
//   → 需要先把 session.user.id 转成 franchisee.id (跟客户页图谱 tab 同口径)
//
// 为什么放在 auth/ 而不是 queries/:
//   - 输入是 session (auth 域), 输出只是 id; 多个 route 共用
//   - 不许在这里做业务判断 (只做 session → franchiseeId 解析)
//
// 边界:
//   - session 为空 (dev DEV_SKIP_AUTH / 未登录) → null
//   - user 没绑 franchisee (未加盟) → null
//   - null 语义 = "没有下级" → 客户列表「加盟」恒 0, 种子/普通照常
// ============================================

import { getFranchiseeIdByUserId } from "@/lib/db/queries/franchisee";

export async function resolveViewerFranchiseeId(
  sessionUserId: string | undefined
): Promise<bigint | null> {
  if (!sessionUserId) return null;
  try {
    return await getFranchiseeIdByUserId(BigInt(sessionUserId));
  } catch {
    // session.user.id 不是数字 (理论上不会; 防脏数据把整个列表打挂)
    return null;
  }
}
