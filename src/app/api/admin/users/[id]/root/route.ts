// POST /api/admin/users/[id]/root — 建根 (Bootstrap Root)
//   主人 2026-09-21 拍: 「建根 = 先有账号, admin 能建根, 但要用户先注册」
//
// 为什么单独一个接口, 不塞进 /api/franchisees/placement-requests:
//   三方确认 = 设置者 + 新加盟商 + **父节点**; 根没有父节点 → 三方确认天然盖不到,
//   硬塞会给状态机开一条「零确认即执行」的分支 (最容易在后续改动里被滥用的特例)。
//   所以建根走 admin 专用入口 + 守卫 + 审计; 根一旦存在, 后续节点照旧三方确认。
//
// 权限: role=admin (服务端查库); 目标必须是**已注册**账号 (§6.6 建号入口只有注册)

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { createRootForUser } from "@/lib/db/queries/admin-users";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const BodySchema = z.object({
  /** 建根原因 (必填, 审计留痕) */
  note: z.string().min(2).max(200),
});

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  const [actor] = await db
    .select({ role: userTable.role })
    .from(userTable)
    .where(eq(userTable.id, BigInt(session.user.id)))
    .limit(1);
  if (actor?.role !== "admin") {
    return NextResponse.json(
      { error: "只有系统管理员能建根", code: "FORBIDDEN" },
      { status: 403 }
    );
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid user id" }, { status: 400 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  const parsed = BodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "建根必须填写原因 (2-200 字)", details: parsed.error.errors },
      { status: 400 }
    );
  }

  try {
    const result = await createRootForUser(
      {
        userId: BigInt(id),
        adminUserId: BigInt(session.user.id),
        note: parsed.data.note,
      },
      getAuditContextFromRequest(request, session)
    );
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    if (error instanceof Error) {
      // 业务拒绝 (已在树里 / 账号不存在 / 已停用 / 缺原因) → 400, 不当 500
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("[POST /api/admin/users/[id]/root]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
