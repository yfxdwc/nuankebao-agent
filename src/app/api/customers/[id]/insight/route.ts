import { NextRequest, NextResponse } from "next/server";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getCustomerById } from "@/lib/db/queries/customer";
import { hasFeatureAccess } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";
import { loadCustomerInsight } from "@/lib/customer/insight";
import { DEFAULT_RESOLVED_CONFIG } from "@/lib/customer/insight-config";

/**
 * GET /api/customers/[id]/insight
 *
 * 客户详情页 L0 的**一次请求**拿全部: 评分(三维) + 行动指引(结构化)。
 *
 * 分层 (主人 2026-09-23 拍板 P1):
 *   免费层 = 评分 + 行动指引 —— 确定性规则引擎, **不调 AI, 不判会员**。
 *            理由: CHARTER §1.4「产出可执行的跟进指引」是核心承诺,
 *                  不能因为没会员额度/断网就没行动。
 *   会员层 = 每条行动的 `script` (具体话术) —— 走既有 POST /api/ai/follow-up。
 *            本端点只回 `scriptAvailable` 告诉前端要不要显示"升级看话术"。
 *
 * 安全 (照抄 [id]/route.ts 的 IDOR 口径):
 *   「我的客户」以外的 id 一律 404 (不泄露存在性)。
 *
 * 设计原则 (docs 里那三条, 见 lib/customer/scoring.ts 头注):
 *   ① 确定性 —— 同一天同一客户, 两次请求分数必须一样
 *   ② 不含金额 —— CHARTER §3.6 红线
 *   ③ 可解释 —— 每个维度带 factors[], 每条行动带 evidence{}
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

  // IDOR 守卫: 复用与列表/详情完全相同的行级过滤 (single source of truth)
  const rbacCtx = await getRbacContextForSession(session);
  const scope = rbacCtx ? customerRbacFilter(rbacCtx) : undefined;
  const visible = await getCustomerById(customerId, {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope,
  });
  if (!visible) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const insight = await loadCustomerInsight(customerId);
  if (!insight) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const scriptAvailable = await hasFeatureAccess(
    session?.user?.id,
    FEATURES.AI_FOLLOW_UP
  );

  return NextResponse.json({
    ...insight,
    scriptAvailable,
    /** 前端用这个阈值判断"哪个维度算短板" (避免前端硬编码 60) */
    weakDimensionThreshold: DEFAULT_RESOLVED_CONFIG.scoring.weakDimensionThreshold,
    /**
     * 生效的参数版本 (scoring.configVersion 已随分数返回, 这里再冗余一份顶层)。
     * admin 调节页将来改完参数会 +version, 前端可据此提示"规则已更新"。
     */
    configVersion: DEFAULT_RESOLVED_CONFIG.scoring.version,
  });
}
