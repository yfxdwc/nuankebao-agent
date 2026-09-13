import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
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
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const profile = await generateCustomerProfile(BigInt(id));
  if (!profile) {
    return NextResponse.json({ error: "客户不存在" }, { status: 404 });
  }

  return NextResponse.json(profile);
}