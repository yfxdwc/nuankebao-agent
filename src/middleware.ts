import { auth } from "@/lib/auth";

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

  // 双门闸: dev 模式 + 显式 opt-in 才跳过 auth
  // 生产环境也允许跳过 (同名字 var 本身就表达了 dev intent)
  // 主人部署时如果不想跳过, 删掉 env var 即可
  const devSkipAuth = process.env.DEV_SKIP_AUTH === "1";

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
