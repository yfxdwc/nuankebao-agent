import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";

// ============================================
// 密码哈希 (Node 内置 scrypt — 不引第三方依赖)
//
// 存储格式: scrypt$N$salt_hex$hash_hex
//   - N 存进哈希里, 未来调成本 (如 2^15) 时旧哈希仍可按各自参数校验, 天然向后兼容
//   - 参数: N=16384 (2^14), r=8, p=1, keylen=64
// 依据: docs/deploy/production-plan.md §1.1 (账号密码登录, 邀请制)
// ============================================

const DEFAULT_N = 16384;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const KEY_LEN = 64;
const SALT_LEN = 16;

export function hashPassword(password: string): string {
  const salt = randomBytes(SALT_LEN);
  const hash = scryptSync(password, salt, KEY_LEN, {
    N: DEFAULT_N,
    r: SCRYPT_R,
    p: SCRYPT_P,
  });
  return `scrypt$${DEFAULT_N}$${salt.toString("hex")}$${hash.toString("hex")}`;
}

/**
 * 校验密码。stored 为空/格式错/算法不符 → false (不抛异常)。
 */
export function verifyPassword(
  password: string,
  stored: string | null | undefined
): boolean {
  if (!stored || typeof password !== "string") return false;

  const parts = stored.split("$");
  if (parts.length !== 4 || parts[0] !== "scrypt") return false;

  const n = Number(parts[1]);
  const salt = Buffer.from(parts[2], "hex");
  const expected = Buffer.from(parts[3], "hex");
  if (!Number.isInteger(n) || n <= 0 || salt.length === 0 || expected.length === 0) {
    return false;
  }

  try {
    const actual = scryptSync(password, salt, expected.length, {
      N: n,
      r: SCRYPT_R,
      p: SCRYPT_P,
    });
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  } catch {
    // 参数非法 (N 非 2 的幂等) → 视为校验失败
    return false;
  }
}

/**
 * 密码强度: 至少 8 位, 同时含字母和数字 (邀请制内部系统的最低要求)
 */
export function isValidPassword(password: string): boolean {
  if (typeof password !== "string") return false;
  if (password.length < 8) return false;
  if (!/[A-Za-z]/.test(password)) return false;
  if (!/\d/.test(password)) return false;
  return true;
}

export const PASSWORD_POLICY_MESSAGE = "密码至少 8 位, 需同时包含字母和数字";
