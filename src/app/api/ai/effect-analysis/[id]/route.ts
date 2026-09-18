import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { generateEffectAnalysis } from "@/lib/ai/predictions";

/**
 * GET /api/ai/effect-analysis/[id]
 * 效果分析: 多疗程趋势 + AI 总结
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const result = await generateEffectAnalysis(BigInt(id));
  if (!result) {
    return NextResponse.json({ error: "客户不存在" }, { status: 404 });
  }
  return NextResponse.json(result);
}