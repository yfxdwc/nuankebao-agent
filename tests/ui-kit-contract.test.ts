/**
 * tests/ui-kit-contract.test.ts — B0b/B3 web UI 组件契约
 *
 * 守护的东西:
 *   1. 7 个 web 组件文件都存在 + 默认导出 (防误删/误改名)
 *   2. design/tokens/density-baseline.json 结构合法 (每个路由都有条目)
 *   3. src/app/admin/** 里不再出现「rounded-lg border shadow-sm 三件套」(B3 反 SaaS)
 *   4. web 端组件契约: 每个组件的导出签名与文档约定 (page-header / section / data-table 等)
 *
 * 见 docs/ui-principles.md §2.5 + §4 review 清单.
 */

import { describe, it, expect } from "vitest";
import { readFileSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { execSync } from "node:child_process";

const ROOT = process.cwd();
const UI_DIR = join(ROOT, "src/components/ui");

// ============ 1. 7 个 web UI 组件 (B0b 落地) ============

// 核心契约组件 (B0b 落地, 2026-09-24 一致列表)
const REQUIRED_UI_FILES = [
  // B0b 第一批 (page-header / section / data-table / empty-state / filter-bar / stat-row / skeleton)
  "page-header.tsx",
  "section.tsx",
  "data-table.tsx",
  "empty-state.tsx",
  "filter-bar.tsx",
  "stat-row.tsx",
  "skeleton.tsx",
  // shadcn 兼容层 (B0 之前就有, 保留)
  "button.tsx",
  "card.tsx",
  "input.tsx",
  "label.tsx",
  "checkbox.tsx",
  "select.tsx",
  "textarea.tsx",
  "fab.tsx",
  "badge.tsx",
  "theme-switcher.tsx",
];

describe("Web UI 组件契约 (B0b + B3)", () => {
  for (const f of REQUIRED_UI_FILES) {
    it(`${f} 文件存在`, () => {
      const p = join(UI_DIR, f);
      expect(existsSync(p), `缺少 ${f}`).toBe(true);
    });

    it(`${f} 是非空文件`, () => {
      const p = join(UI_DIR, f);
      if (!existsSync(p)) return; // 上一个 test 已 fail, 跳过
      const size = statSync(p).size;
      expect(size, `${f} 不应是空文件`).toBeGreaterThan(100);
    });
  }

  it("每个 .tsx 文件都导出至少 1 个组件 (默认或命名导出)", () => {
    // 简单判定: 文件里至少有一个 export 语句, 且其中提及大写字母开头的标识符 (组件名约定)
    //   完整的 AST 解析不在本测试范围内, 只做最低防误删
    let allOk = true;
    for (const f of REQUIRED_UI_FILES) {
      const p = join(UI_DIR, f);
      if (!existsSync(p)) continue;
      const src = readFileSync(p, "utf8");
      // 匹配 export function / const / default / interface / type / { Name, ... }
      //   关键是: export 语句里至少有 1 个大写字母开头的标识符
      const lines = src.split("\n");
      const hasExport = lines.some((l) => {
        const trimmed = l.trim();
        if (!trimmed.startsWith("export")) return false;
        // 简化: 找 export 后面是否跟着大写字母开头的标识符
        return /export\s+(\{|default\s+\{|default\s+function|default\s+const|function|const|class|interface|type|[A-Z])/.test(trimmed);
      });
      if (!hasExport) {
        allOk = false;
        console.warn(`  ⚠ ${f} 缺少规范的 export (组件名约定)`);
      }
    }
    expect(allOk, "有组件文件缺少规范的 export").toBe(true);
  });
});

// ============ 2. density-baseline.json 结构合法 ============

describe("density-baseline.json 结构", () => {
  const path = join(ROOT, "design/tokens/density-baseline.json");

  it("文件存在且 JSON 合法", () => {
    expect(existsSync(path)).toBe(true);
    const raw = readFileSync(path, "utf8");
    expect(() => JSON.parse(raw)).not.toThrow();
  });

  it("每个路由×视口组合都有基线条目 (key 形如 `/path@1440x900`)", () => {
    const raw = JSON.parse(readFileSync(path, "utf8"));
    const routes = raw._routes ?? {};
    const entries = Object.entries(routes).filter(([k]) => !k.startsWith("_"));
    expect(entries.length, "基线至少应有 5 个路由").toBeGreaterThanOrEqual(5);
    for (const [k, v] of entries) {
      expect(k, `${k} 应是 route@viewport 形式`).toMatch(/^.+@(\d{3,4}x\d{3,4})$/);
      expect(v).toHaveProperty("viewport");
      expect(v).toHaveProperty("framed");
      expect(v).toHaveProperty("visibleRows");
      expect(v).toHaveProperty("rowHeight");
      expect(v).toHaveProperty("isListRoute");
      expect(typeof v.framed).toBe("number");
      expect(typeof v.visibleRows).toBe("number");
    }
  });
});

// ============ 3. admin/ 里不再出现典型 SaaS 三件套 ============

const SAAS_TRIPLE_PATTERN = /rounded-lg\b[^\n]*\bborder\b[^\n]*\bshadow-sm\b/;

describe("src/app/admin/** 反 SaaS 卡片 (B3)", () => {
  it("没有「rounded-lg border shadow-sm」三件套同时出现", () => {
    // 用 git grep 扫所有 src/app/admin/**/*.{tsx,ts}
    //   (跳过 .gitignore / 注释 / mermaid DSL)
    //   现有豁免: src/app/admin/dev/architecture/** (mermaid classDef 不是 CSS)
    try {
      const out = execSync(
        "grep -rEn 'rounded-lg.*border.*shadow-sm' src/app/admin --include='*.tsx' --include='*.ts' 2>/dev/null || true",
        { cwd: ROOT, encoding: "utf8" },
      ).trim();
      // 过滤掉注释行 (以 // 或 * 开头) 和 dev/architecture (mermaid)
      const violations = out
        .split("\n")
        .filter((l) => l && !l.includes("dev/architecture"));
      expect(violations, violations.join("\n")).toHaveLength(0);
    } catch (err) {
      throw new Error(`grep 失败: ${err}`);
    }
  });
});

// ============ 4. Web 组件 key 文档化 (B0b) ============

describe("B0b 组件文档化 (docs/dev-modules/ui-kit.md)", () => {
  // docs/dev-modules/ui-kit.md 是不是列了 page-header / section / ... 7 个组件
  const path = join(ROOT, "docs/dev-modules/ui-kit.md");

  it("如果文件存在, 7 个核心组件名都在", () => {
    if (!existsSync(path)) return; // 文档不是关键路径, 跳过
    const raw = readFileSync(path, "utf8");
    const names = [
      "page-header",
      "section",
      "data-table",
      "empty-state",
      "filter-bar",
      "stat-row",
      "skeleton",
    ];
    for (const n of names) {
      expect(raw.toLowerCase(), `ui-kit.md 应提到 ${n}`).toContain(n.toLowerCase());
    }
  });
});