// ============================================
// GET /api/customers/shares/received
// Phase D (主文档 §6.5.4 API + §9.3 角标元数据)
// ============================================
// 返回**当前 user** 收到的所有 active 推送 (角标 / 「上级推送 · N 条」tap 展开用)
//
// 角标元数据约束 (主文档 §9.3):
//   - 所有手机号一律 mask (不论归属如何) — 角标**不是客户档案详情**, 不能透露完整信息
//   - 详情路径才进 viewerCustomerScopeSql → 解密 + ownership 分级明文/maskPhone;
//     此处直接给 mask, 不让 client 拿到明文
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { listReceivedShares } from "@/lib/db/queries/customer-share";
import { logger } from "@/lib/errors";

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 200;

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  try {
    const { searchParams } = new URL(request.url);
    const rawLimit = parseInt(searchParams.get("limit") ?? String(DEFAULT_LIMIT), 10);
    const limit = isNaN(rawLimit)
      ? DEFAULT_LIMIT
      : Math.max(1, Math.min(rawLimit, MAX_LIMIT));

    const items = await listReceivedShares(BigInt(session.user.id), { limit });
    return NextResponse.json({
      items,
      total: items.length,
      limit,
    });
  } catch (e) {
    logger.error("GET /api/customers/shares/received failed", {}, e);
    return NextResponse.json({ error: "服务器内部错误" }, { status: 500 });
  }
}
