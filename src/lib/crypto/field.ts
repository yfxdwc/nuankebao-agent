import crypto from "node:crypto";

// ============================================
// 字段加密封装 (应用层 AES-256-CBC)
//
// 借鉴 HashiCorp Vault 的加密策略 + pgcrypto 双层防护思路
// 详见 docs/references.md §2
//
// 密钥管理: 从环境变量 PGCRYPTO_KEY 读取 (32 bytes hex)
// 生成: openssl rand -hex 32
// 部署: 通过 /etc/nuankebao/secrets/pgcrypto.key 或 Docker secrets 注入
// ============================================

const ALGORITHM = "aes-256-cbc";
const IV_LENGTH = 16; // bytes

/**
 * 密钥缓存 (启动时读一次, 避免每次请求读 env)
 */
let cachedKey: Buffer | null = null;

function getKey(): Buffer {
  if (cachedKey) return cachedKey;

  const keyHex = process.env.PGCRYPTO_KEY;
  if (!keyHex) {
    throw new Error(
      "PGCRYPTO_KEY is not set. 生成方法: openssl rand -hex 32"
    );
  }
  if (keyHex.length !== 64) {
    throw new Error(
      `PGCRYPTO_KEY 长度应为 64 字符 (32 bytes hex), 实际 ${keyHex.length}`
    );
  }

  cachedKey = Buffer.from(keyHex, "hex");
  return cachedKey;
}

/**
 * 加密字段
 * 输出格式: base64(iv + ciphertext)
 */
export function encryptField(plaintext: string): string {
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, getKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  return Buffer.concat([iv, encrypted]).toString("base64");
}

/**
 * 解密字段
 */
export function decryptField(ciphertext: string): string {
  const data = Buffer.from(ciphertext, "base64");
  if (data.length < IV_LENGTH + 1) {
    throw new Error("无效的密文");
  }
  const iv = data.subarray(0, IV_LENGTH);
  const ct = data.subarray(IV_LENGTH);
  const decipher = crypto.createDecipheriv(ALGORITHM, getKey(), iv);
  return Buffer.concat([
    decipher.update(ct),
    decipher.final(),
  ]).toString("utf8");
}

/**
 * 用于查询的 hash 索引 (非安全目的, 仅去重/查找)
 * MD5 比 SHA-256 短, 索引更小, 性能更好
 * 安全敏感场景请用 hashForLookup + HMAC(secret)
 */
export function hashForLookup(plaintext: string): string {
  return crypto.createHash("md5").update(plaintext).digest("hex");
}

/**
 * 安全场景用的 HMAC (例如手机号去重, 防彩虹表)
 */
export function hmacForLookup(plaintext: string): string {
  return crypto
    .createHmac("sha256", getKey())
    .update(plaintext)
    .digest("hex");
}