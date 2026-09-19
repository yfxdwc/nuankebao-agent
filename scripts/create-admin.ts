#!/usr/bin/env -S npx tsx
// ============================================
// 暖客宝 创建/重置 系统管理员 (邀请制建号, P2)
//
// 用法 (口令只经环境变量传入, 不落 git / 不落 shell history 由主人自行处理):
//   ADMIN_USERNAME=admin ADMIN_PASSWORD='强密码' pnpm tsx scripts/create-admin.ts
//
// 可选:
//   ADMIN_NAME   管理员显示名 (默认「系统管理员」)
//   ADMIN_PHONE  手机号 (默认占位 13800138000; 手机号也可作为登录账号,
//                建议指定主人真实手机号)
//
// 行为:
//   - username 已存在 → 重置密码 + 确保 role=admin + isActive=true (幂等)
//   - 不存在 → 新建 (需 phone 未被占用)
//   - 密码按 scrypt 哈希存储 (src/lib/auth/password.ts)
//
// ⚠️ 生产服务器上跑 (migrate 镜像内):
//   docker compose -p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod \
//     run --rm --no-deps -e ADMIN_USERNAME=admin -e ADMIN_PASSWORD='...' \
//     migrate pnpm tsx scripts/create-admin.ts
// ============================================

import { config as loadEnv } from "dotenv";
loadEnv({ path: ".env.local" });

import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { user } from "@/lib/db/schema";
import {
  hashPassword,
  isValidPassword,
  PASSWORD_POLICY_MESSAGE,
} from "@/lib/auth/password";
import { encryptField, hashForLookup } from "@/lib/crypto/field";

const PLACEHOLDER_PHONE = "13800138000";

async function main() {
  const username = process.env.ADMIN_USERNAME?.trim();
  const password = process.env.ADMIN_PASSWORD ?? "";
  const name = process.env.ADMIN_NAME?.trim() || "系统管理员";
  const phone = process.env.ADMIN_PHONE?.trim() || PLACEHOLDER_PHONE;

  if (!username) throw new Error("缺少 ADMIN_USERNAME");
  if (!isValidPassword(password)) throw new Error(PASSWORD_POLICY_MESSAGE);
  if (!/^1\d{10}$/.test(phone)) throw new Error("ADMIN_PHONE 应为 11 位手机号");

  const phoneHash = hashForLookup(phone);
  const [existing] = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.username, username))
    .limit(1);

  if (existing) {
    await db
      .update(user)
      .set({
        name,
        role: "admin",
        isActive: true,
        passwordHash: hashPassword(password),
        phoneEncrypted: encryptField(phone),
        phoneHash,
        updatedAt: new Date(),
      })
      .where(eq(user.id, existing.id));
    console.log(`✓ 已更新管理员 "${username}" (id=${existing.id}, role=admin)`);
  } else {
    const [phoneOwner] = await db
      .select({ id: user.id, username: user.username })
      .from(user)
      .where(eq(user.phoneHash, phoneHash))
      .limit(1);
    if (phoneOwner) {
      throw new Error(
        `手机号已被 user id=${phoneOwner.id} (username=${phoneOwner.username ?? "无"}) 占用; 请换 ADMIN_PHONE`
      );
    }

    const [created] = await db
      .insert(user)
      .values({
        name,
        role: "admin",
        isActive: true,
        phoneEncrypted: encryptField(phone),
        phoneHash,
        username,
        passwordHash: hashPassword(password),
      })
      .returning({ id: user.id });
    console.log(`✓ 已创建管理员 "${username}" (id=${created.id}, role=admin)`);
  }

  if (phone === PLACEHOLDER_PHONE) {
    console.warn(
      `⚠️ 手机号用的是占位值 ${PLACEHOLDER_PHONE}; 建议下次用 ADMIN_PHONE 指定真实号 (手机号也可作为登录账号)`
    );
  }
  console.log("  密码: scrypt 哈希已入库 (明文不落库)");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("✗ 创建管理员失败:", err instanceof Error ? err.message : err);
    process.exit(1);
  });
