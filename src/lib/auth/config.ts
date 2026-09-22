import type { NextAuthConfig } from "next-auth";
import { resolveSessionMaxAgeSeconds, SESSION_UPDATE_AGE_SECONDS } from "./session";

// ============================================
// Auth.js v5 配置 — **Edge 安全部分** (middleware 专用)
//
// 为什么拆 (2026-09-19 P2):
//   之前 middleware.ts 直接 import @/lib/auth, 而 Credentials.authorize 现在要查
//   DB / 校验 scrypt。DB 进 Edge bundle 会让全站 500 (2026-09-18 实测回滚过)。
//   标准拆法: 本文件只放 Edge 能跑的东西 (callbacks / pages / cookie 策略),
//   providers (含 DB) 在 src/lib/auth/index.ts 的 Node 侧注入。
// ============================================

// 会话有效期见 src/lib/auth/session.ts (唯一真相, ADR-0013):
//   maxAge 10 年 + 7 天滚动续期 → 常用设备长期记住登录 (主人 2026-09-20 要求)
export const authConfig = {
  trustHost: true,
  session: {
    strategy: "jwt",
    maxAge: resolveSessionMaxAgeSeconds(),
    updateAge: SESSION_UPDATE_AGE_SECONDS,
  },

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
        // 角色写进 JWT (2026-09-22, ADR-0015 实施步骤 0)
        //   在此之前 session 只塞了 id/phone → 下游 `session.user.role` 恒 undefined
        //   → 管理员被当 sales 过滤 (加盟列表直接空) / 「我的客户」无法接行级过滤。
        //   ⚠ 真相源仍是 DB: getRbacContext 每次查库取 role, 本字段只作兜底
        //   (老 token / user 行查不到); 提权降权立即生效, 不用重新登录。
        t.role = u.role;
      }
      return t;
    },

    async session({ session, token }) {
      if (session.user) {
        session.user.id = token.sub ?? "";
        (session.user as any).phone = (token as any).phone as string | undefined;
        (session.user as any).role = (token as any).role as string | undefined;
      }
      return session;
    },
  },
} satisfies NextAuthConfig;
