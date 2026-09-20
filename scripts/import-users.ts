#!/usr/bin/env -S npx tsx
// ============================================
// 暖客宝 邀请制批量导入用户 (P2)
//
// CSV 格式 (UTF-8, 第一行可选表头):
//   name,phone,role,initial_password,username,referral_code
//   张三,13900000001,sales,Abcd1234,,ABC234
//   李四,13900000002,manager,,,          # 密码留空 = 随机生成并打印一次
//
// - role: admin | manager | sales (默认 sales)
// - initial_password: 留空则随机生成 (打印一次, 由主人分发)
// - username: 留空默认用手机号 (手机号本身就是登录账号)
// - referral_code: **必填** (主人 2026-09-19 拍: 「推荐码作为用户账户最强身份识别码」)
//   —— 推荐人的 6 位码; **只有 role=admin 的行可以留空**
//   填了 → 新用户立刻得 15 天会员, 推荐人等他成为加盟者后再得 15 天 (ADR-0012 §6)
// - 建号同时**强制建客户档案** (主人 2026-09-19 拍「建号即强制建档」); 同手机号已有档案则复用
// - 逃生舱: --allow-missing-referral (只在建"根账号/首批种子账号"时用, 会打印警告)
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
import { isValidPassword, PASSWORD_POLICY_MESSAGE } from "@/lib/auth/password";
import { hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile } from "@/lib/auth/registration";
import { isValidReferralCodeShape } from "@/lib/billing/referral";

type Role = "admin" | "manager" | "sales";
const ROLES: Role[] = ["admin", "manager", "sales"];

interface CsvRow {
  name: string;
  phone: string;
  role: Role;
  password: string;
  username: string;
  /** 推荐人 6 位码 (选填; 只在建号时有效) */
  referralCode: string;
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
    const [
      name,
      phone,
      roleRaw = "sales",
      password = "",
      username = "",
      referralCode = "",
    ] = cols;
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
    if (referralCode && !isValidReferralCodeShape(referralCode)) {
      throw new Error(
        `第 ${i + 1} 行推荐码格式不对: ${referralCode} (6 位字母数字, 去掉易混字符)`
      );
    }
    rows.push({ name, phone, role, password, username, referralCode });
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
    throw new Error(
      "用法: pnpm tsx scripts/import-users.ts <users.csv> [--dry-run] [--allow-missing-referral]"
    );
  }
  const allowMissingReferral = process.argv.includes("--allow-missing-referral");

  const rows = parseCsv(readFileSync(csvPath, "utf-8"));
  if (rows.length === 0) {
    console.log("CSV 没有数据行");
    return;
  }
  console.log(`共 ${rows.length} 行${dryRun ? " (dry-run, 不写库)" : ""}\n`);

  let created = 0;
  let skipped = 0;
  const issued: Array<{ name: string; phone: string; password: string }> = [];
  const failedReferrals: string[] = [];

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
      console.log(
        `- [dry-run] 将创建 ${row.name} ${row.phone} role=${row.role} username=${username}` +
          (row.referralCode ? ` 推荐码=${row.referralCode} (+15 天)` : "")
      );
      created++;
      continue;
    }

    // ★ 唯一建号入口 (主人 2026-09-19 拍): 账号 + 客户档案(强制) + 推荐码(必填)
    //   - 非 admin 行没填码 → 直接报错 (除非 --allow-missing-referral)
    //   - 同手机号已有客户档案 → 复用 (不重复建)
    let res;
    try {
      res = await createAccountWithProfile({
        name: row.name,
        phone: row.phone,
        role: row.role,
        password,
        username,
        referralCode: row.referralCode,
        allowNoReferral: allowMissingReferral || row.role === "admin",
        actorUserId: BigInt(1),
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`✗ 跳过 ${row.name} ${row.phone}: ${msg}`);
      failedReferrals.push(`${row.name}(${row.phone}): ${msg}`);
      continue;
    }

    // ★ 推荐码只能在"注册"时填 —— claimReferralCode 内部再校验"账号创建 24h 内"(兜底)
    let referralNote = "";
    if (row.referralCode) {
      referralNote = res.referralAccepted
        ? ` | 推荐码 ${row.referralCode} 已生效 (+15 天)`
        : ` | ⚠ 推荐码未生效: ${res.referralRejectedReason}`;
      if (!res.referralAccepted) {
        failedReferrals.push(`${row.name}(${row.phone}): ${res.referralRejectedReason}`);
      }
    }
    if (allowMissingReferral && !row.referralCode && row.role !== "admin") {
      console.log(
        `  ⚠️ ${row.name} 没有推荐码 (--allow-missing-referral): 该账号不在任何人的推荐链上`
      );
    }
    console.log(
      `✓ 已创建 ${row.name} ${row.phone} role=${row.role}` +
        ` | 客户档案 ${res.customerCreated ? "新建" : "复用既有"}` +
        ` | 我的推荐码 ${res.ownReferralCode}${referralNote}`
    );
    created++;
    if (!row.password) issued.push({ name: row.name, phone: row.phone, password });
  }

  console.log(`\n完成: 新建 ${created}, 跳过 ${skipped}`);
  if (failedReferrals.length > 0) {
    console.log("\n===== 推荐码未生效 (用户已建号, 可让推荐人核对后重发码) =====");
    for (const f of failedReferrals) console.log(`  ${f}`);
  }
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
