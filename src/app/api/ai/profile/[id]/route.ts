import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { featureGuard } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";
import { generateCustomerProfile } from "@/lib/ai/profile";

/**
 * GET /api/ai/profile/[id]
 * 生成客户画像 (AI 总结)
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // ADR-0012: 会员功能判权 (免费用户 402; 客户端据此弹"开通会员")
  const gate = await featureGuard(session?.user?.id, FEATURES.AI_CUSTOMER_PROFILE);
  if (gate) return gate;

  const { id } = await params;
  const profile = await generateCustomerProfile(BigInt(id));
  if (!profile) {
    return NextResponse.json({ error: "客户不存在" }, { status: 404 });
  }

  return NextResponse.json(profile);
}