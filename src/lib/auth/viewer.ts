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

import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { user } from "@/lib/db/schema";
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

/**
 * session → 当前登录者的**手机号 hash** (账号 ↔ 客户档案的关联约定)
 *
 * 用途: 客户列表 / 客户图谱 / 数据概览要排掉「自己的客户档案」
 *   (自己不应该是自己的客户, 主人 2026-09-22 拍)。
 *   口径与 AGENTS §6.6 一致: 同手机号 = 同一个人。
 *
 * 边界: 未登录 (dev 空 session) / 账号没手机号 / id 是脏数据 → null (调用方不排除任何行)
 */
export async function resolveViewerPhoneHash(
  sessionUserId: string | undefined
): Promise<string | null> {
  if (!sessionUserId) return null;
  try {
    const [u] = await db
      .select({ phoneHash: user.phoneHash })
      .from(user)
      .where(eq(user.id, BigInt(sessionUserId)))
      .limit(1);
    return u?.phoneHash ?? null;
  } catch {
    return null;
  }
}

// ============================================
// 落位「三方确认」用身份 (主人 2026-09-18 拍)
// ============================================
// 需要三样东西:
//   - userId     → 审计 / 确认记录
//   - fid        → 我是哪个加盟商 (目标父节点 / 发起人 判定)
//   - phoneHash  → 匹配「新加盟商本人」(create 单里对方还没加盟商记录, 只能认手机号)
//   - isAdmin    → 系统管理员设置加盟免多方确认 (主人 2026-09-19 拍)
export interface PlacementActorContext {
  userId: bigint;
  fid: bigint | null;
  phoneHash: string | null;
  isAdmin: boolean;
}

export async function resolvePlacementActor(
  sessionUserId: string | undefined
): Promise<PlacementActorContext | null> {
  if (!sessionUserId) return null;
  try {
    const uid = BigInt(sessionUserId);
    const [u] = await db
      .select({
        fid: user.franchiseeId,
        phoneHash: user.phoneHash,
        role: user.role,
      })
      .from(user)
      .where(eq(user.id, uid))
      .limit(1);
    return {
      userId: uid,
      fid: u?.fid ?? null,
      phoneHash: u?.phoneHash ?? null,
      isAdmin: u?.role === "admin",
    };
  } catch {
    return null;
  }
}
