// /api/customers/stats
// GET 客户类型计数 (胶囊按键上的数量, 主人 2026-09-18 拍)
//
// 返回 { all, franchisee, seed, normal } — 口径跟 GET /api/customers 完全一致
// (同一份 buildCustomerConditions + 「加盟 = 我的下级加盟商」tree 口径);
// 与列表一样排掉当前登录者自己的客户档案 (主人 2026-09-22, 「自己不应该是自己的客户」):
//   all = 全部; franchisee = 我的下级加盟商; seed = 显式标种子且非加盟; normal = 其余
//   三类互斥穷尽 → franchisee + seed + normal === all (前端可断言)
//
// ?search= 支持 (搜索后胶囊数量跟着变, 不会出现「筛出来的比胶囊写的多」)
//
// 边界: RBAC 与列表**同一口径** (ADR-0015 步骤 1): 归属我 ∪ 我的直推加盟

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { customerTypeCounts } from "@/lib/db/queries/customer";
import { getRbacContextForSession } from "@/lib/auth/rbac";
import { resolveViewerPhoneHash } from "@/lib/auth/viewer";

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const search = searchParams.get("search") ?? undefined;

  // 行级过滤 (ADR-0015 步骤 1): 胶囊计数必须与列表同口径, 否则"筛出来的比胶囊写的多"
  //   dev skip-auth 无身份 → undefined = 不过滤 (老行为)
  const rbacCtx = await getRbacContextForSession(session);

  const counts = await customerTypeCounts({
    search,
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    excludePhoneHash: await resolveViewerPhoneHash(session?.user?.id),
    rbacCtx,
  });

  return NextResponse.json(counts);
}
