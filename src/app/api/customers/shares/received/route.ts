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
//
// ★ 状态 (2026-09-26 R-10 优化复盘): Flutter / web admin 均**未接入 UI**;
//   receivedShares() 方法定义在 flutter_app/lib/core/services/api.dart:385
//   但无任何调用方。主人拍「保留 + Phase E 接入」 (R-10 文档 §5.3)。
//   本路由暂为「接口在, UI 缺」状态; 后续接「上级推送」列表页时使用。
// ============================================

import { NextRequest } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { listReceivedShares } from "@/lib/db/queries/customer-share";
import { logger } from "@/lib/errors";
import { noStoreJson } from "@/lib/http/no-store";

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 200;

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return noStoreJson({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return noStoreJson({ error: "需要登录" }, { status: 401 });
  }

  try {
    const { searchParams } = new URL(request.url);
    const rawLimit = parseInt(searchParams.get("limit") ?? String(DEFAULT_LIMIT), 10);
    const limit = isNaN(rawLimit)
      ? DEFAULT_LIMIT
      : Math.max(1, Math.min(rawLimit, MAX_LIMIT));

    const items = await listReceivedShares(BigInt(session.user.id), { limit });
    return noStoreJson({
      items,
      total: items.length,
      limit,
    });
  } catch (e) {
    logger.error("GET /api/customers/shares/received failed", {}, e);
    return noStoreJson({ error: "服务器内部错误" }, { status: 500 });
  }
}
