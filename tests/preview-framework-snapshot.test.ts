/**
 * tests/preview-framework-snapshot.test.ts
 *
 * 预览框架冻结 — Vitest snapshot test (L4 验收兜底)
 *
 * 守护目标:
 *   1. 9 个冻结路径每个都 ≥ 1 文件存在 (防止被整个目录 rm 掉)
 *   2. public/app/version.json 字段 framework_version 与 baseline tag 一致
 *   3. guard 脚本的 FROZEN_PATHS 数组与本测试的 EXPECTED 数组一致 (防止 guard 改后忘同步)
 *
 * 与 ADR-0009 §2.4 / AGENTS §9.6 验收清单对应.
 * 见: docs/adr/0009-preview-framework-freeze.md
 */

import { describe, it, expect } from "vitest";
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { execSync } from "node:child_process";

// ============ 期望冻结清单 (与 ADR-0009 §1 + AGENTS §9.1 + dev-modules/flutter-preview.md §Frozen Contract 同源) ============
// 改动本数组时, 必须同步:
//   1. docs/adr/0009-preview-framework-freeze.md §1 冻结清单
//   2. AGENTS.md §9.1 红线 (一图概览)
//   3. docs/dev-modules/flutter-preview.md §Frozen Contract
//   4. tools/pre-commit-preview-guard.sh 的 FROZEN_PATHS 数组
//   5. e2e/preview-smoke.spec.ts (引用同套)
const EXPECTED_FROZEN_PATHS = [
  "src/app/app-preview/",
  "src/app/preview/",
  "src/components/preview/",
  "tools/build-flutter-web.sh",
  "tools/dev-app-proxy.py",
  "tools/install-dev-app-proxy.sh",
  "tools/install-flutter-dev-tunnel.sh",
  "tools/start-flutter-dev.sh",
  "public/app/",
] as const;

// 期望 baseline framework version (从 baseline-preview-v0.1.4-280f5fa tag 时打的)
// 当前 public/app/version.json 字段: version, build_number (2026-09-16 是 0.2.2#3)
// version 由 tools/build-flutter-web.sh 自动 bump, 不应硬编码具体值; 此处仅检查格式.
// 见 CHANGELOG [0.5.2] 验收项

// ============ helpers ============
const PROJECT_ROOT = process.cwd();

function countFiles(dir: string): number {
  const full = join(PROJECT_ROOT, dir);
  if (!existsSync(full)) return 0;
  const stat = statSync(full);
  if (!stat.isDirectory()) return 1;
  let count = 0;
  for (const entry of readdirSync(full, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue; // skip .DS_Store etc.
    const p = join(full, entry.name);
    if (entry.isDirectory()) {
      count += countFiles(join(dir, entry.name));
    } else {
      count += 1;
    }
  }
  return count;
}

function fileExists(p: string): boolean {
  const full = join(PROJECT_ROOT, p);
  return existsSync(full);
}

function readGuardFrozenPaths(): string[] {
  const guardPath = join(PROJECT_ROOT, "tools/pre-commit-preview-guard.sh");
  if (!existsSync(guardPath)) return [];
  const content = readFileSync(guardPath, "utf-8");
  // 匹配 FROZEN_PATHS=( ... \n ) (多行, 以行首 ) 结束 — 避开注释里的 ) 字符
  // eslint-disable-next-line no-useless-escape
  const block = content.match(/FROZEN_PATHS=\(([\s\S]*?)^\)/m);
  if (!block) return [];
  const quotedRe = /"([^"]+)"/g;
  const paths: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = quotedRe.exec(block[1])) !== null) {
    paths.push(m[1]);
  }
  return paths;
}

function readVersionJson(): { version?: string; build_number?: string } | null {
  const v = join(PROJECT_ROOT, "public/app/version.json");
  if (!existsSync(v)) return null;
  try {
    return JSON.parse(readFileSync(v, "utf-8"));
  } catch {
    return null;
  }
}

function getBaselineSha(): string {
  // 列出 baseline-preview-v0.1.4-* tag, 取第一个
  try {
    const out = execSync("git tag -l 'baseline-preview-v0.1.4-*'", {
      cwd: PROJECT_ROOT,
      encoding: "utf-8",
    });
    const tags = out.trim().split("\n").filter(Boolean);
    return tags[0] ?? "";
  } catch {
    return "";
  }
}

