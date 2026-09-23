// ============================================
// plan-loader.ts — 静态解析 docs/* → 给 /admin/plan 页面用
//
// v0.1.5 主人 2026-09-23 拍板 (ask_user d3e7f2a1):
// 「admin 端增加开发计划模块」— 独立 /admin/plan, 纯静态渲染,
// 不写数据库, 不写 API, 只 fs.readFile + markdown 解析.
//
// 数据源 (跟 docs/* 同步, 不复制):
// - docs/phase-1-mvp.md  → 周里程碑 (W1 / W2-3 / W4 / W5-6) + 任务勾选
// - CHANGELOG.md         → 最近变更 (## [Unreleased] / ## [vX.Y.Z])
// - docs/adr/INDEX.md    → 最近 ADR 决策时间线
// - package.json         → 当前版本号
//
// 设计原则:
// - 容错优先: 文件不存在/格式变了 → 返回空数组, 页面降级展示, 不 throw
// - 不做过度解析: 只解主人拍板要看的内容 (周/任务/最近 8 条变更/最近 10 条 ADR)
// - 注释充足: 这种解析逻辑半年后会忘, 注释是给半年后的自己看的
// ============================================

import { readFile } from "node:fs/promises";
import path from "node:path";

// ============================================
// 类型 (页面组件只用这几条)
// ============================================

export interface TaskItem {
  text: string;
  done: boolean;
}

export interface WeekPlan {
  /** "W1" / "W2-3" / "W4" / "W5-6" — 从 `## W1 — ...` 头解析 */
  code: string;
  /** 标题去 code 和破折号后的部分 */
  title: string;
  tasks: TaskItem[];
  /** 任务勾选统计 — UI 用来算进度 */
  done: number;
  total: number;
}

export interface ChangeItem {
  /** "[Unreleased] — admin 客户管理参数调节页" — 渲染时直接显示 */
  title: string;
  /** 提取的日期 (2026-09-23) — 没提取到 = undefined */
  date?: string;
  /** UI 用 'unreleased' 给不同色 (warning surface) */
  kind: "unreleased" | "versioned";
  /** 仅 kind=versioned 有: v0.1.6 */
  tag?: string;
}

export interface AdrItem {
  /** "0018" */
  id: string;
  title: string;
  /** "✅ Accepted" / "⚠️ Superseded" / "⏳ Draft" */
  status: string;
  /** "2026-09-23" */
  date: string;
  /** 链接到 ./0018-...md — admin 路由不直接渲染, 跳 GitHub */
  githubPath: string;
}

export interface PlanData {
  weeks: WeekPlan[];
  changes: ChangeItem[];
  adrs: AdrItem[];
  meta: {
    /** package.json 的 version (v0.1.6) */
    version: string;
    /** 当前阶段 (从 AGENTS §7 + phase-1-mvp 头部推断) */
    phase: string;
    /** 渲染时刻 ISO — 给 footer 显示 "最近刷新" */
    fetchedAt: string;
    /** 渲染失败原因 (解析异常时填, UI 显示 warning 块) */
    warnings: string[];
  };
}

// ============================================
// 路径常量 (相对仓库根, dev server 跑时 cwd = nuankebao-agent/)
// ============================================

const REPO_ROOT = process.cwd();
const PHASE_MD = path.join(REPO_ROOT, "docs/phase-1-mvp.md");
const CHANGELOG_MD = path.join(REPO_ROOT, "CHANGELOG.md");
const ADR_INDEX_MD = path.join(REPO_ROOT, "docs/adr/INDEX.md");
const PACKAGE_JSON = path.join(REPO_ROOT, "package.json");

// GitHub raw 链接 (主人在 README 里挂的 remote)
const GITHUB_REPO = "https://github.com/tooyan/nuankebao-agent/blob/main";

// ============================================
// 主入口
// ============================================

export async function loadPlanData(): Promise<PlanData> {
  const warnings: string[] = [];

  // 并行读 4 个文件, 任一失败不影响其它
  const [phaseRaw, changelogRaw, adrRaw, pkgRaw] = await Promise.all([
    readSafe(PHASE_MD),
    readSafe(CHANGELOG_MD),
    readSafe(ADR_INDEX_MD),
    readSafe(PACKAGE_JSON),
  ]);

  const weeks = phaseRaw ? parseWeeks(phaseRaw) : warn(warnings, "phase-1-mvp.md 读不到");
  const changes = changelogRaw ? parseChanges(changelogRaw) : warn(warnings, "CHANGELOG.md 读不到");
  const adrs = adrRaw ? parseAdrs(adrRaw) : warn(warnings, "docs/adr/INDEX.md 读不到");
  const version = pkgRaw ? parseVersion(pkgRaw) : (warn(warnings, "package.json 读不到"), "v?.?");

  return {
    weeks,
    changes,
    adrs,
    meta: {
      version,
      phase: "Phase 1 MVP",
      fetchedAt: new Date().toISOString(),
      warnings,
    },
  };
}

// ============================================
// 工具函数
// ============================================

async function readSafe(filePath: string): Promise<string | null> {
  try {
    return await readFile(filePath, "utf-8");
  } catch {
    return null;
  }
}

function warn(arr: string[], msg: string): [] {
  arr.push(msg);
  return [];
}

