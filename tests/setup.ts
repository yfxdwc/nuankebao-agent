// 全局测试 setup
// - 设置环境变量
// - mock dotenv / fs 等

// process.env.NODE_ENV 默认就是 "test" (vitest 跑时)
process.env.DATABASE_URL = process.env.DATABASE_URL || "postgres://test:test@localhost:5432/test";

// ============================================
// ⛔ 非测试库 fail-closed 护栏 (2026-09-24)
//
// 起因 (真实事故): 另一个 session 的 subagent 把 DATABASE_URL 直指 dev 库
// (/nuankebao, 不是 _test) 跑了 `pnpm test:run` 全量测试 → integration/knowledge
// 的 `TRUNCATE customer, follow_up_task, interaction, wellness_record CASCADE`
// 把 dev 的客户/互动/养生/跟进清空 (已从当天 03:01 备份恢复)。
//
// 治本口径 (AGENTS §5「贴告示 ≠ 修复」): 让"打错库"物理上不可能 ——
// 库名不是 test 或匹配 `[a-z][a-z0-9_]*_test` 就直接抛错, 测试进程起不来,
// 轮不到 TRUNCATE 执行。
//
// 2026-09-26 reviewer 拍: 收紧 `endsWith('_test')` → 显式正则 (防 「prod_test」/「_test」 绕过),
// 抽成纯函数 assertTestDatabase(url) 供 setup.ts / 外部 / 单测复用 (见 tests/setup-guard.ts)
// ============================================
import { assertTestDatabase } from "./setup-guard";
assertTestDatabase(process.env.DATABASE_URL || "");

process.env.AUTH_SECRET = "test-secret-32chars-123456789012345";
process.env.PGCRYPTO_KEY = "0".repeat(64); // 32 bytes hex, 测试用
process.env.MINIMAX_API_KEY = ""; // 强制走 mock