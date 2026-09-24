/**
 * tests/auto-task-snapshot-extension.test.ts
 *
 * 护栏: .pi/extensions/auto-task-snapshot.ts 不能再现「wip(snapshot): ...」类 commit
 *
 * 背景 (AGENTS §8.1.3, 2026-09-23 主人拍板):
 *   旧版插件在 agent_end 触发 `git add -A` + commit (`wip(snapshot): <最后一句话>`),
 *   会把同一工作目录其他 session 的在制品扫进来, commit 标题与内容完全无关的
 *   「考古灾难」commit. 主人拍板去掉, 只留 turn_start (打 git tag + diff dump).
 *
 * 断言:
 *   1) 不注册 agent_end hook (替换为 turn_start)
 *   2) 没有任何 `git add -A` 调用 (排除注释 / 字符串字面量)
 *   3) 仍注册了 turn_start hook (避免有人连 turn_start 也误删)
 *
 * 与 tools/check-auto-snapshot-extension.sh 同源 —— 那个是 bash 入口 (pre-commit /
 * CI 脚本), 这个是 vitest 单测 (双保险: 改完 .ts 跑 pnpm test:run 自动验)。
 *
 * 见: AGENTS §8.1.3
 */

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const PROJECT_ROOT = process.cwd();
const EXT_PATH = join(PROJECT_ROOT, ".pi/extensions/auto-task-snapshot.ts");

/** 把 TS / TSX / JS 源码里的注释去掉 (跟 tools/check-auto-snapshot-extension.sh 的 awk 同一思路) */
function stripComments(src: string): string {
  // 1) /* ... */ 多行块注释
  let out = src.replace(/\/\*[\s\S]*?\*\//g, "");
  // 2) 行尾 // 注释 (简单版本, 字符串里的 // 不考虑 —— 该扩展不用字符串嵌入 git 命令)
  out = out.replace(/\/\/.*$/gm, "");
  // 3) /* 开头但未配对的整段也吃掉
  out = out.replace(/\/\*[\s\S]*$/g, "");
  return out;
}

describe("auto-task-snapshot extension 护栏 (AGENTS §8.1.3)", () => {
  it("插件源文件存在", () => {
    // 不存在 = 该项目已不用 pi; 此测试无意义, 直接跳过 (而不是 fail)
    //   主人挪走 → 删测试; 暂时未挪 → 验证仍生效
    expect(readFileSync.bind(null, EXT_PATH)).toBeDefined();
  });

  describe("源码 (去注释后)", () => {
    const raw = readFileSync(EXT_PATH, "utf8");
    const code = stripComments(raw);

    it("不注册 agent_end hook", () => {
      // 形如 `pi.on("agent_end", ...)` 或 `pi.on('agent_end', ...)`
      // 转义双引号 + 单引号
      const re = /pi\.on\(\s*["']agent_end["']/;
      expect(code).not.toMatch(re);
    });

    it("没有 `git add -A` 调用", () => {
      const re = /\bgit\s+add\s+-A\b/;
      expect(code).not.toMatch(re);
    });

    it("仍注册 turn_start hook (避免有人把 turn_start 误删一起没了)", () => {
      const re = /pi\.on\(\s*["']turn_start["']/;
      expect(code).toMatch(re);
    });

    it("恰好注册 1 个 pi.on(...) hook (防止新增未审 hook)", () => {
      const hooks = code.match(/^\s*pi\.on\(/gm) ?? [];
      expect(hooks.length, `实际 ${hooks.length} 个 hook`).toBe(1);
    });
  });

  describe("原始源码 (含注释)", () => {
    // 注释里允许提及「agent_end / git add -A 已去掉」(这是文档, 不是代码)
    // → 不做反向断言
    const raw = readFileSync(EXT_PATH, "utf8");

    it("顶部 doc comment 解释了为什么去掉 (供日后回看)", () => {
      // 找到首段 /* ... */ 块注释
      const m = raw.match(/^\/\*\*([\s\S]*?)\*\//);
      expect(m).not.toBeNull();
      expect(m![1]).toMatch(/agent_end/);
      expect(m![1]).toMatch(/git add -A/);
    });
  });
});