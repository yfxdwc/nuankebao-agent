// ============================================
// drizzle-kit generate 输出检测: 防止 snapshot 落后时的"假 diff"被静默 apply
// ============================================
//
// 背景 (docs/backlog.md 2026-09-23 「技术债 · drizzle snapshot 只到 0016」):
//   本仓 drizzle/meta/ snapshot 只到 0016, 之后 0017-0024 都是手写迁移
//   (仓里 *README 注释 + 每条 .sql 顶部注释都讲过原因)。drizzle-kit generate
//   拿最后一份 snapshot (0016) 与 src/lib/db/schema.ts 比对 → 会把 0017-0024
//   的所有变更**整段重放**到一份「0025_xxx.sql」里。apply 到已有库 =
//   重复 ALTER / 重复建表, 灾难级误操作。
//
// 本文件 = 纯函数检测 (可单测) + 干跑 drizzle-kit 的小 CLI 入口
// 配套 bash 包装: tools/check-drizzle-generate.sh (用它而不是直接 drizzle-kit)
//
// 设计取舍:
//   - 「已知表 / 索引」直接 grep drizzle/*.sql 收集 (不维护硬编码清单,
//     跟 schema 自动同步, 新加表不用改本文件)
//   - 只标高危模式 (CREATE 已存在表 / ALTER 已存在表 / DROP 已存在索引);
//     CREATE INDEX IF NOT EXISTS 之类 idempotent 写法不误报
//   - 注释行 / 空 statement 跳过, 不算命中
//   - 「存在」的判定基于已 apply 的 drizzle/*.sql (人工手写的也算),
//     不基于真实数据库 (本脚本不连库, 离线可用)
// ============================================

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

// ============================================
// 类型
// ============================================

export type DangerKind =
  | "create-existing-table"      // CREATE TABLE "X" 其中 X 已在历史里建过
  | "alter-existing-table"       // ALTER TABLE "X" ... (对已存在表做结构变更)
  | "drop-existing-index";       // DROP INDEX "X" 其中 X 已在历史里建过

export type DangerReason = {
  kind: DangerKind;
  /** 命中的对象名 (table 或 index) */
  name: string;
  /** 完整 SQL statement (一行) */
  statement: string;
  /** 在生成文件中的行号 (1-indexed) */
  line: number;
};

export type ExistingObjects = {
  tables: Set<string>;
  indexes: Set<string>;
};

// ============================================
// 收集「仓库里已有」的表 / 索引
// ============================================
// 扫描 <drizzleDir>/*.sql, 排除 audit / meta / down 目录
// 解析每条 CREATE TABLE / CREATE [UNIQUE] INDEX 语句
// ============================================
export function collectExistingObjects(drizzleDir: string): ExistingObjects {
  const tables = new Set<string>();
  const indexes = new Set<string>();

  if (!existsSync(drizzleDir)) {
    return { tables, indexes };
  }

  const files = readdirSync(drizzleDir)
    .filter((f) => f.endsWith(".sql"))
    // 排除 audit 系统文件 (不是业务 schema) + 排除未来可能加的其他非迁移文件
    .filter((f) => !f.startsWith("audit_"))
    .filter((f) => f !== "audit_function.sql")
    .sort();

  for (const f of files) {
    const content = readFileSync(join(drizzleDir, f), "utf-8");
    // 拆 statement (drizzle 用 "--> statement-breakpoint" 分隔)
    const statements = content.split(/-->\s*statement-breakpoint/i);

    for (const stmt of statements) {
      const cleaned = stmt.replace(/--.*$/gm, "");
      collectFromStatement(cleaned, tables, indexes);
    }
  }

  return { tables, indexes };
}

// 抽出来方便测试单条 statement 解析
function collectFromStatement(
  stmt: string,
  tables: Set<string>,
  indexes: Set<string>,
): void {
  // CREATE TABLE [IF NOT EXISTS] "name"
  const createTable = stmt.match(
    /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?"([^"]+)"/i,
  );
  if (createTable) {
    tables.add(createTable[1]);
  }

  // CREATE [UNIQUE] INDEX [IF NOT EXISTS] "name"
  const createIndex = stmt.match(
    /CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?"([^"]+)"/i,
  );
  if (createIndex) {
    indexes.add(createIndex[1]);
  }
}

