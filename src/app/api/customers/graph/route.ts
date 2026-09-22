// /api/customers/graph
// GET 推荐关系图 (客户页图谱视图数据源)
// 返回: { nodes: [{ id, name, referrerId }] }
//   - 边 = referrerId -> id, 前端从节点列表构建
//   - 范围: RBAC 过滤后的客户池
//   - 不返回手机号/健康数据 (PII 最小化, 见 CHARTER §3.1)
//
// 边界:
//   - 节点上限 1000 (中老年销售实际场景不会超过, 超了再分页)
//   - sales 视角: 只看自己创建的客户
//   - admin 视角: 全网
//   - manager 视角: 本店所有客户

import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getCustomerReferralGraph } from "@/lib/db/queries/customer";
import { getRbacContext } from "@/lib/auth/rbac";
import { resolveViewerPhoneHash } from "@/lib/auth/viewer";

export async function GET() {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // RBAC 上下文 (sales/manager/admin 三种视角过滤)
  // 2026-09-22 (ADR-0015 步骤 0): session 已补 role, getRbacContext 以 DB role 为准
  //   (老 JWT 无 role 字段也能自愈)。
  // ⚠ 本路由是 ADR-0015 Q4 拍定要**废弃**的客户图谱死链路 (零调用方),
  //   保留期间只做最小维护; 删除随步骤 5。
  const sessionUserId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
  const sessionRole = (session?.user as { role?: string } | undefined)?.role;
  let rbacCtx;
  try {
    rbacCtx = await getRbacContext(sessionUserId, sessionRole);
  } catch (err) {
    // RBAC schema 未就绪 → 降级为无过滤 (W5 上线前临时行为)
    console.warn(
      "[GET /api/customers/graph] RBAC 上下文获取失败, 降级为无过滤:",
      String(err).split("\n")[0]
    );
    rbacCtx = undefined;
  }

  // 自己不应该是自己的客户 (主人 2026-09-22): 图谱同样排掉当前登录者自己的客户档案
  const viewerPhoneHash = await resolveViewerPhoneHash(session?.user?.id);
  const nodes = await getCustomerReferralGraph({ rbacCtx, excludePhoneHash: viewerPhoneHash });

  return NextResponse.json({
    nodes,
    count: nodes.length,
  });
}
