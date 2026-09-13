import NextAuth from "next-auth";
import Credentials from "next-auth/providers/credentials";

// ============================================
// W1 占位 Auth.js v5 配置
//
// W1 验收: 任何手机号 + 验证码 123456 都能登录 (开发期 mock)
// W2/W3 完整接入:
//   - 阿里云 SMS 网关发送验证码
//   - Drizzle adapter 查询 user 表
//   - 真实短信验证 + 限流
//   - 字段加密 (mobile 用 phone_hash 查, 解密后比对面板)
// ============================================

export const { handlers, auth, signIn, signOut } = NextAuth({
  trustHost: true,
  session: { strategy: "jwt" },
  // dev mode (NODE_ENV !== production) → 不发 Secure cookie.
  // 根因: .env AUTH_URL=https://nuankebao.tooyang.top → Auth.js 自动用 Secure cookie
  // (url.protocol === "https:" 判定), 但 dev server 跑在 http://localhost:3003.
  // Chrome 因 Secure 标志 + http 拒绝存 cookie → 302 后 document.cookie="" → 下一次请求
  // 401 → router 判未登录跳回 /login → 主人看到 "输验证码 → 回到手机号".
  // 之前 curl 验证漏了 (curl 不验 Secure 标志).
  // (commit 2026-09-11 第三次修, 跟 w14 / 87334c3 / 1369ac4 错开)
  useSecureCookies: process.env.NODE_ENV === "production",
  providers: [
    Credentials({
      name: "credentials",
      credentials: {
        phone: { label: "手机号", type: "tel" },
        code: { label: "验证码", type: "text" },
      },
      async authorize(credentials) {
        // W1 开发期: 验证码硬编码 123456
        // W3 替换为真实阿里云 SMS 校验
        if (
          credentials?.code === "123456" &&
          typeof credentials?.phone === "string" &&
          credentials.phone.length === 11
        ) {
          return {
            id: "1",
            name: "开发测试",
            phone: credentials.phone,
          };
        }
        return null;
      },
    }),
  ],
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
    //   → dev 浏览器跟随到同源 / → Next.js redirect 到 /admin → middleware → 200
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
});