import NextAuth from "next-auth";
import Credentials from "next-auth/providers/credentials";
import { authConfig } from "./config";
import { verifyCredentials } from "./credentials";

// ============================================
// Auth.js v5 配置 — **Node 侧** (Route Handlers / 业务代码用)
//
// 登录方式 (2026-09-19 P2, 邀请制 — 不开放自助注册):
//   - identifier: 登录名 (如 admin) 或 手机号
//   - password:   scrypt 校验 (src/lib/auth/credentials.ts)
//
// ⚠️ 结构 (不能合并回单文件):
//   - ./config.ts  = Edge 安全部分 (middleware 引用; 无 DB)
//   - 本文件        = 带 DB 的 Credentials provider (仅 Node 运行时)
//   2026-09-18 实测: DB 进 Edge middleware bundle → 全站 500。
// ============================================

export const { handlers, auth, signIn, signOut } = NextAuth({
  ...authConfig,
  providers: [
    Credentials({
      name: "credentials",
      credentials: {
        identifier: { label: "账号 / 手机号", type: "text" },
        password: { label: "密码", type: "password" },
      },
      async authorize(credentials) {
        const identifier =
          typeof credentials?.identifier === "string" ? credentials.identifier : "";
        const password =
          typeof credentials?.password === "string" ? credentials.password : "";

        const u = await verifyCredentials(identifier, password);
        if (!u) return null;

        // role 一并带出 (2026-09-22 ADR-0015 步骤 0): config.ts 的 jwt callback
        //   会把它写进 token → session.user.role 可用 (老版只带 id/name/phone)。
        return {
          id: u.id,
          name: u.name,
          phone: u.phone,
          role: u.role,
        } as { id: string; name: string; phone?: string; role?: string };
      },
    }),
  ],
});
