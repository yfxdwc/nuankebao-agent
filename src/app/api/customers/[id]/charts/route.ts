import { NextRequest, NextResponse } from "next/server";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getCustomerById } from "@/lib/db/queries/customer";
import { loadCustomerCharts } from "@/lib/customer/charts";

/**
 * GET /api/customers/[id]/charts
 *
 * 客户「分析」Tab 的三张图数据 (免费层, 不调 AI):
 *   · trend      —— 效果趋势 (每次记录的 pain/sleep 前→后)
 *   · bodyParts  —— 部位热力 (哪些部位反复出问题 + 止痛中位数)
 *   · 雷达图不需要这里 —— 直接用 /insight 的 effect/engagement/value
 *
 * 为什么跟 /insight 分开:
 *   L0 (评分环 + 待办) 是**一打开详情页就要显示**的, 必须快;
 *   趋势/部位是「点开分析 Tab 才看」的聚合查询 → 拆开, 别拖慢首屏。
 *
 * ⚠ 只做**描述性统计** (出现次数 / 中位止痛幅度)。
 *   不给"该用什么方案"的结论 —— CHARTER §1.3 不做医疗诊断,
 *   方案判断归技师/店长。
 *
 * 安全: 与 [id]/route.ts 同一套 IDOR 口径 (非「我的客户」→ 404)。
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
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }
  const customerId = BigInt(id);

  const rbacCtx = await getRbacContextForSession(session);
  const scope = rbacCtx ? customerRbacFilter(rbacCtx) : undefined;
  const visible = await getCustomerById(customerId, {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope,
  });
  if (!visible) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const charts = await loadCustomerCharts(customerId);
  if (!charts) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(charts);
}
