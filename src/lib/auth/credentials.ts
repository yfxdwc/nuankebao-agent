import { and, eq, or } from "drizzle-orm";
import { db } from "@/lib/db";
import { user } from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { rateLimit, RateLimits } from "@/lib/rate-limit";
import { verifyPassword } from "./password";

// ============================================
// 账号密码登录 — 凭证校验 (Node 侧专用)
//
// ⚠️ 本模块 import DB / crypto / rate-limit, **不能** 被 middleware (Edge) 引用。
//    Edge 侧只 import src/lib/auth/config.ts (2026-09-19 P2 拆分;
//    2026-09-18 实测: DB 进 Edge bundle = 全站 500)。
//
// 登录标识: username (如 admin) 或 手机号 (查 phone_hash)
// ============================================

export interface AuthedUser {
  id: string;
  name: string;
  phone?: string;
  role?: string;
}

export interface ActiveUserRow {
  id: bigint;
  name: string;
  role: string;
  passwordHash: string | null;
}

export function isPhoneIdentifier(value: string): boolean {
  return /^1\d{10}$/.test(value);
}

/**
 * 按 登录名/手机号 找 active 用户 (不校验密码)
 */
export async function findActiveUserByIdentifier(
  identifierRaw: string
): Promise<ActiveUserRow | null> {
  const identifier = identifierRaw.trim();
  if (!identifier) return null;

  const conds = [eq(user.username, identifier)];
  if (isPhoneIdentifier(identifier)) {
    conds.push(eq(user.phoneHash, hashForLookup(identifier)));
  }

  const [row] = await db
    .select({
      id: user.id,
      name: user.name,
      role: user.role,
      passwordHash: user.passwordHash,
    })
    .from(user)
    .where(and(or(...conds), eq(user.isActive, true)))
    .limit(1);

  return row ?? null;
}

/**
 * 账号 + 密码校验 (Auth.js Credentials provider 的 authorize 用它)
 *
 * 频控: 每标识 5 次/分钟 (RateLimits.login, 内存滑动窗口);
 * 超限返回 null (对外统一 "账号或密码错误", 不暴露原因)。
 */
export async function verifyCredentials(
  identifierRaw: string,
  passwordRaw: string
): Promise<AuthedUser | null> {
  const identifier = (identifierRaw ?? "").trim();
  const password = typeof passwordRaw === "string" ? passwordRaw : "";
  if (!identifier || !password) return null;

  const limit = rateLimit(`auth:${identifier}`, RateLimits.login);
  if (!limit.allowed) return null;

  const row = await findActiveUserByIdentifier(identifier);
  if (!row || !verifyPassword(password, row.passwordHash)) return null;

  const result: AuthedUser = {
    id: row.id.toString(),
    name: row.name,
    role: row.role,
  };
  if (isPhoneIdentifier(identifier)) result.phone = identifier;
  return result;
}

/**
 * 按用户 id 校验密码 (改密接口用)
 */
export async function verifyPasswordForUser(
  userId: bigint,
  password: string
): Promise<boolean> {
  const [row] = await db
    .select({ passwordHash: user.passwordHash })
    .from(user)
    .where(eq(user.id, userId))
    .limit(1);
  return !!row && verifyPassword(password, row.passwordHash);
}
