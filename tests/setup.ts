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
// 库名不是 test 或 *_test 就直接抛错, 测试进程起不来, 轮不到 TRUNCATE 执行。
// ============================================
{
  const url = process.env.DATABASE_URL || "";
  let dbName = "";
  try {
    dbName = new URL(url).pathname.replace(/^\//, "");
  } catch {
    dbName = "";
  }
  if (!(dbName === "test" || dbName.endsWith("_test"))) {
    throw new Error(
      `[tests/setup] 拒绝对非测试库运行: "${dbName || url}"。\n` +
        "集成测试会 TRUNCATE 业务表, 绝不能指向 dev/prod。\n" +
        "正确用法: DATABASE_URL=postgres://nuankebao:<pwd>@localhost:5432/nuankebao_test pnpm test:run (见 README §测试)"
    );
  }
}
process.env.AUTH_SECRET = "test-secret-32chars-123456789012345";
process.env.PGCRYPTO_KEY = "0".repeat(64); // 32 bytes hex, 测试用
process.env.MINIMAX_API_KEY = ""; // 强制走 mock