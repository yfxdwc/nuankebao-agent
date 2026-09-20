// ============================================
// 存量补齐: 账号 ↔ 客户档案 + 无推荐人客户挂到「根」 (主人 2026-09-19 拍)
//
// 背景 (实测): 7 个账号里 0 个有同名客户档案; 47 个客户里 38 个没有推荐人。
// 主人拍板: 「建号即强制建档 + 推荐码必填 (admin/根可空)」+ 存量:「客户挂到门店/根, 账号补档案」
//
// 做三件事 (全部幂等):
//   ① 每个账号 → 保证有客户档案 (同手机号; 有则复用) + 自己的推荐码
//   ② 「根」账号 = 加盟树根节点 (placement_path='') 对应的客户档案 —— 没有就建
//   ③ 无推荐人的客户 → referrer_id 指向根 (= 门店直客)
//
// 用法:
//   npx tsx scripts/backfill-account-customer-link.ts            # 真跑
//   npx tsx scripts/backfill-account-customer-link.ts --dry-run  # 只看会改什么
// ============================================

import { config as loadEnv } from "dotenv";
loadEnv({ path: ".env.local" });

import { and, eq, isNull, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer, franchisee, user } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import { withAuditContext } from "@/lib/audit/context";
import { ensureAccountProfile } from "@/lib/auth/registration";

const dryRun = process.argv.includes("--dry-run");
const ACTOR = BigInt(1);
const line = (s: string) => console.log(s);

async function counts() {
  const [c] = await db.execute<{
    users: string;
    users_with_customer: string;
    customers: string;
    customers_no_referrer: string;
  }>(sql`
    SELECT
      (SELECT count(*) FROM "user") AS users,
      (SELECT count(*) FROM "user" u JOIN customer c ON c.phone_hash = u.phone_hash AND c.deleted_at IS NULL) AS users_with_customer,
      (SELECT count(*) FROM customer WHERE deleted_at IS NULL) AS customers,
      (SELECT count(*) FROM customer WHERE deleted_at IS NULL AND referrer_id IS NULL) AS customers_no_referrer
  `);
  return c;
}

async function main() {
  const before = await counts();
  line(`dry-run = ${dryRun}\n`);
  line(`补齐前: 账号 ${before.users} (有客户档案 ${before.users_with_customer}) | ` +
    `客户 ${before.customers} (无推荐人 ${before.customers_no_referrer})\n`);

  // ---- ① 账号 → 客户档案 + 推荐码 ----
  const users = await db
    .select({ id: user.id, name: user.name, role: user.role })
    .from(user)
    .orderBy(user.id);
  let createdProfiles = 0;
  for (const u of users) {
    if (dryRun) {
      const [c] = await db
        .select({ id: customer.id })
        .from(customer)
        .innerJoin(user, eq(user.phoneHash, customer.phoneHash))
        .where(and(eq(user.id, u.id), isNull(customer.deletedAt)))
        .limit(1);
      line(`  [dry-run] 账号 ${u.id} ${u.name} (${u.role}) → 客户档案 ${c ? "已在" : "待建"}`);
      if (!c) createdProfiles++;
      continue;
    }
    const prof = await ensureAccountProfile(u.id, ACTOR);
    if (prof.customerCreated) {
      createdProfiles++;
      line(`  ✓ 账号 ${u.id} ${u.name} (${u.role}) → 新建客户档案 #${prof.customerId} | 推荐码 ${prof.referralCode}`);
    }
  }
  line(`\n① 账号补档案: 新建 ${createdProfiles} 个\n`);

  // ---- ② 「根」= 加盟树根节点 (placement_path = '') 的客户档案 ----
  const [rootFranchisee] = await db
    .select({ id: franchisee.id, name: franchisee.name, phoneEncrypted: franchisee.phoneEncrypted, phoneHash: franchisee.phoneHash })
    .from(franchisee)
    .where(and(eq(franchisee.placementPath, ""), isNull(franchisee.deletedAt)))
    .limit(1);

  let rootCustomerId: bigint | null = null;
  if (rootFranchisee) {
    const [existing] = await db
      .select({ id: customer.id })
      .from(customer)
      .where(and(eq(customer.phoneHash, rootFranchisee.phoneHash), isNull(customer.deletedAt)))
      .limit(1);
    if (existing) {
      rootCustomerId = existing.id;
      line(`② 根客户档案 = #${existing.id} (加盟树根 ${rootFranchisee.name})\n`);
    } else if (dryRun) {
      line(`② [dry-run] 待建根客户档案 (加盟树根 ${rootFranchisee.name})\n`);
    } else {
      const [created] = await withAuditContext({ userId: ACTOR }, async (tx) =>
        tx
          .insert(customer)
          .values({
            name: rootFranchisee.name,
            phoneEncrypted: rootFranchisee.phoneEncrypted,
            phoneHash: rootFranchisee.phoneHash,
            isSeed: false,
            createdBy: ACTOR,
          })
          .returning({ id: customer.id })
      );
      rootCustomerId = created.id;
      line(`② 新建根客户档案 #${created.id} (加盟树根 ${rootFranchisee.name})\n`);
    }
  } else {
    line("② ⚠ 没有找到加盟树根节点 (placement_path='') → 跳过「挂到根」\n");
  }

  // ---- ③ 无推荐人客户 → 挂到根 ----
  if (rootCustomerId != null) {
    const orphans = await db
      .select({ id: customer.id, name: customer.name })
      .from(customer)
      .where(and(isNull(customer.referrerId), isNull(customer.deletedAt)));
    const targets = orphans.filter((c) => c.id !== rootCustomerId);
    line(`③ 待挂到根的无推荐人客户: ${targets.length} 个 (根自己 #${rootCustomerId} 除外)`);
    for (const c of targets.slice(0, 5)) {
      line(`     e.g. #${c.id} ${c.name}`);
    }
    if (targets.length > 5) line(`     … 其余 ${targets.length - 5} 个同类`);
    if (!dryRun && targets.length > 0) {
      await withAuditContext({ userId: ACTOR }, async (tx) =>
        tx
          .update(customer)
          .set({ referrerId: rootCustomerId, updatedAt: sql`NOW()` })
          .where(and(isNull(customer.referrerId), isNull(customer.deletedAt)))
      );
      line(`  ✓ 已把 ${targets.length} 个客户挂到根 #${rootCustomerId}`);
    } else if (dryRun) {
      line("  [dry-run] 未改数据");
    }
    line("");
  }

  if (dryRun) {
    line("dry-run 结束 (没写库)");
    return;
  }
  const after = await counts();
  line(`补齐后: 账号 ${after.users} (有客户档案 ${after.users_with_customer}) | ` +
    `客户 ${after.customers} (无推荐人 ${after.customers_no_referrer})`);
  line(`\n${after.users_with_customer === after.users ? "✅ 不变量成立: 每个账号都有客户档案" : "⚠️ 仍有账号没有客户档案"}`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("✗ 失败:", e instanceof Error ? e.message : e);
    process.exit(1);
  });
