// ============================================
// 系统管理员账号「长期保留」保证脚本 (主人 2026-09-19 拍)
//
// 主人原话: 「长期保留系统管理员账号 admin，生产环境也要保留」
//   → 管理员账号是**永久设施**: dev 机器 + 生产环境都必须存在一个 role='admin' 的账号
//   → 生产部署 / 灾备恢复后, 跑一次本脚本即可保证管理员账号在
//
// 用法:
//   pnpm db:ensure-admin                          # 用 .env.local / 环境变量里的 ADMIN_PHONE
//   ADMIN_PHONE=13800138000 pnpm db:ensure-admin  # 显式给手机号
//   npx tsx scripts/ensure-admin.ts --phone=138... --name=管理员
//
// 行为 (幂等):
//   - 账号不存在 → 建一个 (role='admin', 无加盟商绑定, is_active=true)
//   - 账号已存在 → 只把 role 抬成 'admin' (不覆盖姓名/加盟商绑定/密码等)
//   - 打印最终结果 (id / 手机号 / 姓名 / role)
// ============================================

import { config as loadEnv } from "dotenv";
loadEnv({ path: ".env.local" });
loadEnv();

import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { user } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";

function arg(name: string): string | undefined {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : undefined;
}

const phone = arg("phone") ?? process.env.ADMIN_PHONE ?? "13800138000";
const name = arg("name") ?? process.env.ADMIN_NAME ?? "管理员";
const avatarUrl = process.env.ADMIN_AVATAR_URL ?? null;

async function main() {
  if (!/^1[3-9]\d{9}$/.test(phone)) {
    console.error(`❌ ADMIN_PHONE 格式不对: ${phone} (要 11 位手机号)`);
    process.exit(1);
  }
  const phoneHash = hashForLookup(phone);
  const [existing] = await db
    .select({ id: user.id, name: user.name, role: user.role })
    .from(user)
    .where(eq(user.phoneHash, phoneHash))
    .limit(1);

  if (existing) {
    if (existing.role === "admin") {
      console.log(
        `✅ 管理员账号已存在 (无需改): id=${existing.id} ${existing.name} role=admin`
      );
      return;
    }
    await db
      .update(user)
      .set({ role: "admin", isActive: true, updatedAt: new Date() })
      .where(eq(user.id, existing.id));
    console.log(
      `✅ 已把现有账号抬成管理员: id=${existing.id} ${existing.name} (原 role=${existing.role})`
    );
    return;
  }

  const [created] = await db
    .insert(user)
    .values({
      name,
      phoneEncrypted: encryptField(phone),
      phoneHash,
      role: "admin",
      isActive: true,
      avatarUrl,
    })
    .returning({ id: user.id, name: user.name, role: user.role });
  console.log(
    `✅ 已新建管理员账号: id=${created.id} ${created.name} role=${created.role} (手机号 ${phone.slice(0, 3)}****${phone.slice(7)})`
  );
  console.log(
    `   登录: dev 环境用 flutter-login (code=123456); 生产环境用短信验证码登录`
  );
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("❌ 失败:", e instanceof Error ? e.message : String(e));
    process.exit(1);
  });
