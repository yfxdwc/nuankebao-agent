// /api/auth/flutter-login
// dev 专用: Flutter web R12 治本方案 (HttpOnly cookie JS 读不到, 改用 body 返回)
//
// 背景 (docs/login-failure-triage.md §2.B R12):
//   Auth.js v5 session-token 默认 httpOnly=true (dev 也一样, 没法关),
//   Flutter web (XHR) dio onResponse 拦截器收不到 Set-Cookie 头,
//   JS 读 document.cookie 拿不到 HttpOnly cookie → 登录后 storage 空 →
//   后续 API 401 → 跳回 /login → 主人看到循环.
//
// 治本方案 A (本 endpoint 实施):
//   1. dev mode (NODE_ENV !== production): 接受 账号/手机号 + 密码,
//      用 Auth.js 同样的 secret 生成 JWT, Set-Cookie + body 返回 { sessionToken, cookieName }
//   2. Flutter web 用 dio 调这个 endpoint, 从 body 拿 token,
//      写 ApiClient.storage.session_token, 后续请求走 onRequest 拦截器拼 Cookie
//   3. prod 模式: 本 endpoint 直接 404 (安全: 不允许 JWT 走 body 返回)
//
// 2026-09-19 P2 变更 (账号密码登录):
//   - 主路径: identifier (username/手机号) + password → verifyCredentials (真实 scrypt 校验)
//   - 兼容路径 (仅 dev):
//     a. `code=123456` + DEV_LOGIN_ANY_USER=1 → 旧预览 bundle 免密切号 (deprecated)
//     b. DEV_LOGIN_ANY_PASSWORD (env) + DEV_LOGIN_ANY_USER=1 → 多账号预览免真实密码切号
//   - 生产环境以上全部失效 (404 + NODE_ENV 门闸)

import { NextRequest, NextResponse } from "next/server";
import { encode as jwtEncode } from "next-auth/jwt";
import {
  findActiveUserByIdentifier,
  verifyCredentials,
} from "@/lib/auth/credentials";
import { resolveSessionMaxAgeSeconds } from "@/lib/auth/session";

// 跟 Auth.js 侧同一个源 (src/lib/auth/session.ts):
//   10 年 + 7 天滚动续期 (主人 2026-09-20: 同设备长期记住登录, 不限时长)
//   以前两边各写 30 天 → 到期后冷启动被判未登录, 用户又要重新登录
const SESSION_TOKEN_TTL_SECONDS = resolveSessionMaxAgeSeconds();
const LEGACY_DEV_CODE = "123456";

export async function POST(request: NextRequest) {
  // prod 模式禁用 — JWT 通过 body 返回是 dev 妥协方案, prod 必须 HttpOnly
  if (process.env.NODE_ENV === "production") {
    return NextResponse.json({ error: "Not Found" }, { status: 404 });
  }

  let body: {
    identifier?: string;
    phone?: string;
    password?: string;
    code?: string;
  };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const identifier = (body.identifier ?? body.phone ?? "").trim();
  const password = typeof body.password === "string" ? body.password : "";
  const legacyCode = typeof body.code === "string" ? body.code : "";

  if (!identifier) {
    return NextResponse.json({ error: "请输入账号或手机号" }, { status: 400 });
  }

  const anyUser = process.env.DEV_LOGIN_ANY_USER === "1";

  let sub: string | null = null;
  let displayName = "";
  // 2026-09-22 (ADR-0015 步骤 0): session 补 role/phone
  //   之前 token 只有 { sub, name } → 下游 session.user.role 恒 undefined
  //   → 管理员被当 sales 过滤。phone 仅作展示兜底 (查 phone_hash 都走 DB)。
  let phone: string | undefined;
  let role: string | undefined;

  if (anyUser && legacyCode) {
    // 兼容旧预览 bundle (密码框上线前的前端): 码 123456 + 免密切号
    if (legacyCode !== LEGACY_DEV_CODE) {
      return NextResponse.json(
        { error: "验证码错误", hint: "dev mode: code=123456" },
        { status: 401 }
      );
    }
    const row = await findActiveUserByIdentifier(identifier);
    if (!row) {
      return NextResponse.json(
        { error: "该账号/手机号没有对应用户", hint: "DEV_LOGIN_ANY_USER=1 也要求用户已存在" },
        { status: 401 }
      );
    }
    sub = row.id.toString();
    displayName = row.name;
    role = row.role;
  } else if (anyUser && process.env.DEV_LOGIN_ANY_PASSWORD && password === process.env.DEV_LOGIN_ANY_PASSWORD) {
    // 多账号预览: 共享 dev 密码切任意已存在用户 (仅 dev; 生产 404)
    const row = await findActiveUserByIdentifier(identifier);
    if (!row) {
      return NextResponse.json(
        { error: "该账号/手机号没有对应用户", hint: "DEV_LOGIN_ANY_USER=1 也要求用户已存在" },
        { status: 401 }
      );
    }
    sub = row.id.toString();
    displayName = row.name;
    role = row.role;
  } else {
    // 主路径: 真实账号 + 密码校验 (含限流)
    const u = await verifyCredentials(identifier, password);
    if (!u) {
      return NextResponse.json(
        { error: "账号或密码错误, 或尝试过于频繁" },
        { status: 401 }
      );
    }
    sub = u.id;
    displayName = u.name;
    phone = u.phone;
    role = u.role;
  }

  // 生成同 Auth.js 格式的 JWT (让 Next.js middleware auth() 能认)
  const secret = process.env.AUTH_SECRET ?? process.env.NEXTAUTH_SECRET ?? "";
  if (!secret) {
    return NextResponse.json({ error: "AUTH_SECRET not set" }, { status: 500 });
  }
  const token = await jwtEncode({
    token: { sub, name: displayName, phone, role },
    secret,
    salt: "authjs.session-token",
    maxAge: SESSION_TOKEN_TTL_SECONDS,
  });

  // 返回 body (R12 治本主路径: Flutter web 从 body 读 token)
  // 不再设 HttpOnly cookie (Flutter web dio 读不到; 走 Authorization/Cookie 手动路径).
  const response = NextResponse.json(
    {
      sessionToken: token,
      cookieName: "authjs.session-token",
      expiresIn: SESSION_TOKEN_TTL_SECONDS,
    },
    { status: 200 }
  );
  // 非 HttpOnly, sameSite=lax (dev 专用 path, 不影响生产 HTTPS 路径)
  response.cookies.set("authjs.session-token", token, {
    httpOnly: false,
    path: "/",
    sameSite: "lax",
    maxAge: SESSION_TOKEN_TTL_SECONDS,
  });
  return response;
}
