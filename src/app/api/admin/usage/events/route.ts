// GET /api/admin/usage/events?limit=100&userId=&name= — 最近原始事件 (admin only, 调试用)
//
// 与 /overview /users 的分工:
//   - 聚合看趋势 → overview / users
//   - 单点排查 (「这条 500 是什么路径」) → 本接口, 最多 200 条
//
// 隐私: 事件本身无 PII (词表 + 清洗保证); 仍只允许 admin 读

import { NextRequest, NextResponse } from "next/server";

import { apiGuard } from "@/lib/api-guard";
import { requireAdminApi } from "@/lib/auth/admin-api";
import { listRecentUsageEvents } from "@/lib/db/queries/usage";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const guard = await apiGuard(request, { auth: true, rateLimit: "report" });
  if (guard.response) return guard.response;

  const admin = await requireAdminApi();
  if (!admin.ok) return admin.response;

  const params = new URL(request.url).searchParams;
  const limitRaw = Number(params.get("limit"));
  const limit = Number.isFinite(limitRaw) ? limitRaw : 100;

  const userIdRaw = params.get("userId");
  let userId: bigint | undefined;
  if (userIdRaw && /^\d{1,20}$/.test(userIdRaw)) {
    userId = BigInt(userIdRaw);
  }

  const eventName = params.get("name") ?? undefined;

  const events = await listRecentUsageEvents({
    limit,
    userId,
    eventName,
  });
  return NextResponse.json({ count: events.length, events });
}
