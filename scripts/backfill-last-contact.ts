// ============================================
// 回填「上次联系 / 上次到店」冗余列 (主人 2026-09-20 拍: 客户列表按跟进紧急度排序)
//
// 为什么需要: customer.last_interaction_at / last_visit_at 是 0016 迁移新增的冗余列,
//   写路径 (记互动 / 记养生记录) 会维护它, 但**存量数据**要一次性从明细表回填。
//
// 用法:
//   npx tsx scripts/backfill-last-contact.ts            # 真跑
//   npx tsx scripts/backfill-last-contact.ts --dry-run   # 只看会改多少行
//
// 幂等: 用的是 MAX(明细表时间), 重复跑结果一致
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { withAuditContext } from "@/lib/audit/context";

const dryRun = process.argv.includes("--dry-run");

async function counts() {
  const [c] = await db.execute<{
    customers: string;
    with_interaction: string;
    with_visit: string;
  }>(sql`
    SELECT
      (SELECT count(*) FROM customer WHERE deleted_at IS NULL) AS customers,
      (SELECT count(*) FROM customer WHERE deleted_at IS NULL AND last_interaction_at IS NOT NULL) AS with_interaction,
      (SELECT count(*) FROM customer WHERE deleted_at IS NULL AND last_visit_at IS NOT NULL) AS with_visit
  `);
  return c;
}

async function main() {
  const before = await counts();
  console.log(
    `回填前: 客户 ${before.customers} | 有上次联系 ${before.with_interaction} | 有上次到店 ${before.with_visit}\n`
  );

  // 先报出"明细表里其实有数据, 但冗余列是空"的数量 (真正要补的)
  const [gap] = await db.execute<{ g1: string; g2: string }>(sql`
    SELECT
      (SELECT count(*) FROM customer c
        WHERE c.deleted_at IS NULL AND c.last_interaction_at IS NULL
          AND EXISTS (SELECT 1 FROM interaction i WHERE i.customer_id = c.id)) AS g1,
      (SELECT count(*) FROM customer c
        WHERE c.deleted_at IS NULL AND c.last_visit_at IS NULL
          AND EXISTS (SELECT 1 FROM wellness_record w WHERE w.customer_id = c.id)) AS g2
  `);
  console.log(`待补: 上次联系 ${gap.g1} 行 / 上次到店 ${gap.g2} 行`);

  if (dryRun) {
    console.log("\n[dry-run] 未写库");
    return;
  }

  await withAuditContext({ userId: BigInt(0) }, async (tx) => {
    await tx.execute(sql`
      UPDATE customer c
      SET last_interaction_at = sub.max_at, updated_at = NOW()
      FROM (SELECT customer_id, MAX(created_at) AS max_at FROM interaction GROUP BY customer_id) sub
      WHERE c.id = sub.customer_id
        AND (c.last_interaction_at IS NULL OR c.last_interaction_at < sub.max_at)
    `);
    await tx.execute(sql`
      UPDATE customer c
      SET last_visit_at = sub.max_at, updated_at = NOW()
      FROM (SELECT customer_id, MAX(created_at) AS max_at FROM wellness_record GROUP BY customer_id) sub
      WHERE c.id = sub.customer_id
        AND (c.last_visit_at IS NULL OR c.last_visit_at < sub.max_at)
    `);
  });

  const after = await counts();
  console.log(
    `\n回填后: 客户 ${after.customers} | 有上次联系 ${after.with_interaction} | 有上次到店 ${after.with_visit}`
  );
  console.log("\n✅ 回填完成 (幂等, 可重复跑)");
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("✗ 失败:", e instanceof Error ? e.message : e);
    process.exit(1);
  });
