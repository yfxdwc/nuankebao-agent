// ============================================
// 客户推送 (customer_share) 巡检脚本
// Phase D (主文档 §8.4 / ADR-0019 §4.4)
// ============================================
// 命令:
//   npx tsx scripts/audit-customer-share.ts              # 只报告
//   npx tsx scripts/audit-customer-share.ts --strict    # 异常 → exit 1
//   npx tsx scripts/audit-customer-share.ts --stats      # 扩散密度统计
//   npx tsx scripts/audit-customer-share.ts --list-density  # 列表膨胀分布 (升级阈值 O-3)
//
// 检查项:
//   1. 跨枝推送 (from 与 to 不同 root_id 且 from 非 admin)
//   2. 越权推送 (from 既不是 customer.owner_id 也不 role='admin')
//   3. 重复 active (同一 (customer_id, to_user_id) 多条 revoked_at IS NULL)
//   4. 双方账号停用 (from_user.is_active=false 或 to_user.is_active=false 但推送仍 active)
//   5. 推送人节点软删 (ff.deleted_at IS NOT NULL 但推送仍 active)
//
// 数据库来源 (dev / prod): 启动时打印 DATABASE_URL 主机, 主人一眼区分
//   (默认走 .env.local → nuankebao dev; prod 显式设 DATABASE_URL=nuankebao-prod-postgres)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { eq, isNull, sql, desc } from "drizzle-orm";
import { db } from "@/lib/db";
import { customerShare, customer, user as userTable, franchisee } from "@/lib/db/schema";

const STRICT = process.argv.includes("--strict");
const STATS = process.argv.includes("--stats");
const LIST_DENSITY = process.argv.includes("--list-density");

interface CrossBranchRow extends Record<string, unknown> {
  share_id: string;
  customer_id: string;
  from_user_id: string;
  from_root_id: string | null;
  to_user_id: string;
  to_root_id: string | null;
  from_name: string;
  to_name: string;
}
interface UnauthorizedRow extends Record<string, unknown> {
  share_id: string;
  customer_id: string;
  from_user_id: string;
  from_name: string;
  customer_owner_id: string | null;
  owner_name: string | null;
}
interface DuplicateActiveRow extends Record<string, unknown> {
  customer_id: string;
  to_user_id: string;
  count: number;
  share_ids: string[];
}
interface InactiveUserRow extends Record<string, unknown> {
  share_id: string;
  customer_id: string;
  from_user_id: string;
  from_name: string;
  from_active: boolean;
  to_user_id: string;
  to_name: string;
  to_active: boolean;
}
interface SoftDeletedFranchiseeRow extends Record<string, unknown> {
  share_id: string;
  customer_id: string;
  from_user_id: string;
  from_franchisee_id: string;
  ff_deleted_at: Date | null;
}

async function findCrossBranch(): Promise<CrossBranchRow[]> {
  const rows = await db.execute<CrossBranchRow>(sql`
    SELECT cs.id::text          AS share_id,
           cs.customer_id::text AS customer_id,
           cs.from_user_id::text AS from_user_id,
           ff.root_id::text     AS from_root_id,
           cs.to_user_id::text  AS to_user_id,
           tf.root_id::text     AS to_root_id,
           fu.name              AS from_name,
           tu.name              AS to_name
    FROM customer_share cs
    JOIN "user" fu ON fu.id = cs.from_user_id
    JOIN "user" tu ON tu.id = cs.to_user_id
    LEFT JOIN franchisee ff ON ff.id = fu.franchisee_id
    LEFT JOIN franchisee tf ON tf.id = tu.franchisee_id
    WHERE cs.revoked_at IS NULL
      AND fu.role <> 'admin'
      AND (
        (ff.root_id IS NOT NULL AND tf.root_id IS NOT NULL
         AND ff.root_id IS DISTINCT FROM tf.root_id)
        OR (ff.root_id IS NULL AND tf.root_id IS NOT NULL)
        OR (ff.root_id IS NOT NULL AND tf.root_id IS NULL)
      )
      AND ff.deleted_at IS NULL
      AND tf.deleted_at IS NULL
  `);
  return rows;
}

async function findUnauthorized(): Promise<UnauthorizedRow[]> {
  // 这里严格说:「owner_id = NULL 也算越权」(建号即建档 owner 为 NULL;
  //   但非 admin 必须等客户被显式 claim 后才能推 — 推到 owner=NULL 的客户是越权)
  return db.execute<UnauthorizedRow>(sql`
    SELECT cs.id::text          AS share_id,
           cs.customer_id::text AS customer_id,
           cs.from_user_id::text AS from_user_id,
           fu.name              AS from_name,
           c.owner_id::text     AS customer_owner_id,
           ou.name              AS owner_name
    FROM customer_share cs
    JOIN "user" fu ON fu.id = cs.from_user_id
    JOIN customer c ON c.id = cs.customer_id
    LEFT JOIN "user" ou ON ou.id = c.owner_id
    WHERE cs.revoked_at IS NULL
      AND fu.role <> 'admin'
      AND c.deleted_at IS NULL
      AND c.owner_id IS NOT NULL
      AND cs.from_user_id <> c.owner_id
  `);
}

