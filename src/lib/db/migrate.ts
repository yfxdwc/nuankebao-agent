// ============================================
// 暖客宝 数据库 migration 脚本
// 跑:
//   pnpm db:migrate           (应用 up migration + 审计触发器)
//   pnpm db:migrate:down <idx> (单步 down, idx 是 drizzle/meta/_journal.json 里的序号)
//   pnpm db:migrate:check     (只跑 compat 检查, 不实际跑 SQL)
// ============================================
// 依据: CHARTER §3.5 Schema 演进红线 + ADR-0004
// 集成: tools/check-migration-compat.sh (CI 阻断)
// ============================================

import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { config as loadEnv } from "dotenv";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { join } from "node:path";

// 主机跑需要 .env.local 的 localhost 地址
loadEnv({ path: ".env.local" });

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL is not set in .env.local");
}

// ============================================
// 检查 migration 兼容性 (CHARTER §3.5)
// ============================================
function checkMigrationCompat(): boolean {
  console.log("[0/4] 检查 migration 兼容性 (CHARTER §3.5)...");
  try {
    execSync("bash tools/check-migration-compat.sh", {
      stdio: "inherit",
      cwd: process.cwd(),
    });
    console.log("✓ migration 兼容性通过\n");
    return true;
  } catch (error) {
    console.error("\n❌ migration 兼容性检测失败");
    console.error("   修复 ❌ 项后重跑, 或主人 ask_user 拍板例外 (ADR 留档)");
    return false;
  }
}

// ============================================
// 应用 up migration (drizzle 自动)
// ============================================
async function applyUpMigrations(sql: postgres.Sql, db: ReturnType<typeof drizzle>) {
  console.log("[2/4] 应用 Drizzle up migration...");
  await migrate(db, { migrationsFolder: "./drizzle" });
  console.log("✓ Drizzle up migration 完成\n");
}

// ============================================
// 审计触发器函数 (必须先于 up migration)
//
// 背景 (2026-09-19 P1, 新库首部署暴露):
//   migration 0010 里直接 CREATE TRIGGER ... EXECUTE FUNCTION audit_trigger(),
//   而函数原先只在 up migration **之后** 才创建 → 全新库跑到 0010 必报
//   "function audit_trigger() does not exist" (dev 库因历史增量迁移掩盖了此问题)。
//   修法: 函数定义拆到 drizzle/audit_function.sql, 在 up migration 之前先建。
// ============================================
async function applyAuditFunction(sql: postgres.Sql) {
  console.log("[1/4] 创建审计触发器函数...");
  const fnPath = join(process.cwd(), "drizzle", "audit_function.sql");
  const fnSql = readFileSync(fnPath, "utf-8");
  await sql.unsafe(fnSql);
  console.log("✓ 审计触发器函数创建完成\n");
}

// ============================================
// 应用审计触发器 (CHARTER §3.1)
// ============================================
async function applyAuditTriggers(sql: postgres.Sql) {
  console.log("[3/4] 创建审计触发器...");
  const auditSqlPath = join(process.cwd(), "drizzle", "audit_trigger.sql");
  const auditSql = readFileSync(auditSqlPath, "utf-8");
  await sql.unsafe(auditSql);
  console.log("✓ 审计触发器创建完成\n");
}

// ============================================
// 应用 down migration (单步, 按 idx)
// ============================================
async function rollbackMigration(sql: postgres.Sql, idx: number) {
  console.log(`[rollback] 回滚 migration idx=${idx}...`);

  // 从 drizzle/meta/_journal.json 读 idx 对应的 tag
  const journalPath = join(process.cwd(), "drizzle", "meta", "_journal.json");
  if (!existsSync(journalPath)) {
    throw new Error(`找不到 ${journalPath}`);
  }
  const journal = JSON.parse(readFileSync(journalPath, "utf-8"));
  const entry = journal.entries.find((e: any) => e.idx === idx);
  if (!entry) {
    throw new Error(`idx=${idx} 不在 _journal.json 里 (现有 ${journal.entries.length} 条)`);
  }

  const tag = entry.tag; // e.g., "0000_elite_ultimo"
  const downPath = join(process.cwd(), "drizzle", "down", `${tag}.sql`);

  if (!existsSync(downPath)) {
    throw new Error(
      `找不到 down 文件: ${downPath}\n` +
        `  → 加性 migration (CREATE TABLE / ADD COLUMN) 可不强求 down, 但破坏性 migration 必带\n` +
        `  → 见 CHARTER §3.5 + ADR-0004`,
    );
  }

  const downSql = readFileSync(downPath, "utf-8");
  console.log(`  → 读取 ${downPath}`);

  await sql.begin(async (tx) => {
    await tx.unsafe(downSql);
  });

  console.log(`✓ 回滚 ${tag} 完成\n`);

  // 从 __drizzle_migrations 表删记录 (让 up migration 可重跑)
  await sql`
    DELETE FROM drizzle.__drizzle_migrations
    WHERE id = ${entry.when}
  `;
  console.log(`✓ 清理 migration journal\n`);
}

// ============================================
// 主流程
// ============================================
async function runMigrations() {
  const args = process.argv.slice(2);
  const command = args[0];

  console.log("=========================================");
  console.log(" 暖客宝 数据库 migration");
  console.log("=========================================");
  console.log("");

  const sql = postgres(connectionString!, { max: 1 });
  const db = drizzle(sql);

  try {
    if (command === "check") {
      // 只跑 compat 检查
      checkMigrationCompat();
      return;
    }

    if (command === "down") {
      // 回滚
      const idx = parseInt(args[1], 10);
      if (isNaN(idx)) {
        throw new Error("用法: pnpm db:migrate:down <idx>");
      }
      await rollbackMigration(sql, idx);
      return;
    }

    // 默认: 应用 up migration
    // 0. 跑 compat 检查 (不阻断,只警告,但主流程打印)
    const compatOk = checkMigrationCompat();
    if (!compatOk) {
      // compat 检查返回错误码但有 error, 等下脚本会非零退出
      // 这里给主人拍板机会
      console.warn(
        "\n⚠️ compat 检查失败, 但仍尝试跑 migration (主人 review 决定是否中断)",
      );
    }
    console.log("");

    await applyAuditFunction(sql);
    await applyUpMigrations(sql, db);
    await applyAuditTriggers(sql);

    console.log("✓ migration 全部完成");
  } catch (error) {
    console.error("✗ migration 失败:", error);
    process.exit(1);
  } finally {
    await sql.end();
    process.exit(0);
  }
}

runMigrations();