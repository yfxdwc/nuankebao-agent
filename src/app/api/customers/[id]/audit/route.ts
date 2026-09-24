// ============================================
// GET /api/customers/[id]/audit —— 该客户档案的最近改动 (管理 Tab「最近改动」)
//
// 2026-09-24 (管理 Tab 建议 #2): 归属转移 / 合并 / 身份绑定 / 归档这些操作
//   现在都能查到"谁在什么时候改的"。
//
// 鉴权与可见性: **与 `GET /api/customers/[id]` 同一把尺** —— 看不见的客户一律
//   404 (IDOR 口径: 不是「我的客户」当不存在), 不额外放宽也不额外收紧。
//
// 返回: { items: AuditEntryView[] } (只给"改了哪些列", 不给列值 —— 见 queries/audit.ts)
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getCustomerById } from "@/lib/db/queries/customer";
import { listCustomerAuditTrail } from "@/lib/db/queries/audit";

const MAX_LIMIT = 50;
const DEFAULT_LIMIT = 20;

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const rawLimit = parseInt(
    new URL(request.url).searchParams.get("limit") ?? `${DEFAULT_LIMIT}`,
    10
  );
  const limit = Math.min(
    Math.max(Number.isFinite(rawLimit) ? rawLimit : DEFAULT_LIMIT, 1),
    MAX_LIMIT
  );

  // 行级过滤: 与详情接口同口径 (看不见 → 404)
  const rbacCtx = await getRbacContextForSession(session);
  const scope = rbacCtx ? customerRbacFilter(rbacCtx) : undefined;
  const customer = await getCustomerById(BigInt(id), {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope,
  });
  if (!customer) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const items = await listCustomerAuditTrail(BigInt(id), limit);
  return NextResponse.json({ items });
}