// ============================================
// 纯函数: 在一段 SQL 中检测「重放已存在对象」危险
// ============================================
//
// 设计:
//   - 按 --> statement-breakpoint 拆, 一条 statement 命中一次就算
//   - CREATE TABLE / ALTER TABLE / DROP INDEX 三类危险
//   - IF NOT EXISTS 不豁免 (snapshot 落后时, 意图就是错的; 哪怕 idempotent
//     也会导致 schema.ts 与 db 不同步)
//   - CREATE INDEX IF NOT EXISTS 等安全模式不报 (idempotent + 增量合理)
// ============================================
export function detectReplay(
  sql: string,
  existing: ExistingObjects,
): DangerReason[] {
  const reasons: DangerReason[] = [];

  // 按 statement-breakpoint 拆: 保留分隔符位置, 避免 "DROP X;--> statement-breakpoint\nALTER Y;"
  // 这种同行的语义被吞掉。拆完后每块 = 一个 statement (可能含或不含 ; 结尾)。
  const separator = /-->\s*statement-breakpoint/i;
  const parts = sql.split(separator);

  // 对每块: 用 indexOf 定位第一个出现的字符位置 (各 part 不会重复), 算出起始行号
  let searchFrom = 0;
  for (const part of parts) {
    // 跳过 slice 下前面 part 占用的范围, 找这一块在原 sql 里的起点
    let partStart = -1;
    if (part.length > 0) {
      partStart = sql.indexOf(part, searchFrom);
      // 万一 indexOf 返回 -1 (理论上不应该), 退到 searchFrom
      if (partStart < 0) partStart = searchFrom;
    } else {
      // 空 chunk (连续分隔符间): 起点 = searchFrom
      partStart = searchFrom;
    }

    // 跳过 chunk 开头的连续换行 (它们是上一行的尾巴, 不算本 chunk 的语义行号)
    let leadingNewlines = 0;
    while (
      leadingNewlines < part.length &&
      part[leadingNewlines] === "\n"
    ) {
      leadingNewlines++;
    }
    const partNoLeading = part.slice(leadingNewlines);

    const startLine =
      sql.slice(0, partStart + leadingNewlines).split("\n").length;
    // split("\n") on "a\nb\n" → ["a","b",""], length 3 = number of segments.
    // 起始行号应该是 (segments 数) 而不是 +1 (因为最后一段空字符串不代表多一行)。
    // 例如 sql = "a\nb", slice = "a", split = ["a"] length 1 = 行 1 ✓
    // 例如 sql = "a\nb\n", slice = "a\nb", split = ["a","b"] length 2 = 行 2 ✓

    const trimmed = part.replace(/--.*$/gm, "").trim();
    if (trimmed && partNoLeading.trim().length > 0) {
      const firstLine = partNoLeading.split("\n")[0].trim();
      const stmtReasons = checkStatement(trimmed, firstLine, startLine, existing);
      reasons.push(...stmtReasons);
    }

    // 推进 searchFrom: 跳过本 part + 后面的分隔符 (如果有)
    searchFrom = partStart + part.length;
    if (searchFrom < sql.length) {
      const sepMatch = sql.slice(searchFrom).match(separator);
      if (sepMatch) searchFrom += sepMatch[0].length;
    }
  }

  return reasons;
}

function checkStatement(
  cleanedStmt: string,
  originalStmt: string,
  startLine: number,
  existing: ExistingObjects,
): DangerReason[] {
  const out: DangerReason[] = [];

  // 1) CREATE TABLE [IF NOT EXISTS] "existing"
  const createTableMatch = cleanedStmt.match(
    /^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?"([^"]+)"/i,
  );
  if (createTableMatch) {
    const name = createTableMatch[1];
    if (existing.tables.has(name)) {
      out.push({
        kind: "create-existing-table",
        name,
        statement: originalStmt.split("\n")[0],
        line: startLine,
      });
    }
    return out;
  }

  // 2) ALTER TABLE "existing" ... <危险子句>
  //    危险子句 = ADD COLUMN / DROP COLUMN / ADD CONSTRAINT / RENAME COLUMN/TABLE /
  //              ALTER COLUMN (任何形式)
  //    例外: 仅 SET DEFAULT 之类轻量操作, 但为安全起见不豁免任何 ALTER (snapshot 落后
  //          时任何 ALTER 都可疑; 主人真要 ALTER 走手写 migration)
  const alterMatch = cleanedStmt.match(/^ALTER\s+TABLE\s+(?:"([^"]+)"|(\w+))/i);
  if (alterMatch) {
    const table = alterMatch[1] ?? alterMatch[2];
    if (existing.tables.has(table)) {
      // ALTER TABLE 命中"已存在表"即危险 — drizzle-kit 在 snapshot 落后时输出的
      // ALTER 几乎全是「对已存在表加/改列」, 全部需要人话拦截
      out.push({
        kind: "alter-existing-table",
        name: table,
        statement: originalStmt.split("\n")[0],
        line: startLine,
      });
    }
    return out;
  }

  // 3) DROP INDEX [IF EXISTS] "existing"
  const dropIndexMatch = cleanedStmt.match(
    /^DROP\s+INDEX\s+(?:IF\s+EXISTS\s+)?"([^"]+)"/i,
  );
  if (dropIndexMatch) {
    const name = dropIndexMatch[1];
    if (existing.indexes.has(name)) {
      out.push({
        kind: "drop-existing-index",
        name,
        statement: originalStmt.split("\n")[0],
        line: startLine,
      });
    }
    return out;
  }

  return out;
}

