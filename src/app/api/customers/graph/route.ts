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
  // 已知问题: rbac.getRbacContext 查 user.default_store_id, 但 W5 RBAC 字段
  //   尚未 migration (schema.ts 有, DB 没有). 这是 W1 之前的预埋 bug,
  //   不在本次任务范围. 这里 try/catch 降级为无 rbacCtx, 等 W5 RBAC 上线时
  //   移除降级逻辑.
  // 注: Auth.js session.user.role 也未配置 (W5 才会加 JWT role 字段),
  //   默认降级 sales (rbacCtx 内部也 fallback)
  const sessionUserId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
  const sessionRole = (session?.user as { role?: string } | undefined)?.role ?? "sales";
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
