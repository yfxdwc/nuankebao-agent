// ============================================
// 互动记录详情 / 修正 / 删除 (联系人记录 Tab 用)
//
// ⚠ 权限口径 (与 POST /api/interactions 不同):
//   features.ts 写的是「GET 允许看历史, POST 需会员」(CRM_INTERACTION)
//   PATCH / DELETE **故意**不挂 featureGuard ——
//   理由: 销售员自己记错了一条互动, 会员过期后**应仍能修正 / 删除自己的错记**,
//   否则数据被锁死 = 比功能不能新建更糟 (客户列表持续涨, 错记永远错下去)。
//   后续若要收紧 (例如限制只有 N 天内的记录可改), 加在此处, 不外推到 POST。
//
// 结构镜像 src/app/api/wellness-records/[id]/route.ts: auth + isAuthSkipped + zod +
//   getAuditContextFromRequest + 400/404/500 分支; params 是 Promise<{id:string}>。
//
// 🔒 IDOR 修复 (R-12 同源, 2026-09-25, 见 docs/customer-idor-audit.md §2):
//   之前 GET/PATCH/DELETE 全部直接 `getInteractionById(BigInt(id))`, 任何登录者都
//   可读 / 改 / 删全表互动记录 (interaction 没有 ACL, 挂的是 customer_id)。
//   修法 (跟 wellness-records/[id] 同口径): 先读出记录的 customerId, 再对
//   `customer.id` 做 `customerRbacFilter` 行级过滤 — 命中不到 → **404** (不泄漏
//   存在性, 不外推到 403)。customerId 拿不到 (记录不存在) 也 → 404 (同样的存在性
//   防御)。
// ============================================

import { NextRequest, NextResponse } from "next/server";
import type { Session } from "next-auth";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  getInteractionById,
  updateInteraction,
  deleteInteraction,
} from "@/lib/db/queries/interaction";
import { getCustomerById } from "@/lib/db/queries/customer";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const UpdateSchema = z
  .object({
    type: z
      .enum(["phone", "wechat", "visit", "holiday_greeting", "other"])
      .optional(),
    summary: z.string().max(2000).optional(),
    followUpAt: z.string().datetime().nullable().optional(),
  })
  // 至少给一个字段 (空 body 无意义 → 早 400 比沉默"啥也没改"清晰)
  .refine(
    (v) =>
      v.type !== undefined ||
      v.summary !== undefined ||
      v.followUpAt !== undefined,
    { message: "至少需要提供一个字段" }
  );

/**
 * IDOR 闸门: 「这条互动所在的客户必须在 viewer 可见范围内」。
 *   命中不到 (记录不存在 OR 不在范围) 一律 404 — 不区分两者, 不暴露存在性。
 *
 * 为什么不改 query 函数签名加 scope:
 *   `getInteractionById` 也被别处间接复用 (e.g. follow-up 分析), 改签名会牵动
 *   既有调用点; route 层是 IDOR 暴露面, 把闸门装在 route 即可, 内部仍复用原函数。
 */
async function guardInteractionScope(
  interactionId: bigint,
  session: Session | null
): Promise<{ ok: true } | { ok: false; res: NextResponse }> {
  const item = await getInteractionById(interactionId);
  if (!item) {
    return { ok: false, res: NextResponse.json({ error: "Not found" }, { status: 404 }) };
  }
  const rbacCtx = await getRbacContextForSession(session);
  const visible = await getCustomerById(BigInt(item.customerId), {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
  });
  if (!visible) {
    return { ok: false, res: NextResponse.json({ error: "Not found" }, { status: 404 }) };
  }
  return { ok: true };
}

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  const guard = await guardInteractionScope(BigInt(id), session);
  if (!guard.ok) return guard.res;

  const item = await getInteractionById(BigInt(id));
  if (!item) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(item);
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  // 先 scope check — 命中不到就连 UPDATE 都不发, 避免 race 内还改到
  const guard = await guardInteractionScope(BigInt(id), session);
  if (!guard.ok) return guard.res;

  try {
    const body = await request.json();
    const input = UpdateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const item = await updateInteraction(BigInt(id), input, ctx);

    if (!item) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    return NextResponse.json(item);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Invalid input", details: error.errors },
        { status: 400 }
      );
    }
    console.error("[PATCH /api/interactions/[id]]", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  const guard = await guardInteractionScope(BigInt(id), session);
  if (!guard.ok) return guard.res;

  const ctx = getAuditContextFromRequest(request, session);
  const success = await deleteInteraction(BigInt(id), ctx);

  if (!success) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ success: true });
}