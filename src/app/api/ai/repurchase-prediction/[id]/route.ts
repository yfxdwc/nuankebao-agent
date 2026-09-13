import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { predictRepurchase } from "@/lib/ai/predictions";

/**
 * GET /api/ai/repurchase-prediction/[id]
 * 复购预测: 基于历史间隔, 算下次预计到店
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const result = await predictRepurchase(BigInt(id));
  if (!result) {
    return NextResponse.json({ error: "客户不存在" }, { status: 404 });
  }
  return NextResponse.json(result);
}