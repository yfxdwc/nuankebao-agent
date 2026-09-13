/**
 * 暖客宝 dev 模式 auth 跳过 helper
 *
 * 与 src/middleware.ts 的 DEV_SKIP_AUTH 逻辑对齐:
 *   - DEV_SKIP_AUTH === '1' → 跳过 auth (任何 NODE_ENV)
 *   - 默认关闭
 *
 * API route 用法:
 *   if (!isAuthSkipped() && !session?.user?.id) return 401;
 *
 * 原因: middleware 只处理页面重定向, API 路由有自己的 auth() 检查.
 * dev 模式手机扫码直看 UI, 但调 API 也会撞 401, 需要这里也放行.
 *
 * 注: NODE_ENV 检查移除 — 生产环境下主人如果不跳过 auth, 直接 unset 环境变量即可,
 * 安全语义靠 "var 是否设置" 而不是 "dev/prod 区分".
 */
export function isAuthSkipped(): boolean {
  return process.env.DEV_SKIP_AUTH === "1";
}
