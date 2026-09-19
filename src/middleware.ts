import NextAuth from "next-auth";
import { authConfig } from "@/lib/auth/config";

// Edge 安全: middleware 只认 Edge 可跑的 auth 配置 (无 DB / scrypt)。
// 带 DB 的 Credentials provider 在 @/lib/auth (Node 侧) —— 不能 import 进来,
// 否则 postgres/drizzle 进 Edge bundle → 全站 500 (2026-09-18 实测)。
const { auth } = NextAuth(authConfig);

/**
 * W14 修: 中间件重定向 base 不用 nextUrl (dev server 下 origin 固定本机),
 * 改用环境变量 AUTH_URL (公网) / APP_URL / 兜底 localhost.
 * 这样主人从 https://nuankebao.tooyang.top 访问时, 未登录跳转也回公网,
 * 不会跳到 http://localhost:3003.
 *
 * W15 修: dev 模式下优先用请求 host (手机扫描 QR 走 LAN IP 时, 不要重定向
 * 到公网域名 — 手机达不到 nuankebao.tooyang.top).
 * 依据: NODE_ENV !== 'production' → dev; dev 模式默认用请求头里的 host.
 *
 * W16 新增: DEV_SKIP_AUTH=1 (dev 模式) → 跳过 admin auth 跳转, 手机扫码直接看 UI.
 * 双门闸: 必须 NODE_ENV !== 'production' && DEV_SKIP_AUTH === '1' 才生效.
 * 生产默认关闭 (生产 NODE_ENV=production → 短路, 即使变量误设也不生效).
 */
function getPublicBaseUrl(req: Request): string {
  const isDev = process.env.NODE_ENV !== "production";

  // dev 模式: 默认走请求头里的 host (QR 扫码手机能达)
  // 注: req.url 在 AUTH_TRUST_HOST=true 下会被 Auth.js 重写成公网域名,
  // 不能直接用 new URL(req.url).host. 必须用原始 Host 头.
  if (isDev) {
    const host = req.headers.get("host") || new URL(req.url).host;
    const proto = req.headers.get("x-forwarded-proto") || (host.includes("localhost") || host.startsWith("127.") || host.startsWith("192.168.") || host.startsWith("10.") ? "http" : "https");
    return `${proto}://${host}`;
  }

  // 生产: 1. 显式 AUTH_URL (公网域名)
  const authUrl = process.env.AUTH_URL;
  if (authUrl && !authUrl.includes("localhost") && !authUrl.includes("127.0.0.1")) {
    return authUrl;
  }
  // 2. APP_URL
  const appUrl = process.env.APP_URL;
  if (appUrl && !appUrl.includes("localhost") && !appUrl.includes("127.0.0.1")) {
    return appUrl;
  }
  // 3. 走代理头 (cloudflared / nginx 设了才用)
  const forwardedHost =
    req.headers.get("x-forwarded-host") || req.headers.get("x-forwarded-for");
  if (forwardedHost && !forwardedHost.includes("localhost") && !forwardedHost.includes("127.0.0.1")) {
    const proto = req.headers.get("x-forwarded-proto") || "https";
    const host = forwardedHost.split(",")[0].trim();
    if (!host.includes(":") || /^[a-z0-9-]+(\.[a-z0-9-]+)*$/.test(host)) {
      return `${proto}://${host}`;
    }
  }
  // 4. 兜底
  return "http://localhost:3003";
}

export default auth((req) => {
  const { nextUrl } = req;
  const isLoggedIn = !!req.auth;
  const base = getPublicBaseUrl(req as unknown as Request);

  // A6 (2026-09-19, docs/deploy/production-plan.md §3.A):
  // 生产环境关闭 dev 预览路由 (/app-preview /preview), dev 保留。
  // 注: middleware (Edge) 里 process.env 非 NEXT_PUBLIC_* 变量可能在构建期内联,
  //     要打开开关可能需重新 build; 默认不设 = 生产 404。
  const isAppPreviewPath =
    nextUrl.pathname === "/app-preview" ||
    nextUrl.pathname.startsWith("/app-preview/") ||
    nextUrl.pathname === "/preview" ||
    nextUrl.pathname.startsWith("/preview/");
  if (
    process.env.NODE_ENV === "production" &&
    process.env.APP_PREVIEW_ENABLED !== "1" &&
    isAppPreviewPath
  ) {
    return new Response("Not Found", { status: 404 });
  }

  // 双门闸: dev 模式 (NODE_ENV !== production) + 显式 opt-in 才跳过 auth
  // 2026-09-19 P2: 加 NODE_ENV 硬门闸 (之前只认变量值, 生产误设就裸奔)
  const devSkipAuth =
    process.env.NODE_ENV !== "production" && process.env.DEV_SKIP_AUTH === "1";

  const isOnAdmin = nextUrl.pathname.startsWith("/admin");
  const isOnLogin = nextUrl.pathname === "/login";

  // 未登录访问 /admin/* → 重定向到 /login (base 跟随 dev/prod)
  // DEV_SKIP_AUTH=1 时跳过 (dev 模式扫码直看 UI)
  if (isOnAdmin && !isLoggedIn && !devSkipAuth) {
    const url = new URL("/login", base);
    url.searchParams.set("callbackUrl", nextUrl.pathname);
    return Response.redirect(url);
  }

  // 已登录访问 /login → 重定向到 /admin (base 跟随 dev/prod)
  // devSkipAuth 下也跳过 (避免无 session 访 /login 被踢到 /admin 仍报错)
  if (isOnLogin && isLoggedIn && !devSkipAuth) {
    return Response.redirect(new URL("/admin", base));
  }
});

export const config = {
  // 匹配所有路径除了 api、_next 静态资源、图片、favicon
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};
