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
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  getInteractionById,
  updateInteraction,
  deleteInteraction,
} from "@/lib/db/queries/interaction";
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

  const ctx = getAuditContextFromRequest(request, session);
  const success = await deleteInteraction(BigInt(id), ctx);

  if (!success) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ success: true });
}