async function findDuplicateActive(): Promise<DuplicateActiveRow[]> {
  const rows = await db.execute<{
    customer_id: string;
    to_user_id: string;
    count: number;
    share_ids: string[];
  }>(sql`
    SELECT customer_id::text AS customer_id,
           to_user_id::text  AS to_user_id,
           count(*)::int      AS count,
           array_agg(id::text) AS share_ids
    FROM customer_share
    WHERE revoked_at IS NULL
    GROUP BY customer_id, to_user_id
    HAVING count(*) > 1
  `);
  return rows;
}

async function findInactiveUsers(): Promise<InactiveUserRow[]> {
  return db.execute<InactiveUserRow>(sql`
    SELECT cs.id::text         AS share_id,
           cs.customer_id::text AS customer_id,
           cs.from_user_id::text AS from_user_id,
           fu.name             AS from_name,
           fu.is_active        AS from_active,
           cs.to_user_id::text  AS to_user_id,
           tu.name             AS to_name,
           tu.is_active        AS to_active
    FROM customer_share cs
    JOIN "user" fu ON fu.id = cs.from_user_id
    JOIN "user" tu ON tu.id = cs.to_user_id
    WHERE cs.revoked_at IS NULL
      AND (fu.is_active = false OR tu.is_active = false)
  `);
}

async function findSoftDeletedFranchisees(): Promise<SoftDeletedFranchiseeRow[]> {
  return db.execute<SoftDeletedFranchiseeRow>(sql`
    SELECT cs.id::text          AS share_id,
           cs.customer_id::text AS customer_id,
           cs.from_user_id::text AS from_user_id,
           fu.franchisee_id::text AS from_franchisee_id,
           ff.deleted_at        AS ff_deleted_at
    FROM customer_share cs
    JOIN "user" fu ON fu.id = cs.from_user_id
    JOIN franchisee ff ON ff.id = fu.franchisee_id
    WHERE cs.revoked_at IS NULL
      AND ff.deleted_at IS NOT NULL
  `);
}

interface StatsRow extends Record<string, unknown> {
  active_per_customer_p99: number;
  active_per_customer_max: number;
  active_per_customer_avg: number;
  active_total: number;
  customers_with_shares: number;
  recipients_today_p99: number;
  recipients_today_max: number;
}

async function stats(): Promise<StatsRow | null> {
  const [r] = await db.execute<StatsRow>(sql`
    WITH per_cust AS (
      SELECT customer_id, count(*) AS n
      FROM customer_share
      WHERE revoked_at IS NULL
      GROUP BY customer_id
    ),
    today_per_recip AS (
      SELECT to_user_id, count(*) AS n
      FROM customer_share
      WHERE revoked_at IS NULL
        AND created_at >= date_trunc('day', NOW())
      GROUP BY to_user_id
    )
    SELECT
      COALESCE((SELECT percentile_cont(0.99) WITHIN GROUP (ORDER BY n)::int FROM per_cust), 0) AS active_per_customer_p99,
      COALESCE((SELECT max(n)::int FROM per_cust), 0) AS active_per_customer_max,
      COALESCE((SELECT avg(n)::numeric(10,2) FROM per_cust), 0) AS active_per_customer_avg,
      (SELECT count(*)::int FROM customer_share WHERE revoked_at IS NULL) AS active_total,
      (SELECT count(distinct customer_id)::int FROM customer_share WHERE revoked_at IS NULL) AS customers_with_shares,
      COALESCE((SELECT percentile_cont(0.99) WITHIN GROUP (ORDER BY n)::int FROM today_per_recip), 0) AS recipients_today_p99,
      COALESCE((SELECT max(n)::int FROM today_per_recip), 0) AS recipients_today_max
  `);
  return r ?? null;
}

interface ListDensityBucket extends Record<string, unknown> {
  bucket: string;
  customer_count: number;
}
async function listDensity(): Promise<ListDensityBucket[]> {
  return db.execute<ListDensityBucket>(sql`
    WITH per_cust AS (
      SELECT customer_id, count(*) AS n
      FROM customer_share
      WHERE revoked_at IS NULL
      GROUP BY customer_id
    )
    SELECT
      CASE
        WHEN n = 0 THEN '0'
        WHEN n BETWEEN 1 AND 5 THEN '1-5'
        WHEN n BETWEEN 6 AND 10 THEN '6-10'
        WHEN n BETWEEN 11 AND 20 THEN '11-20'
        ELSE '21+'
      END AS bucket,
      count(*)::int AS customer_count
    FROM per_cust
    GROUP BY 1
    ORDER BY 1
  `);
}

function printDbSource() {
  const url = process.env.DATABASE_URL ?? "(unset)";
  const host = url.match(/@([^/]+)/)?.[1] ?? "?";
  const db = url.match(/\/([^/?]+)(?:$|\?)/)?.[1] ?? "?";
  console.log(`📍 DB source: ${host} / ${db}\n`);
}