// ============ tests ============

describe("Preview Framework Freeze — Snapshot Test (ADR-0009, AGENTS §9)", () => {
  describe("1. 9 冻结路径每个都 ≥ 1 文件存在", () => {
    for (const path of EXPECTED_FROZEN_PATHS) {
      it(`应存在: ${path}`, () => {
        if (path.endsWith("/")) {
          // 目录: 应有 ≥ 1 文件
          const count = countFiles(path);
          expect(count, `${path} 应有 ≥ 1 文件`).toBeGreaterThan(0);
        } else {
          // 单文件
          expect(fileExists(path), `${path} 应存在`).toBe(true);
        }
      });
    }
  });

  describe("2. 版本一致性 (public/app/version.json)", () => {
    it("version.json 应存在且可解析", () => {
      const v = readVersionJson();
      expect(v, "public/app/version.json 应存在").not.toBeNull();
      // 当前格式: { app_name, version, build_number, package_name }
      expect(v?.version, "应有 version 字段").toBeDefined();
      expect(v?.build_number, "应有 build_number 字段").toBeDefined();
    });

    it("version 应是非空 semver-like 字符串", () => {
      const v = readVersionJson();
      expect(v?.version).toMatch(/^\d+\.\d+\.\d+$/);
      expect(v?.build_number).toMatch(/^\d+$/);
    });

    it("version.json mtime 不应 > 90 天 (防 stale baseline)", () => {
      const p = join(PROJECT_ROOT, "public/app/version.json");
      if (!existsSync(p)) return; // 已在前一个 test 检查
      const stat = statSync(p);
      const ageDays = (Date.now() - stat.mtimeMs) / (1000 * 60 * 60 * 24);
      expect(
        ageDays,
        `version.json mtime = ${ageDays.toFixed(1)} 天, > 90 天说明 baseline 太久没更新`
      ).toBeLessThan(90);
    });
  });

  describe("3. guard 脚本与测试期望一致 (防止改 guard 忘同步)", () => {
    it("tools/pre-commit-preview-guard.sh FROZEN_PATHS 应与 EXPECTED_FROZEN_PATHS 完全一致", () => {
      const guardPaths = readGuardFrozenPaths();
      expect(guardPaths.length).toBeGreaterThan(0);
      expect(
        guardPaths,
        "guard FROZEN_PATHS 与测试 EXPECTED_FROZEN_PATHS 应一致 (防脱钩)"
      ).toEqual([...EXPECTED_FROZEN_PATHS]);
    });

    it("guard 脚本应存在且可执行", () => {
      const guardPath = join(PROJECT_ROOT, "tools/pre-commit-preview-guard.sh");
      expect(existsSync(guardPath)).toBe(true);
      const stat = statSync(guardPath);
      // 0o755 = rwxr-xr-x
      expect(stat.mode & 0o111, "guard 应可执行").toBeGreaterThan(0);
    });
  });

  describe("4. baseline tag 应存在", () => {
    it("git tag -l 'baseline-preview-v0.1.4-*' 应至少 1 个 tag", () => {
      const tag = getBaselineSha();
      expect(tag, "至少应存在 1 个 baseline-preview-v0.1.4-* tag").toMatch(
        /^baseline-preview-v0\.1\.4-[0-9a-f]+$/
      );
    });
  });

  describe("5. guard 自检 (--check mode)", () => {
    it("guard --check 应 exit 0 + 输出 9 个路径", () => {
      try {
        const out = execSync("bash tools/pre-commit-preview-guard.sh --check", {
          cwd: PROJECT_ROOT,
          encoding: "utf-8",
        });
        expect(out).toContain("Preview Framework Guard");
        // 期望每个路径都出现
        for (const p of EXPECTED_FROZEN_PATHS) {
          const stripped = p.replace(/\/$/, "");
          expect(
            out,
            `--check 输出应含 ${stripped}`
          ).toContain(stripped);
        }
      } catch (e: any) {
        throw new Error(`guard --check 失败: ${e.message}`);
      }
    });
  });
});