// ============================================
// 解析: docs/phase-1-mvp.md → WeekPlan[]
// ============================================
//
// 文件结构 (主人 v0.1.2 写的, 后面估计也按这个格式续):
//   # Phase 1 MVP 实施计划 (6 周)
//   ...
//   ## W1 — 项目骨架 + Docker
//   ### 任务
//   - [ ] xxx
//   - [x] yyy
//   ### 验收
//   ...
//
// 解析策略:
//   1. 按 `^## W\d` 切段 (W1 / W2-3 / W4 / W5-6)
//   2. 每段找 `- [ ]` / `- [x]` 行 → TaskItem
//   3. 标题 = ## 后面的全部, 我们再 strip code
//
function parseWeeks(raw: string): WeekPlan[] {
  const weeks: WeekPlan[] = [];
  const lines = raw.split("\n");

  let current: WeekPlan | null = null;

  for (const line of lines) {
    // 1) 切段: `## W1 — 项目骨架 + Docker`
    const h2 = /^##\s+(W[\w-]+)\s*[—–-]\s*(.+?)\s*$/.exec(line);
    if (h2) {
      if (current) weeks.push(current);
      current = {
        code: h2[1],
        title: h2[2],
        tasks: [],
        done: 0,
        total: 0,
      };
      continue;
    }

    // 2) 段内任务勾选: `- [x] xxx` / `- [ ] xxx`
    //    ⚠ 不能匹配 `- [x] xxx` 出现在代码块里 — 但 phase-1-mvp.md 不用代码块, 暂不管
    const task = /^\s*-\s+\[(x| )\]\s+(.+?)\s*$/.exec(line);
    if (task && current) {
      const done = task[1] === "x";
      current.tasks.push({ text: task[2], done });
      current.total += 1;
      if (done) current.done += 1;
    }
  }

  if (current) weeks.push(current);
  return weeks;
}

// ============================================
// 解析: CHANGELOG.md → ChangeItem[]
// ============================================
//
// 文件结构 (Keep a Changelog):
//   ## [Unreleased] — 标题 (2026-09-23)
//   ## [Unreleased] — 另一条
//   ## [0.1.5] — 2026-09-22
//
// 解析策略: 抓所有 `## [...]` 行, 提取版本/日期/标题
//          只保留最近 8 条 (页面够看就行)
//
function parseChanges(raw: string): ChangeItem[] {
  const items: ChangeItem[] = [];
  const lines = raw.split("\n");

  for (const line of lines) {
    const m = /^##\s+\[([^\]]+)\]\s*[—–-]\s*(.+?)\s*$/.exec(line);
    if (!m) continue;

    const bracket = m[1];
    const rest = m[2];
    const isUnreleased = bracket.toLowerCase() === "unreleased";

    // 优先从 `rest` 末尾抠 `(YYYY-MM-DD)`, 没有就从整行 grep
    const dateInRest = /\((\d{4}-\d{2}-\d{2})\)\s*$/.exec(rest);
    const dateAnywhere = /\((\d{4}-\d{2}-\d{2})\)/.exec(line);
    const date = dateInRest?.[1] ?? dateAnywhere?.[1];

    // 标题去掉尾部日期
    const title = dateInRest ? rest.slice(0, dateInRest.index).trim() : rest;

    items.push({
      title,
      date,
      kind: isUnreleased ? "unreleased" : "versioned",
      tag: isUnreleased ? undefined : bracket,
    });
  }

  // 只要最近 8 条 (page 1 屏可见)
  return items.slice(0, 8);
}

// ============================================
// 解析: docs/adr/INDEX.md → AdrItem[]
// ============================================
//
// 文件结构:
//   | 0018 | [核心定位 — ...](./0018-core-positioning.md) | ✅ Accepted | 2026-09-23 | ... |
//
// 解析策略:
//   1. 抓 `^|` 开头且不含 `^|--` 的行
//   2. 按 `|` split → 至少 5 列
//   3. 0 列 = id, 1 列 = 标题+相对路径, 2 列 = 状态, 3 列 = 日期
//   4. 标题里的相对路径 → githubPath
//
function parseAdrs(raw: string): AdrItem[] {
  const items: AdrItem[] = [];
  const lines = raw.split("\n");

  for (const line of lines) {
    // 跳过表头 + 分隔行 + 空行
    if (!line.startsWith("|")) continue;
    if (line.includes("---")) continue;
    if (line.includes("标题")) continue; // 表头
    if (line.includes("# |")) continue;

    const cells = line.split("|").map((s) => s.trim());
    // 期望至少 6 元素 (| x | x | y | z | w |) — split 出来是 6, 因为前后是空串
    if (cells.length < 6) continue;

    const id = cells[1]; // "0018"
    const titleCell = cells[2]; // "[核心定位 — ...](./0018-core-positioning.md)"
    const status = cells[3]; // "✅ Accepted"
    const date = cells[4]; // "2026-09-23"

    if (!/^\d{3,4}$/.test(id)) continue;

    // 标题拆出 "标题文本" 和 "相对路径"
    const linkMatch = /\[(.+?)\]\(\.\/(.+?\.md)\)/.exec(titleCell);
    if (!linkMatch) continue;
    const title = linkMatch[1];
    const mdPath = linkMatch[2];

    items.push({
      id,
      title,
      status,
      date,
      githubPath: `${GITHUB_REPO}/docs/adr/${mdPath}`,
    });
  }

  // 只要最近 10 条 (page 1 屏可见)
  return items.slice(0, 10);
}

// ============================================
// 解析: package.json → version
// ============================================
function parseVersion(raw: string): string {
  try {
    const pkg = JSON.parse(raw);
    return pkg.version ? `v${pkg.version}` : "v?.?";
  } catch {
    return "v?.?";
  }
}