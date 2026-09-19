// ============================================
// PATCH /api/me/password — 自助修改密码
// ============================================
// 背景 (docs/deploy/production-plan.md §3.B9):
//   账号密码登录上线后, 用户需要能自己改密码 (管理员发初始密码 → 首登后改).
//
// 边界:
//   - 需要登录 (dev DEV_SKIP_AUTH 无 session 时也要求登录, 改密必须有明确身份)
//   - 必须验证旧密码 (防偷设备改密)
//   - 新密码强度: ≥8 位 + 字母 + 数字 (src/lib/auth/password.ts)
//   - 改密走审计 (user 表有 user_audit 触发器; withAuditContext 记录操作人/IP)
//
// 已知限制 (MVP 接受):
//   JWT session 策略下, 改密不会使旧 token 立即失效 (最长 30 天).
//   后续可加 password_changed_at + session 回调校验 (Phase 2 安全加固).
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import {
  hashPassword,
  isValidPassword,
  PASSWORD_POLICY_MESSAGE,
  verifyPassword,
} from "@/lib/auth/password";
import { withAuditContext, getAuditContextFromRequest } from "@/lib/audit/context";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { rateLimit, RateLimits, rateLimitResponse } from "@/lib/rate-limit";

export const dynamic = "force-dynamic";

const bodySchema = z
  .object({
    oldPassword: z.string().min(1, "请输入当前密码"),
    newPassword: z.string().min(1, "请输入新密码"),
  })
  .strict();

export async function PATCH(request: NextRequest) {
  const session = await auth();
  const rawUserId = session?.user?.id ?? "";
  if (!/^\d+$/.test(rawUserId)) {
    return NextResponse.json({ error: "未登录" }, { status: 401 });
  }
  const userId = BigInt(rawUserId);

  // 防爆破: 每用户 5 次/分钟
  const limit = rateLimit(`me:password:${userId.toString()}`, RateLimits.login);
  if (!limit.allowed) return rateLimitResponse(limit);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "请求体不是合法 JSON" }, { status: 400 });
  }

  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? "参数错误" },
      { status: 400 }
    );
  }
  const { oldPassword, newPassword } = parsed.data;

  if (!isValidPassword(newPassword)) {
    return NextResponse.json({ error: PASSWORD_POLICY_MESSAGE }, { status: 400 });
  }
  if (newPassword === oldPassword) {
    return NextResponse.json({ error: "新密码不能与当前密码相同" }, { status: 400 });
  }

  const [row] = await db
    .select({ passwordHash: userTable.passwordHash, isActive: userTable.isActive })
    .from(userTable)
    .where(eq(userTable.id, userId))
    .limit(1);

  if (!row) {
    return NextResponse.json({ error: "账号不存在" }, { status: 404 });
  }
  if (!row.isActive) {
    return NextResponse.json({ error: "账号已停用" }, { status: 403 });
  }
  if (!row.passwordHash) {
    return NextResponse.json(
      { error: "当前账号未设置密码, 请联系管理员重置" },
      { status: 400 }
    );
  }
  if (!verifyPassword(oldPassword, row.passwordHash)) {
    return NextResponse.json({ error: "当前密码不正确" }, { status: 401 });
  }

  const newHash = hashPassword(newPassword);
  const ctx = getAuditContextFromRequest(request, session);

  await withAuditContext(ctx, async (tx) => {
    await tx
      .update(userTable)
      .set({ passwordHash: newHash, updatedAt: new Date() })
      .where(eq(userTable.id, userId));
  });

  return NextResponse.json({ ok: true });
}
