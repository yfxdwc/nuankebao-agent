// POST /api/franchisees/:id/force-unjoin
// admin 强删 (主人 2026-09-18 拍): 绕过三方确认直接解除加盟
//   - 仅 role=admin
//   - 仍有下线 → 拒绝 (先处理下线)
//   - 会写审计日志 (audit_trigger), 并在返回体里说明是强删
import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getRbacContext } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { forceUnjoinFranchisee } from "@/lib/db/queries/franchisee-placement";

export async function POST(
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

  // admin 才允许强删
  // 2026-09-22 (ADR-0015 步骤 0): getRbacContext 以 DB role 为准,
  //   修掉「session 没有 role → admin 恒被当 sales → 403」的老 bug。
  const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
  const rbac = await getRbacContext(
    userId,
    (session?.user as { role?: string } | undefined)?.role
  );
  if (rbac.role !== "admin") {
    return NextResponse.json(
      { error: "只有 admin 可以强删加盟关系" },
      { status: 403 }
    );
  }

  try {
    await forceUnjoinFranchisee(
      BigInt(id),
      getAuditContextFromRequest(request, session)
    );
    return NextResponse.json({ ok: true, forced: true });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error("[POST /api/franchisees/:id/force-unjoin]", msg);
    return NextResponse.json({ error: msg }, { status: 400 });
  }
}
