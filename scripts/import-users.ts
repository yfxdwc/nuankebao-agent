#!/usr/bin/env -S npx tsx
// ============================================
// 暖客宝 邀请制批量导入用户 (P2)
//
// CSV 格式 (UTF-8, 第一行可选表头):
//   name,phone,role,initial_password,username
//   张三,13900000001,sales,Abcd1234,
//   李四,13900000002,manager,,          # 密码留空 = 随机生成并打印一次
//
// - role: admin | manager | sales (默认 sales)
// - initial_password: 留空则随机生成 (打印一次, 由主人分发)
// - username: 留空默认用手机号 (手机号本身就是登录账号)
//
// 用法:
//   pnpm tsx scripts/import-users.ts users.csv
//   pnpm tsx scripts/import-users.ts users.csv --dry-run
//
// 行为:
//   - 幂等: phone_hash 已存在的行跳过 (不覆盖现有人名/密码)
//   - 手机号走 AES 加密 + md5(phone) 查询 hash (与 customer 同口径)
//   - 密码 scrypt 哈希 (src/lib/auth/password.ts)
// ============================================

import { config as loadEnv } from "dotenv";
loadEnv({ path: ".env.local" });

import { readFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { user } from "@/lib/db/schema";
import { hashPassword, isValidPassword, PASSWORD_POLICY_MESSAGE } from "@/lib/auth/password";
import { encryptField, hashForLookup } from "@/lib/crypto/field";

type Role = "admin" | "manager" | "sales";
const ROLES: Role[] = ["admin", "manager", "sales"];

interface CsvRow {
  name: string;
  phone: string;
  role: Role;
  password: string;
  username: string;
}

function parseCsv(raw: string): CsvRow[] {
  const lines = raw
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"));
  if (lines.length === 0) return [];

  const rows: CsvRow[] = [];
  const start = /^name[,，]/i.test(lines[0]) ? 1 : 0;

  for (let i = start; i < lines.length; i++) {
    const cols = lines[i].split(/[,，]/).map((c) => c.trim());
    const [name, phone, roleRaw = "sales", password = "", username = ""] = cols;
    if (!name || !phone) {
      throw new Error(`第 ${i + 1} 行缺 name/phone: ${lines[i]}`);
    }
    if (!/^1\d{10}$/.test(phone)) {
      throw new Error(`第 ${i + 1} 行手机号格式不对: ${phone}`);
    }
    const role = (roleRaw || "sales") as Role;
    if (!ROLES.includes(role)) {
      throw new Error(`第 ${i + 1} 行 role 非法: ${roleRaw} (可选 ${ROLES.join("/")})`);
    }
    if (password && !isValidPassword(password)) {
      throw new Error(`第 ${i + 1} 行初始密码不合格: ${PASSWORD_POLICY_MESSAGE}`);
    }
    rows.push({ name, phone, role, password, username });
  }
  return rows;
}

function generatePassword(): string {
  // 10 位 base64url, 保证含字母+数字 (policy)
  for (let i = 0; i < 100; i++) {
    const pwd = randomBytes(8).toString("base64url").slice(0, 10);
    if (isValidPassword(pwd)) return pwd;
  }
  throw new Error("随机密码生成失败");
}

async function main() {
  const csvPath = process.argv[2];
  const dryRun = process.argv.includes("--dry-run");
  if (!csvPath) {
    throw new Error("用法: pnpm tsx scripts/import-users.ts <users.csv> [--dry-run]");
  }

  const rows = parseCsv(readFileSync(csvPath, "utf-8"));
  if (rows.length === 0) {
    console.log("CSV 没有数据行");
    return;
  }
  console.log(`共 ${rows.length} 行${dryRun ? " (dry-run, 不写库)" : ""}\n`);

  let created = 0;
  let skipped = 0;
  const issued: Array<{ name: string; phone: string; password: string }> = [];

  for (const row of rows) {
    const phoneHash = hashForLookup(row.phone);
    const [existing] = await db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.phoneHash, phoneHash))
      .limit(1);

    if (existing) {
      console.log(`- 跳过 ${row.name} ${row.phone} (已存在 id=${existing.id})`);
      skipped++;
      continue;
    }

    const password = row.password || generatePassword();
    const username = row.username || row.phone;

    if (dryRun) {
      console.log(`- [dry-run] 将创建 ${row.name} ${row.phone} role=${row.role} username=${username}`);
      created++;
      continue;
    }

    await db.insert(user).values({
      name: row.name,
      role: row.role,
      isActive: true,
      phoneEncrypted: encryptField(row.phone),
      phoneHash,
      username,
      passwordHash: hashPassword(password),
    });
    console.log(`✓ 已创建 ${row.name} ${row.phone} role=${row.role}`);
    created++;
    if (!row.password) issued.push({ name: row.name, phone: row.phone, password });
  }

  console.log(`\n完成: 新建 ${created}, 跳过 ${skipped}`);
  if (issued.length > 0) {
    console.log("\n===== 随机初始密码 (只显示这一次, 请立即分发/保存) =====");
    for (const u of issued) {
      console.log(`  ${u.name} (${u.phone}): ${u.password}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("✗ 导入失败:", err instanceof Error ? err.message : err);
    process.exit(1);
  });
