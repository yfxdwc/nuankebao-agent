// GET /api/admin/usage/users?days=30 — 每个真实用户的使用画像 (admin only)
//
// 回答的问题: 谁在用 / 谁几天没用了 / 各自用了哪些功能 (「完整全面」的用户维度)

import { NextRequest, NextResponse } from "next/server";

import { apiGuard } from "@/lib/api-guard";
import { requireAdminApi } from "@/lib/auth/admin-api";
import { getUsageUsers } from "@/lib/db/queries/usage";

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
  const users = await getUsageUsers(days);
  return NextResponse.json({ days, users });
}
