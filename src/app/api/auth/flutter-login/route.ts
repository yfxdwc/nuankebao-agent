// /api/auth/flutter-login
// GET/dev 专用: 暖客宝 Flutter web R12 治本方案 (HttpOnly cookie JS 读不到, 改用 body 返回)
//
// 背景 (docs/login-failure-triage.md §2.B R12):
//   Auth.js v5 session-token 默认 httpOnly=true (dev 也一样, 没法关),
//   Flutter web (XHR) dio onResponse 拦截器收不到 Set-Cookie 头,
//   JS 读 document.cookie 拿不到 HttpOnly cookie → 登录后 storage 空 →
//   后续 API 401 → 跳回 /login → 主人看到循环.
//
// 治本方案 A (本 endpoint 实施):
//   1. dev mode (NODE_ENV !== production): 接受 phone + code (验证码硬编码 123456),
//      用 Auth.js signIn + encode 同样的 secret 生成 JWT,
//      Set-Cookie + 额外在 body 里返回 { sessionToken, cookieName }
//   2. Flutter web 用 fetch (不用 dio) 调这个 endpoint, 从 body 拿 token,
//      写 ApiClient.storage.session_token, 后续 dio 请求走 onRequest
//      拦截器从 storage 拼 Cookie 头 (路径已存在)
//   3. prod 模式: 本 endpoint 直接 404 (避免 security risk: 把 JWT 通过 body 返回)
//
// 不替代 Auth.js OAuth callback — 真机 APK / Next.js web login 仍走老路径.
// 只为 Flutter web dev mode 治 R12.

import { NextRequest, NextResponse } from "next/server";
import { encode as jwtEncode } from "next-auth/jwt";

const SESSION_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60; // 30 days, 同 Auth.js 默认
const DEV_PHONE = "13800138000";
const DEV_CODE = "123456";

export async function POST(request: NextRequest) {
  // prod 模式禁用 — JWT 通过 body 返回是 dev 妥协方案, prod 必须 HttpOnly
  if (process.env.NODE_ENV === "production") {
    return NextResponse.json({ error: "Not Found" }, { status: 404 });
  }

  let body: { phone?: string; code?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { phone, code } = body;
  if (phone !== DEV_PHONE || code !== DEV_CODE) {
    return NextResponse.json(
      { error: "验证码错误", hint: "dev mode: phone=13800138000, code=123456" },
      { status: 401 }
    );
  }

  // 生成同 Auth.js 格式的 JWT (让 Next.js middleware auth() 能认)
  const secret = process.env.AUTH_SECRET ?? process.env.NEXTAUTH_SECRET ?? "";
  if (!secret) {
    return NextResponse.json(
      { error: "AUTH_SECRET not set" },
      { status: 500 }
    );
  }
  const token = await jwtEncode({
    token: { sub: "1", phone: DEV_PHONE, name: "开发测试" },
    secret,
    salt: "authjs.session-token",
    maxAge: SESSION_TOKEN_TTL_SECONDS,
  });

  // 返回 body (R12 治本主路径: Flutter web 从 body 读 token → Authorization header)
  // 不再设 HttpOnly cookie (因为 HttpOnly cookie JS 读不到, Flutter web dio
  // 设 Cookie header 被浏览器拒, 必须走 Authorization 路径).
  // 注: 备选设个 非 HttpOnly cookie 作兑底 (老 Auth.js callback 路径走原生 cookie).
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