// ============================================
// CLI 入口 (被 bash 包装调用, 也可单独 tsx 运行调试)
// 用法: tsx tools/check-drizzle-generate.ts <generated-sql-file>
// 退出码:
//   0 = 无危险
//   1 = 检测到重放 (危险)
//   2 = 调用错误 (参数缺 / 文件不存在)
// ============================================
export function runCli(argv: string[]): number {
  const sqlPath = argv[2];
  const drizzleDir = argv[3];
  if (!sqlPath) {
    console.error("用法: tsx tools/check-drizzle-generate.ts <generated-sql-file> <repo-drizzle-dir>");
    return 2;
  }
  if (!drizzleDir) {
    console.error("用法: tsx tools/check-drizzle-generate.ts <generated-sql-file> <repo-drizzle-dir>");
    console.error("  <repo-drizzle-dir> 必填, 避免检测函数与生成输出在同一目录造成自我污染");
    return 2;
  }
  if (!existsSync(sqlPath)) {
    console.error(`❌ 文件不存在: ${sqlPath}`);
    return 2;
  }

  const existing = collectExistingObjects(drizzleDir);
  const sql = readFileSync(sqlPath, "utf-8");
  const reasons = detectReplay(sql, existing);

  if (reasons.length === 0) {
    return 0;
  }

  console.error("");
  console.error("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.error("🚫 drizzle-kit generate 输出检测到「重放历史变更」危险");
  console.error("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.error(
    `扫描基线: drizzle/*.sql 中已有 ${existing.tables.size} 张表 / ${existing.indexes.size} 个索引`,
  );
  console.error("");
  for (const r of reasons) {
    const label = {
      "create-existing-table": "CREATE 已存在表",
      "alter-existing-table": "ALTER 已存在表",
      "drop-existing-index": "DROP 已存在索引",
    }[r.kind];
    console.error(`  [${label}] 行 ${r.line}: ${r.statement}`);
    console.error(`     → 对象: "${r.name}"`);
  }
  console.error("");
  console.error("根因: drizzle/meta/ 的 snapshot 落后于 drizzle/*.sql 的真实历史");
  console.error("      (本仓 snapshot 只到 0016, 0017-0024 都是手写迁移 — 见 docs/backlog.md)");
  console.error("");
  console.error("正确做法 (手写迁移, 不要用 drizzle-kit generate):");
  console.error("  1. 自己写 drizzle/<NNNN>_your_change.sql (见 0024_app_config.sql 格式)");
  console.error("  2. 在 drizzle/meta/_journal.json 追加一条:");
  console.error("     {");
  console.error('       "idx": <上一条 idx+1>,');
  console.error('       "version": "7",');
  console.error('       "when": <new Date().getTime()>,');
  console.error('       "tag": "<NNNN>_your_change",');
  console.error('       "breakpoints": true');
  console.error("     }");
  console.error("  3. (破坏性变更) 补 drizzle/down/<同名>.down.sql + 跑 pnpm db:compat");
  console.error("");
  console.error("逃逸口 (主人拍板后): 如果这条输出经确认就是真变更,");
  console.error("    把内容人工 review 后改名为 0025_xxx.sql + 追加 journal 条目");
  console.error("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  return 1;
}

// 仅当直接 tsx 调用才执行 CLI; 测试 import 时不会触发
// import.meta.url 在 vitest/tsx 下都能用
const invokedDirectly = (() => {
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return import.meta.url === `file://${(process.argv[1] ?? "")}`;
  } catch {
    return false;
  }
})();
if (invokedDirectly) {
  process.exit(runCli(process.argv));
}