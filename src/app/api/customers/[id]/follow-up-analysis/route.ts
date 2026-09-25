import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { hasFeatureAccess } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";
import { loadFollowUpAnalysis } from "@/lib/follow-up/analysis";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getCustomerById } from "@/lib/db/queries/customer";

/**
 * GET /api/customers/[id]/follow-up-analysis
 *
 * 客户详情页「跟进分析」卡的客观指标 (方案 §7.1)。**全部免费** (方案 §11):
 *   近 30/90 天联系次数 · 平均联系间隔 · 趋势 · 到店规律 · 复购间隔 · 未完成跟进任务
 *
 * AI 解读是会员能力, 但**不在本端点**里生成 —— 走既有 `POST /api/ai/follow-up`
 * (feature key `ai.follow_up`, 非会员 402)。本端点只回 `aiTipAvailable` 提示前端要不要
 * 显示「升级会员看 AI 解读」。
 *
 * 安全 (2026-09-25 P0 IDOR 修复, 见 docs/customer-identity-system.md §9.2 R-12):
 *   行级过滤 — 不在我的客户里 → 404 (避免泄漏存在性), 口径与
 *   `POST /api/customers/[id]/bind-account` 一致 (都走
 *   `getCustomerById(id, { scope: customerRbacFilter(ctx) })`)。
 */
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
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  // P0 IDOR fix: 行级过滤 (与 bind-account 同口径); 命中不到 → 404, 不泄漏存在性
  const rbacCtx = await getRbacContextForSession(session);
  const visible = await getCustomerById(BigInt(id), {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
  });
  if (!visible) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const analysis = await loadFollowUpAnalysis(BigInt(id));
  if (!analysis) {
    // 范围内但 loadFollowUpAnalysis 判定为不存在 (race: 校验后才被软删)
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const aiTipAvailable = await hasFeatureAccess(
    session?.user?.id,
    FEATURES.AI_INSIGHT
  );

  return NextResponse.json({ ...analysis, aiTipAvailable });
}
