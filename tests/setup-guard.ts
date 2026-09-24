// ============================================
// 测试库 fail-closed 护栏 (2026-09-24 立, 2026-09-26 抽纯函数)
//
// 起因 (真实事故): 另一个 session 的 subagent 把 DATABASE_URL 直指 dev 库
// (/nuankebao, 不是 _test) 跑了 `pnpm test:run` 全量测试 → integration/knowledge
// 的 `TRUNCATE customer, follow_up_task, interaction, wellness_record CASCADE`
// 把 dev 的客户/互动/养生/跟进清空 (已从当天 03:01 备份恢复)。
//
// 治本口径 (AGENTS §5「贴告示 ≠ 修复」): 让"打错库"物理上不可能 ——
// 库名不是 test 或 *_test 就直接抛错, 测试进程起不来, 轮不到 TRUNCATE 执行。
//
// 口径 (2026-09-26 收紧):
//   - 显式正则 `^(test|[a-z][a-z0-9_]*_test)$` 取代 `endsWith('_test')` (防 「prod_test」 /「_test」纯下划线绕过)
//   - 抽成纯函数 `assertTestDatabase(url)`, tests/setup.ts 调它; 单测覆盖
// ============================================

/**
 * 判定一个 DATABASE_URL 是否指向测试库; 不是就抛错。
 *
 * @param url  DATABASE_URL 字符串 (postgres://user:pwd@host:port/dbname)
 * @throws Error  当库名不是 `test` 或匹配 `[a-z][a-z0-9_]*_test` 时
 */
export function assertTestDatabase(url: string): void {
  const dbName = parseDbName(url);
  if (!isTestDbName(dbName)) {
    throw new Error(
      `[tests/setup] 拒绝对非测试库运行: "${dbName || url}"。\n` +
        "集成测试会 TRUNCATE 业务表, 绝不能指向 dev/prod。\n" +
        "正确用法: DATABASE_URL=postgres://nuankebao:<pwd>@localhost:5432/nuankebao_test pnpm test:run (见 README §测试)"
    );
  }
}

/**
 * 纯函数: 库名是否符合测试库约定。
 *   - "test"
 *   - 形如 `<name>_test`, 其中 <name> 以小写字母开头, 后跟小写字母/数字/下划线
 *
 * 故意收紧 (reviewer 要求):
 *   - 不接受 `/nuankebao`、`/production`、`/dev_test_data` (后缀 _test_data 不是 _test)
 *   - 不接受空字符串 / 仅下划线 `_test` (不以字母开头)
 */
export function isTestDbName(dbName: string): boolean {
  if (!dbName) return false;
  return /^(test|[a-z][a-z0-9_]*_test)$/.test(dbName);
}

/**
 * 从 URL 字符串解出库名 (pathname 去前缀 `/`)。URL 解析失败返回空串。
 */
export function parseDbName(url: string): string {
  if (!url) return "";
  try {
    return new URL(url).pathname.replace(/^\//, "");
  } catch {
    return "";
  }
}