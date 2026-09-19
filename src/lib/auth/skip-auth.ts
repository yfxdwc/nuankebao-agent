/**
 * 暖客宝 dev 模式 auth 跳过 helper
 *
 * 与 src/middleware.ts 的 DEV_SKIP_AUTH 逻辑对齐:
 *   - NODE_ENV !== production 且 DEV_SKIP_AUTH === '1' → 跳过 auth
 *   - 默认关闭
 *
 * API route 用法:
 *   if (!isAuthSkipped() && !session?.user?.id) return 401;
 *
 * 2026-09-19 P2 (生产安全, production-plan §3.B10):
 *   之前只认变量值 ("设了就跳过, 生产也跳") —— 生产 .env 误写 DEV_SKIP_AUTH=1
 *   即全站裸奔。现在加 NODE_ENV 硬门闸, 生产环境下该变量无论怎么设都无效。
 */
export function isAuthSkipped(): boolean {
  if (process.env.NODE_ENV === "production") return false;
  return process.env.DEV_SKIP_AUTH === "1";
}
