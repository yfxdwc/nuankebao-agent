import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { hasFeatureAccess } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";
import { loadFollowUpAnalysis } from "@/lib/follow-up/analysis";

/**
 * GET /api/customers/[id]/follow-up-analysis
 *
 * 客户详情页「跟进分析」卡的客观指标 (方案 §7.1)。**全部免费** (方案 §11):
 *   近 30/90 天联系次数 · 平均联系间隔 · 趋势 · 到店规律 · 复购间隔 · 未完成跟进任务
 *
 * AI 解读是会员能力, 但**不在本端点**里生成 —— 走既有 `POST /api/ai/follow-up`
 * (feature key `ai.follow_up`, 非会员 402)。本端点只回 `aiTipAvailable` 提示前端要不要
 * 显示「升级会员看 AI 解读」。
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

  const analysis = await loadFollowUpAnalysis(BigInt(id));
  if (!analysis) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const aiTipAvailable = await hasFeatureAccess(
    session?.user?.id,
    FEATURES.AI_FOLLOW_UP
  );

  return NextResponse.json({ ...analysis, aiTipAvailable });
}
