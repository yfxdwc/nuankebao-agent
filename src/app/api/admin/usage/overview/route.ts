// GET /api/admin/usage/overview?days=30 — 用量总览 (admin only, 只出聚合)
//
// 回答的问题: 有多少人在用 / 每天用多少 / 哪个功能用得多 / AI 卡片有没有人点 /
//             漏斗哪一步断了 / 哪些接口在报错
//
// 隐私: 只返回聚合 (无姓名 / 手机号 / 原始事件; 原始事件走 /api/admin/usage/events 或脚本)

import { NextRequest, NextResponse } from "next/server";

import { apiGuard } from "@/lib/api-guard";
import { requireAdminApi } from "@/lib/auth/admin-api";
import { getUsageOverview } from "@/lib/db/queries/usage";

export const dynamic = "force-dynamic";

function parseDays(request: NextRequest): number {
  const raw = new URL(request.url).searchParams.get("days");
  const days = Number(raw);
  if (!Number.isFinite(days)) return 30;
  return Math.min(Math.max(Math.round(days), 1), 365);
}

export async function GET(request: NextRequest) {
  const guard = await apiGuard(request, { auth: true, rateLimit: "report" });
  if (guard.response) return guard.response;

  const admin = await requireAdminApi();
  if (!admin.ok) return admin.response;

  const days = parseDays(request);
  const overview = await getUsageOverview(days);
  return NextResponse.json(overview);
}
