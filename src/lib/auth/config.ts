import type { NextAuthConfig } from "next-auth";

// ============================================
// Auth.js v5 配置 — **Edge 安全部分** (middleware 专用)
//
// 为什么拆 (2026-09-19 P2):
//   之前 middleware.ts 直接 import @/lib/auth, 而 Credentials.authorize 现在要查
//   DB / 校验 scrypt。DB 进 Edge bundle 会让全站 500 (2026-09-18 实测回滚过)。
//   标准拆法: 本文件只放 Edge 能跑的东西 (callbacks / pages / cookie 策略),
//   providers (含 DB) 在 src/lib/auth/index.ts 的 Node 侧注入。
// ============================================

export const authConfig = {
  trustHost: true,
  session: { strategy: "jwt" },

  // dev mode (NODE_ENV !== production) → 不发 Secure cookie.
  // 根因: .env AUTH_URL=https://nuankebao.tooyang.top → Auth.js 自动用 Secure cookie
  // (url.protocol === "https:" 判定), 但 dev server 跑在 http://localhost:3003.
  // Chrome 因 Secure 标志 + http 拒绝存 cookie → 302 后 document.cookie="" → 下一次请求
  // 401 → 跳回 /login → 登录循环 (w14 第三次复发修复遗留说明)。
  useSecureCookies: process.env.NODE_ENV === "production",

  // ⚠️ 故意留空: Credentials (含 DB 查询) 只在 Node 侧 (src/lib/auth/index.ts) 注入
  providers: [],

  pages: {
    signIn: "/login",
  },

  callbacks: {
    // dev mode 把 callbackUrl 强制相对化 (去 host).
    // 根因 (第四次修, 跟 w14 / 87334c3 / 1369ac4 / useSecureCookies 错开):
    //   Auth.js 默认 callbackUrl=/ 会被转成 AUTH_URL + '/' = https://nuankebao.tooyang.top/
    //   dio 在 web 平台 xhr.open + xhr.send 不传 manual, 浏览器自动跟随 302
    //   → 跨源 (localhost:3003 → nuankebao.tooyang.top) → ACAO 缺失 → XHR onError
    //   → dio 抛 connectionError (虽然 cookie 实际存了, 拦截器已收 session-token)
    //   修复: callbackUrl 是相对路径就保留; 是绝对 URL 砍掉 host 只留 path+query
    //   生产 (NODE_ENV=production) 保留 Auth.js 默认 (跟 AUTH_URL 走, HTTPS OK)
    async redirect({ url, baseUrl }) {
      if (process.env.NODE_ENV !== "production") {
        if (url.startsWith("/")) return url;
        try {
          const u = new URL(url);
          return u.pathname + u.search + u.hash;
        } catch {
          return "/";
        }
      }
      if (url.startsWith(baseUrl)) return url;
      if (url.startsWith("/")) return `${baseUrl}${url}`;
      return baseUrl;
    },

    async jwt({ token, user }) {
      const t = token as any;
      const u = user as any;
      if (u) {
        t.phone = u.phone;
      }
      return t;
    },

    async session({ session, token }) {
      if (session.user) {
        session.user.id = token.sub ?? "";
        (session.user as any).phone = (token as any).phone as string | undefined;
      }
      return session;
    },
  },
} satisfies NextAuthConfig;
