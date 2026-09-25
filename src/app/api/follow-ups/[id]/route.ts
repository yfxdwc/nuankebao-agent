import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  completeFollowUpTask,
  cancelFollowUpTask,
  loadFollowUpTaskScopeById,
} from "@/lib/db/queries/follow-up-task";
import { getCustomerById } from "@/lib/db/queries/customer";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";

// ============================================
// 🔒 IDOR 修复 (R-12 同源, 2026-09-25, 见 docs/customer-idor-audit.md §5):
//   之前 PATCH 只校验登录 → 任意登录者都能按 id 改任意任务 (complete / cancel)。
//   修法 (与 interactions/[id] 同口径):
//     ① loadFollowUpTaskScopeById(id) → 拿 customerId + assignedTo; null = 404
//     ② 可见性判定: 「客户在 viewer 范围内」∪「任务 assigned_to = viewer 本人」
//        → 命中不到 (且 assigned_to ≠ viewer) = 404 (**不**泄漏存在性)
//     ③ 命中 → 才调 completeFollowUpTask / cancelFollowUpTask
//   任务本身存在但已 completed/cancelled (走 complete/cancel 返 null) 仍是 404 ——
//   原行为保留, 错误信息略调 (「Not found」而非「Not found or already completed」,
//   避免向越权者暗示任务存在但状态不符; 合法用户重试时按 404 + GET 二次确认即可)。
// ============================================

const CompleteSchema = z.object({
  action: z.enum(["complete", "cancel"]),
  notes: z.string().optional(),
});

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

  // 🔒 闸门 1: 任务存在?
  const scope = await loadFollowUpTaskScopeById(BigInt(id));
  if (!scope) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  // 🔒 闸门 2: 任务可见? (客户在范围内 ∪ 指派给我)
  //   - dev skip-auth 且无 session → rbacCtx = undefined → 跳过 (双门闸保护)
  //   - admin → scope = undefined → 全过
  const rbacCtx = await getRbacContextForSession(session);
  if (rbacCtx) {
    const inScope = await getCustomerById(scope.customerId, {
      viewerFranchiseeId: rbacCtx.franchiseeId,
      scope: customerRbacFilter(rbacCtx),
    });
    const isAssignedToMe = scope.assignedTo === rbacCtx.userId;
    if (!inScope && !isAssignedToMe) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
  }

  try {
    const body = await request.json();
    const input = CompleteSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const task =
      input.action === "complete"
        ? await completeFollowUpTask(BigInt(id), input.notes, ctx)
        : await cancelFollowUpTask(BigInt(id), ctx);

    if (!task) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    return NextResponse.json(task);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[PATCH /api/follow-ups/[id]]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}