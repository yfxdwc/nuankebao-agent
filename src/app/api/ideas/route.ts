// ============================================
// /api/ideas — 主人待开发想法 CRUD
//   GET  /api/ideas?status=open|done|discarded  列表 (默认全部, 按 updated_at desc)
//   POST /api/ideas { title, description? }     创建
//
// v0.1.5 主人 2026-09-23 拍 (ask_user d3e7f2a1 第二轮)
//
// auth: admin 自用; admin layout 已把整页保护起来, 这里再确认 session 是 admin
//       (早期 dev 模式 DEV_SKIP_AUTH=1 时不强求, 跟其他 admin 端点同口径)
// audit: POST/PATCH/DELETE 走 withAuditContext → idea_audit 触发器
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { listIdeas, createIdea } from "@/lib/db/queries/idea";
import { getRbacContext } from "@/lib/auth/rbac";

export const dynamic = "force-dynamic";

const IdeaStatusSchema = z.enum(["open", "done", "discarded"]);

const CreateIdeaSchema = z.object({
  title: z.string().trim().min(1, "标题必填").max(200, "标题不超过 200 字"),
  description: z.string().trim().max(5000, "描述不超过 5000 字").optional(),
});

// ---------- GET /api/ideas ----------
export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const sessionUserId = session?.user?.id;
  if (!sessionUserId) {
    return NextResponse.json({ error: "missing user id" }, { status: 401 });
  }

  // 仅 admin 自用 (主人拍板 Q5)
  const rbac = await getRbacContext(BigInt(sessionUserId), session.user.role);
  if (rbac.role !== "admin") {
    return NextResponse.json({ error: "forbidden (admin only)" }, { status: 403 });
  }

  // query: ?status=open|done|discarded (可选)
  const url = new URL(request.url);
  const statusParam = url.searchParams.get("status");
  const status = statusParam
    ? IdeaStatusSchema.safeParse(statusParam).data
    : undefined;
  if (statusParam && !status) {
    return NextResponse.json(
      { error: "invalid status (must be open|done|discarded)" },
      { status: 400 }
    );
  }

  const items = await listIdeas({
    userId: BigInt(sessionUserId),
    status,
  });
  return NextResponse.json({ items });
}

// ---------- POST /api/ideas ----------
export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const sessionUserId = session?.user?.id;
  if (!sessionUserId) {
    return NextResponse.json({ error: "missing user id" }, { status: 401 });
  }

  const rbac = await getRbacContext(BigInt(sessionUserId), session.user.role);
  if (rbac.role !== "admin") {
    return NextResponse.json({ error: "forbidden (admin only)" }, { status: 403 });
  }

  const body = await request.json().catch(() => null);
  const parsed = CreateIdeaSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid input", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const audit = getAuditContextFromRequest(request, { userId: BigInt(sessionUserId) });
  const created = await createIdea(
    {
      userId: BigInt(sessionUserId),
      title: parsed.data.title,
      description: parsed.data.description,
    },
    audit
  );
  return NextResponse.json({ item: created }, { status: 201 });
}