async function main() {
  printDbSource();

  if (STATS) {
    const s = await stats();
    if (!s) {
      console.log("(无数据)");
      return;
    }
    console.log("📊 推送扩散密度统计 (active):");
    console.log(`   active 推送总条数          : ${s.active_total}`);
    console.log(`   涉及客户数                 : ${s.customers_with_shares}`);
    console.log(`   同客户 active 推送数 (max) : ${s.active_per_customer_max}`);
    console.log(`   同客户 active 推送数 (p99) : ${s.active_per_customer_p99}`);
    console.log(`   同客户 active 推送数 (avg) : ${s.active_per_customer_avg}`);
    console.log(`   同接收人今日条数 (max)     : ${s.recipients_today_max}`);
    console.log(`   同接收人今日条数 (p99)     : ${s.recipients_today_p99}`);
    return;
  }

  if (LIST_DENSITY) {
    const rows = await listDensity();
    if (rows.length === 0) {
      console.log("(无 active 推送)");
      return;
    }
    console.log("📈 推送列表膨胀分布 (按同客户 active 数):");
    for (const r of rows) {
      console.log(`   ${r.bucket.padEnd(8)} 条推送  覆盖 ${r.customer_count} 个客户`);
    }
    return;
  }

  console.log("============================================================");
  console.log(" 客户推送 (customer_share) 巡检");
  console.log("============================================================\n");

  const [cross, unauth, dup, inactive, softDel] = await Promise.all([
    findCrossBranch(),
    findUnauthorized(),
    findDuplicateActive(),
    findInactiveUsers(),
    findSoftDeletedFranchisees(),
  ]);

  let hasError = false;

  console.log("1) 跨枝推送 (S2 防护检查; admin 无枝豁免)");
  if (cross.length === 0) {
    console.log("   ✅ 无跨枝推送\n");
  } else {
    hasError = true;
    console.log(`   ❌ 发现 ${cross.length} 条跨枝推送:`);
    for (const r of cross) {
      console.log(
        `     #${r.share_id} cust#${r.customer_id} ${r.from_name} (root=${r.from_root_id ?? "∅"}) → ${r.to_name} (root=${r.to_root_id ?? "∅"})`,
      );
    }
    console.log();
  }

  console.log("2) 越权推送 (S1 归属人/admin; 推到 owner=NULL 也算越权)");
  if (unauth.length === 0) {
    console.log("   ✅ 无越权推送\n");
  } else {
    hasError = true;
    console.log(`   ❌ 发现 ${unauth.length} 条越权推送:`);
    for (const r of unauth) {
      console.log(
        `     share#${r.share_id} cust#${r.customer_id} from=${r.from_name}(#${r.from_user_id}) 但 customer.owner=${r.owner_name ?? "∅"}`,
      );
    }
    console.log();
  }

  console.log("3) 重复 active (S4 部分唯一索引应该拦); 索引漏了=真出错");
  if (dup.length === 0) {
    console.log("   ✅ 无重复 active\n");
  } else {
    hasError = true;
    console.log(`   ❌ 发现 ${dup.length} 个 (customer, to_user) 有多条 active:`);
    for (const r of dup) {
      console.log(
        `     cust#${r.customer_id} → user#${r.to_user_id}: count=${r.count}, share ids=${r.share_ids.join(",")}`,
      );
    }
    console.log();
  }

  console.log("4) 推送双方账号停用 (SHARE-4; SQL EXISTS user active 子句应过滤)");
  if (inactive.length === 0) {
    console.log("   ✅ 没有 active 推送挂在停用账号上\n");
  } else {
    hasError = true;
    console.log(`   ❌ 发现 ${inactive.length} 条 active 推送挂在停用账号上:`);
    for (const r of inactive) {
      console.log(
        `     share#${r.share_id} from=${r.from_name}(active=${r.from_active}) → to=${r.to_name}(active=${r.to_active})`,
      );
    }
    console.log();
  }

  console.log("5) 推送人 franchisee 节点软删 (主文档 §3.4 (c) 「推送人节点软删失效」)");
  if (softDel.length === 0) {
    console.log("   ✅ 没有 active 推送挂在软删节点上\n");
  } else {
    hasError = true;
    console.log(`   ❌ 发现 ${softDel.length} 条 active 推送的推送人节点已软删:`);
    for (const r of softDel) {
      console.log(
        `     share#${r.share_id} cust#${r.customer_id} fromUser#${r.from_user_id} franchisee#${r.from_franchisee_id} deleted_at=${r.ff_deleted_at}`,
      );
    }
    console.log();
  }

  if (STRICT && hasError) {
    console.error("\n❌ --strict: 有异常 → exit 1");
    process.exit(1);
  } else if (!hasError) {
    console.log("✅ 全绿 — 推送机制无异常");
  } else {
    console.log("\n(非 --strict, 只报告不退出; 主家可按清单查审计)");
  }
}

main().catch((e) => {
  console.error("💥", e);
  process.exit(1);
});
