#!/usr/bin/env -S npx tsx
// ============================================
// 加盟商 → 客户档案 回填 (主人 2026-09-18 拍, 方案 A)
//
// 背景: 客户列表「加盟」跟客户页「图谱」对不上 (列表 0 vs 图谱 14)
//   根因: 两张表 (customer vs franchisee) 靠 phone_hash 对齐, seed 数据两拨人手机号不重叠
//   修法: 加盟商建号时同步落客户档案 (queries/franchisee.ts createFranchisee) + 本脚本回填存量
//
// 行为:
//   - 遍历 franchisee (未软删) → 同手机号 upsert 一条 customer (isSeed=false)
//   - 幂等: 已有客户不动 (onConflictDoNothing on phone_hash unique)
//   - 审计: customer 表 audit trigger 自动写 audit_log (走 DB 触发器, 不依赖 API)
//
// 用法:
//   pnpm tsx scripts/backfill-franchisee-customers.ts            # 跑
//   pnpm tsx scripts/backfill-franchisee-customers.ts --dry-run  # 只看会做什么
//   pnpm tsx scripts/backfill-franchisee-customers.ts --restore-deleted
//     软删客户会挡住回填 (idx_customer_phone_hash 唯一索引含已软删行) →
//     默认跳过; 加此 flag 则恢复 (deleted_at = NULL) 那些行。
//     ⚠ 只在“确认该手机号现在是加盟商, 应该有客户档案”时用 (删客户可能是有意的)
//
// 关联: CHANGELOG 2026-09-18「客户类型真过滤 (图谱同口径)」
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { db } from "@/lib/db";
import { customer, franchisee } from "@/lib/db/schema";
import { isNull, eq } from "drizzle-orm";
import { franchiseeCustomerValues } from "@/lib/db/queries/customer";

const DRY_RUN = process.argv.includes("--dry-run");
const RESTORE_DELETED = process.argv.includes("--restore-deleted");

function log(msg: string) {
  console.log(`[backfill] ${msg}`);
}

async function main() {
  const rows = await db
    .select({
      id: franchisee.id,
      name: franchisee.name,
      phoneEncrypted: franchisee.phoneEncrypted,
      createdBy: franchisee.createdBy,
    })
    .from(franchisee)
    .where(isNull(franchisee.deletedAt));

  log(`未软删加盟商: ${rows.length} 位`);

  // phoneEncrypted 是 pgcrypto 密文, 这里需要明文手机号才能建客户档案
  // → 解密 (跟 franchisee.toView 同一套 decryptField)
  const { decryptField } = await import("@/lib/crypto/field");

  let created = 0;
  let existed = 0;
  let restored = 0;
  let blockedDeleted = 0;

  for (const r of rows) {
    const phone = decryptField(r.phoneEncrypted);
    const values = franchiseeCustomerValues({
      name: r.name,
      phone,
      createdBy: r.createdBy,
    });

    if (DRY_RUN) {
      log(`[dry-run] 会建客户档案: ${r.name} (franchisee #${r.id})`);
      created++;
      continue;
    }

    const inserted = await db
      .insert(customer)
      .values(values)
      .onConflictDoNothing({ target: customer.phoneHash })
      .returning({ id: customer.id });

    if (inserted.length > 0) {
      created++;
      log(`✓ 建客户档案 #${inserted[0].id} ← 加盟商 #${r.id} ${r.name}`);
      continue;
    }

    // 冲突: 已存在同手机号客户 (可能是软删的)
    const [existing] = await db
      .select({ id: customer.id, deletedAt: customer.deletedAt })
      .from(customer)
      .where(eq(customer.phoneHash, values.phoneHash))
      .limit(1);

    if (existing?.deletedAt && RESTORE_DELETED) {
      await db
        .update(customer)
        .set({ deletedAt: null })
        .where(eq(customer.id, existing.id));
      restored++;
      log(`↺ 恢复软删客户档案 #${existing.id} ← 加盟商 #${r.id} ${r.name}`);
    } else if (existing?.deletedAt) {
      blockedDeleted++;
      log(`! 被软删客户 #${existing.id} 挡住 (加 --restore-deleted 可恢复): ${r.name}`);
    } else {
      existed++;
      log(`- 已有客户档案, 跳过: ${r.name} (加盟商 #${r.id})`);
    }
  }

  log(
    `${DRY_RUN ? "[dry-run] " : ""}完成: 新建 ${created} / 已存在 ${existed} / 恢复 ${restored} / 软删挡住 ${blockedDeleted}`
  );
  process.exit(0);
}

main().catch((e) => {
  console.error("[backfill] 失败:", e);
  process.exit(1);
});
