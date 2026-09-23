// GET    /api/admin/insight-config   — 读生效配置 + 默认值 + 覆盖原文
// PUT    /api/admin/insight-config   — 保存覆盖 (夹区间 + 版本 +1 + 审计留痕)
// DELETE /api/admin/insight-config   — 重置为默认 (删覆盖行)
//
// 主人 2026-09-23 拍: 「在 admin 里增加管理、调节页面，让评分规则及其他客户管理中的
//   参数可在管理页面进行调节」
//
// 权限: role=admin (服务端查库; 客户端藏入口只是体验)。
//   待拍板 (backlog ⓪-新): 是否允许店长改本店 —— 当前按最窄口径 = 仅系统管理员。
//   参数是否按门店隔离: CHARTER §3.6 门店维度已冻结 → **全局一套** (不按门店)。
//
// 审计: 写/删都走 withAuditContext → app_config 的 audit_trigger 记谁改了什么。
//   (这是 ADR-0015「诊断/配置类改动要留痕」的延伸)

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import {
  getInsightConfigView,
  saveInsightConfig,
  resetInsightConfig,
} from "@/lib/customer/insight-config-store";
import { logger } from "@/lib/errors";

/** 系统管理员闸门 (读也要 admin: 参数本身就是经营策略, 不该给普通销售看) */
async function requireAdmin(session: { user?: { id?: string } } | null) {
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }
  const [actor] = await db
    .select({ role: userTable.role })
    .from(userTable)
    .where(eq(userTable.id, BigInt(session.user.id)))
    .limit(1);
  if (actor?.role !== "admin") {
    return NextResponse.json(
      { error: "只有系统管理员能调节客户管理参数", code: "FORBIDDEN" },
      { status: 403 }
    );
  }
  return null;
}

export async function GET(_request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const gate = await requireAdmin(session);
  if (gate) return gate;

  try {
    return NextResponse.json(await getInsightConfigView());
  } catch (error) {
    logger.error("GET /api/admin/insight-config failed", {}, error);
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}

export async function PUT(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const gate = await requireAdmin(session);
  if (gate) return gate;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  try {
    const ctx = getAuditContextFromRequest(request, session);
    // ⚠ 不在这里做 zod 校验: 参数有 31 个且每个的合法区间由
    //   resolveInsightConfig 统一定义 (它才是唯一真相源)。
    //   在这里再写一份 zod schema = 两处区间定义 = 迟早不一致。
    const view = await saveInsightConfig(body, ctx);
    return NextResponse.json(view);
  } catch (error) {
    logger.error("PUT /api/admin/insight-config failed", {}, error);
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const gate = await requireAdmin(session);
  if (gate) return gate;

  try {
    const ctx = getAuditContextFromRequest(request, session);
    const view = await resetInsightConfig(ctx);
    return NextResponse.json(view);
  } catch (error) {
    logger.error("DELETE /api/admin/insight-config failed", {}, error);
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
