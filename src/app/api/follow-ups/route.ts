import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  listFollowUpTasks,
  createFollowUpTask,
} from "@/lib/db/queries/follow-up-task";
import { getCustomerById } from "@/lib/db/queries/customer";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";

// ============================================
// 🔒 IDOR 修复 (R-12 同源, 2026-09-25, 见 docs/customer-idor-audit.md §5):
//   之前 GET 只校验登录, 随后 `listFollowUpTasks({ status, assignedTo, customerId, ... })`
//   完全不带 viewer 上下文 → 任何登录者都能:
//     ① 不传 customerId → 拉**全库**跟进任务 (任务详情 + 加密 aiSuggestion + 备注)
//     ② 传别人的 customerId → 精确捞他人客户的全部任务
//   修法 (与 `interactions/route.ts` + `wellness-records/route.ts` 一脉相承):
//     - 可见性 = 「任务关联客户在 viewer 范围内」∪「任务 assigned_to = viewer 本人」
//     - 单一真相源 = `customerRbacFilter(rbacCtx)` 传入 `listFollowUpTasks.scope`;
//       Phase D 升级 viewerCustomerScopeSql 时只换 rbac.ts 内一处, 本文件不动
//     - ?customerId= 别人客户 → SQL 自然过滤为空, 返回 { items: [], total: 0 }
//       (**不** 404, 避免泄漏存在性)
//     - admin → scope = undefined, 全见 (与既有 listCustomers 行为一致)
//     - dev skip-auth 且无 session → scope = undefined, 不做行级过滤 (双门闸保护)
//
// POST (写侧, 同源):
//   校验 body.customerId 必须在 viewer 可见范围内, 否则 **400** (而非 404) ——
//   理由: customerId 是 body 字段而非 URL 资源; 400 = 「请求体不合法」语义更准;
//   404 暗示「该 customer 不存在」会误导 caller (它其实存在, 只是不在你范围里)。
//   错误信息显式写明 "not in your scope", 与 404 区分开。
// ============================================

const CreateSchema = z.object({
  customerId: z.string().regex(/^\d+$/),
  dueAt: z.string().datetime(),
  reason: z.string().min(1),
  aiSuggestion: z.string().optional(),
  assignedTo: z.string().regex(/^\d+$/).optional(),
});

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const status = (searchParams.get("status") ?? "pending") as
    | "pending"
    | "done"
    | "cancelled";
  const assignedTo = searchParams.get("assignedTo") ?? undefined;
  // 客户详情页用: 只看这个客户的跟进任务 (主人 2026-09-18)
  const customerId = searchParams.get("customerId") ?? undefined;
  const limit = parseInt(searchParams.get("limit") ?? "50");
  const offset = parseInt(searchParams.get("offset") ?? "0");

  // 🔒 可见性闸门: 任务 = 「客户在 scope 内」∪「指派给我」
  //   - ?customerId= 别人客户 → EXISTS 子查询自然过滤为空, 返回空列表 (不 404)
  //   - admin → scope = undefined, 全见
  //   - dev skip-auth 且无 session → scope = undefined (双门闸保护)
  const rbacCtx = await getRbacContextForSession(session);
  const result = await listFollowUpTasks({
    status,
    assignedTo,
    customerId,
    limit,
    offset,
    scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
    viewerUserId: rbacCtx?.userId ?? null,
  });
  return NextResponse.json(result);
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = CreateSchema.parse(body);

    // 🔒 IDOR 写侧: body.customerId 必须在 viewer 可见范围内
    //   - dev skip-auth 且无 session → 跳过 (双门闸保护, 老 dev 行为)
    //   - admin → scope = undefined → 全过
    //   - sales / manager → 走 customerRbacFilter, 命中不到 → 400
    const rbacCtx = await getRbacContextForSession(session);
    if (rbacCtx) {
      const visible = await getCustomerById(BigInt(input.customerId), {
        viewerFranchiseeId: rbacCtx.franchiseeId,
        scope: customerRbacFilter(rbacCtx),
      });
      if (!visible) {
        return NextResponse.json(
          { error: "Customer not found in your scope" },
          { status: 400 }
        );
      }
    }

    const ctx = getAuditContextFromRequest(request, session);
    const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
    const task = await createFollowUpTask(input, ctx, userId);

    return NextResponse.json(task, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[POST /api/follow-ups]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}