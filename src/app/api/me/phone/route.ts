// ============================================
// PATCH /api/me/phone — 自助修改手机号
// ============================================
// 背景 (CHARTER §3.6 + §6.6):
//   用户能自己改手机号 — 替代原来"换号要找管理员"的提示。
//
// 边界:
//   - 需要登录 (dev 空 session 时也要求登录)
//   - 必须验证当前密码 (防偷设备改号)
//   - 新手机号格式: 中国大陆 11 位 /^1[3-9]\d{9}$/ (跟注册一致)
//   - 新手机号不能与现有 user 的 phoneHash 冲突 → 409
//   - 同手机号 customer 档案同步改 (CHARTER §6.6: user ↔ customer 约定用手机号 hash 关联,
//     改号后两边都要跟上)
//   - 改号走审计 (user 表已挂 user_audit 触发器; withAuditContext 记录操作人/IP)
//   - 不强制重新登录 — 跟改密码一致; session.user.phone 是 jwt 里首次登录时的快照,
//     改完提示"下次登录用新手机号"即可
//
// 已知限制 (MVP 接受):
//   - 同手机号 customer 档案可能有多个 (历史原因 / 多账号同手机号?)
//     → 全部一起改 (同一 phoneHash 命中), 符合"同号 = 同人"约定
//   - customer 软删记录 (deleted_at != null) 也一起改 — 改号前已是 deleted,
//     改完还是 deleted (兜底一致即可)

import { NextRequest, NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { verifyPassword } from "@/lib/auth/password";
import { withAuditContext, getAuditContextFromRequest } from "@/lib/audit/context";
import { db } from "@/lib/db";
import { customer, user as userTable } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import { rateLimit, RateLimits, rateLimitResponse } from "@/lib/rate-limit";
import { maskPhone } from "@/lib/utils";

export const dynamic = "force-dynamic";

const PHONE_REGEX = /^1[3-9]\d{9}$/;

const bodySchema = z
  .object({
    password: z.string().min(1, "请输入当前密码"),
    newPhone: z.string().regex(PHONE_REGEX, "手机号格式不对"),
  })
  .strict();

export async function PATCH(request: NextRequest) {
  const session = await auth();
  const rawUserId = session?.user?.id ?? "";
  if (!/^\d+$/.test(rawUserId)) {
    return NextResponse.json({ error: "未登录" }, { status: 401 });
  }
  const userId = BigInt(rawUserId);

  // 防爆破: 每用户 5 次/分钟 (跟改密码同档)
  const limit = rateLimit(`me:phone:${userId.toString()}`, RateLimits.login);
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
  const { password, newPhone } = parsed.data;

  // ---- 读账号 (一次性) ----
  const [row] = await db
    .select({
      phoneHash: userTable.phoneHash,
      passwordHash: userTable.passwordHash,
      isActive: userTable.isActive,
    })
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
      { error: "当前账号未设置密码, 请联系管理员重置密码后再改手机号" },
      { status: 400 }
    );
  }
  if (!verifyPassword(password, row.passwordHash)) {
    return NextResponse.json({ error: "当前密码不正确" }, { status: 401 });
  }

  const newPhoneHash = hashForLookup(newPhone);
  if (newPhoneHash === row.phoneHash) {
    return NextResponse.json(
      { error: "新手机号不能与当前手机号相同" },
      { status: 400 }
    );
  }

  // ---- 事务: user + 同号 customer 档案同步改 ----
  const ctx = getAuditContextFromRequest(request, session);

  try {
    await withAuditContext(ctx, async (tx) => {
      // 1. 唯一性检查: 新手机号已被其他 user 占用 → 抛错回滚
      const [dupe] = await tx
        .select({ id: userTable.id })
        .from(userTable)
        .where(and(eq(userTable.phoneHash, newPhoneHash), eq(userTable.isActive, true)))
        .limit(1);
      if (dupe) {
        const err = new Error("新手机号已被其他账号使用");
        (err as Error & { statusCode?: number }).statusCode = 409;
        throw err;
      }

      // 2. 改 user
      await tx
        .update(userTable)
        .set({
          phoneEncrypted: encryptField(newPhone),
          phoneHash: newPhoneHash,
          updatedAt: new Date(),
        })
        .where(eq(userTable.id, userId));

      // 3. 同手机号 customer 档案同步改 (CHARTER §6.6)
      //    注: 不限 isNull(deletedAt) — 软删的也一起改, 改完还是软删 (兜底一致)
      await tx
        .update(customer)
        .set({
          phoneEncrypted: encryptField(newPhone),
          phoneHash: newPhoneHash,
          updatedAt: new Date(),
        })
        .where(eq(customer.phoneHash, row.phoneHash));
    });
  } catch (e) {
    const err = e as Error & { statusCode?: number };
    if (err.statusCode === 409) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    throw e;
  }

  return NextResponse.json({
    ok: true,
    phone: { full: newPhone, masked: maskPhone(newPhone) },
  });
}
