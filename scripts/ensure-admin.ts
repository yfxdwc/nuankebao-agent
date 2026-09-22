#!/usr/bin/env -S npx tsx
// ============================================
// 系统管理员账号: 创建 / 提升 / 重置密码 / 补档案 (唯一入口)
// ============================================
// 主人 2026-09-19 拍: 「长期保留系统管理员账号 admin，生产环境也要保留」
//   → 管理员账号是**永久设施** (dev + 生产都要有 role='admin' 的账号)
// 主人 2026-09-19 拍: 「建号即强制建档」→ 管理员账号同样补客户档案 + 推荐码
//
// 用法 (口令只经环境变量, 不落 git / 不进 shell history 由主人自理):
//   # 最简单 (dev / 生产都行): 按手机号
//   ADMIN_PHONE=19957347866 ADMIN_NAME=管理员 pnpm db:ensure-admin
//
//   # 带登录名 + 密码 (推荐生产用: 可以用户名密码登录)
//   ADMIN_USERNAME=admin ADMIN_PASSWORD='强密码' ADMIN_PHONE=19957347866 ADMIN_NAME=管理员 pnpm db:ensure-admin
//
//   # CLI 参数 (等价)
//   npx tsx scripts/ensure-admin.ts --phone=19957347866 --name=管理员
//
// 环境变量:
//   ADMIN_PHONE     手机号 (默认 13800138000; 手机号也是登录账号)
//   ADMIN_NAME      显示名 (默认「管理员」; 只在**显式给了**时才覆盖已有姓名)
//   ADMIN_USERNAME  登录用户名 (可选; 给了就按用户名找人, 不存在则建号时用它)
//   ADMIN_PASSWORD  登录密码 (可选; 给了就设置/重置 —— scrypt 哈希入库, 明文不落库)
//
// 行为 (幂等):
//   - 命中已有账号 → role 抬成 admin + isActive=true (+ 给了密码就重置密码)
//   - 没命中 → 新建账号 (role='admin')
//   - 两条路径都补齐**账号档案**: customer 档案 (同手机号; 有则复用) + 自己的推荐码
//
// ⚠ 生产服务器 (migrate 镜像内):
//   docker compose -p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod \
//     run --rm --no-deps -e ADMIN_USERNAME=admin -e ADMIN_PASSWORD='...' \
//     -e ADMIN_PHONE=19957347866 -e ADMIN_NAME=管理员 migrate pnpm db:ensure-admin
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { user } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import { ensureAccountProfile } from "@/lib/auth/registration";
import {
  hashPassword,
  isValidPassword,
  PASSWORD_POLICY_MESSAGE,
} from "@/lib/auth/password";

function arg(name: string): string | undefined {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : undefined;
}

const phone = arg("phone") ?? process.env.ADMIN_PHONE ?? "13800138000";
const nameArg = arg("name") ?? process.env.ADMIN_NAME ?? null;
const username = (arg("username") ?? process.env.ADMIN_USERNAME ?? "").trim();
const password = arg("password") ?? process.env.ADMIN_PASSWORD ?? "";

async function main() {
  if (!/^1[3-9]\d{9}$/.test(phone)) {
    console.error(`❌ ADMIN_PHONE 格式不对: ${phone} (要 11 位手机号)`);
    process.exit(1);
  }
  if (password && !isValidPassword(password)) {
    console.error(`❌ ADMIN_PASSWORD 不合格: ${PASSWORD_POLICY_MESSAGE}`);
    process.exit(1);
  }

  const phoneHash = hashForLookup(phone);

  // 找目标账号: 给了用户名优先按用户名找, 否则按手机号
  const target = username
    ? (
        await db
          .select({ id: user.id, name: user.name, role: user.role, username: user.username })
          .from(user)
          .where(eq(user.username, username))
          .limit(1)
      )[0]
    : (
        await db
          .select({ id: user.id, name: user.name, role: user.role, username: user.username })
          .from(user)
          .where(eq(user.phoneHash, phoneHash))
          .limit(1)
      )[0];

  let userId: bigint;
  if (target) {
    await db
      .update(user)
      .set({
        role: "admin",
        isActive: true,
        // 显式给了姓名才覆盖 (避免把现有管理员改名)
        ...(nameArg ? { name: nameArg } : {}),
        // 给了用户名就绑上 (便于用户名登录)
        ...(username ? { username } : {}),
        // 给了密码就重置
        ...(password ? { passwordHash: hashPassword(password) } : {}),
        updatedAt: new Date(),
      })
      .where(eq(user.id, target.id));
    userId = target.id;
    console.log(
      `✅ 已有账号抬成/保持管理员: id=${target.id} ${nameArg ?? target.name} (原 role=${target.role})` +
        (password ? " | 密码已重置" : "")
    );
  } else {
    const [created] = await db
      .insert(user)
      .values({
        name: nameArg ?? "管理员",
        role: "admin",
        isActive: true,
        phoneEncrypted: encryptField(phone),
        phoneHash,
        username: username || phone,
        passwordHash: password ? hashPassword(password) : null,
      })
      .returning({ id: user.id, name: user.name, username: user.username });
    userId = created.id;
    console.log(
      `✅ 新建管理员账号: id=${created.id} ${created.name} (username=${created.username})` +
        (password ? " | 已设密码" : " | 未设密码 (只能验证码登录; 想设密码给 ADMIN_PASSWORD)")
    );
  }

  // 「建档」不是 admin 必选项 (ADR-0015 Q5): admin 豁免
  //   → 推荐码照发 (身份识别码), 客户档案不建 (prod admin 现状 = 无档案)
  const prof = await ensureAccountProfile(userId, BigInt(0));
  console.log(
    `   账号档案: 客户档案 ${prof.customerCreated ? "新建" : prof.customerId == null ? "admin 豁免 (不建)" : "已在"}${prof.customerId ? ` #${prof.customerId}` : ""}` +
      ` | 推荐码 ${prof.referralCode}`
  );
  console.log(
    `   登录: ${username ? `用户名 ${username} / ` : ""}手机号 ${phone.slice(0, 3)}****${phone.slice(7)}` +
      (password ? " + 密码" : " + 短信验证码")
  );
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("❌ 失败:", e instanceof Error ? e.message : String(e));
    process.exit(1);
  });
