// ============================================
// PATCH /api/admin/users/[id] — 停用 / 启用账号
// ============================================
// ADR-0016 D7 (主人 2026-09-22 拍「生命周期要有初步机制, 留待后期完善」)
//
// 口径:
//   - 停用 = 不能登录; **不删**客户档案 / **不摘**加盟节点 (默认不级联)
//   - guardrail: 不能停用自己; 不能停用最后一个在用 admin
//   - 停用必须写原因 (审计留痕); 启用可省
//   - 只有 role='admin' 能调 (服务端查库判, 不信客户端)
//
// 为什么不用 DELETE: 账号是主体模型的"账号面", 删了会牵动客户档案/加盟节点/审计;
//   停用是最小可逆动作 (随时可启用)。

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { setUserActiveStatus } from "@/lib/db/queries/admin-users";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const PatchSchema = z.object({
  isActive: z.boolean(),
  /** 停用必须写原因 (2-200 字, 审计留痕); 启用可省 */
  reason: z.string().min(2).max(200).optional(),
});

export async function PATCH(
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
  const actorUserId = BigInt(session.user.id);

  // 服务端判权 (客户端隐藏入口只是体验)
  const [actor] = await db
    .select({ role: userTable.role })
    .from(userTable)
    .where(eq(userTable.id, actorUserId))
    .limit(1);
  if (actor?.role !== "admin") {
    return NextResponse.json({ error: "只有管理员能停用/启用账号" }, { status: 403 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  try {
    const body = await request.json();
    const input = PatchSchema.parse(body);
    if (!input.isActive && !input.reason) {
      return NextResponse.json({ error: "停用必须填写原因" }, { status: 400 });
    }

    const res = await setUserActiveStatus({
      userId: BigInt(id),
      isActive: input.isActive,
      actorUserId,
      ctx: getAuditContextFromRequest(request, session),
    });

    return NextResponse.json({
      ok: true,
      userId: id,
      name: res.name,
      isActive: res.isActive,
      note: input.isActive
        ? "已启用 (客户档案 / 加盟节点一直保留)"
        : "已停用: 不能登录; 客户档案与加盟节点保留 (默认不级联)",
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Invalid input", details: error.errors },
        { status: 400 }
      );
    }
    const msg = error instanceof Error ? error.message : String(error);
    // 业务 guardrail (自己/最后一个 admin) → 400 把原因透给客户端
    if (msg.includes("不能停用") || msg.includes("账号不存在")) {
      return NextResponse.json({ error: msg }, { status: 400 });
    }
    console.error("[PATCH /api/admin/users/[id]]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
