import { NextRequest, NextResponse } from "next/server";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { getCustomerOwnership } from "@/lib/db/queries/customer";
import { logger } from "@/lib/errors";

/**
 * GET /api/customers/[id]/ownership
 * 查一位客户的归属状态 (管理 Tab 的「归属」卡用)
 *
 * 为什么单独一个路由而不是塞进 GET /api/customers/[id]:
 *   - `toView()` 是个纯映射 (row → view), 加 ownerName 得让**所有**调用方都多传一个
 *     参数 (列表 / 详情 / 创建响应 / 编辑响应…) —— 为一个卡片改公共映射不划算;
 *   - 归属卡只在**管理 Tab** 才看, 详情页首屏不该多背一次查库。
 *
 * 返回体里 `canClaim` 的口径与 `claimCustomerOwnership` 的放行条件**一一对应**
 * (见 getCustomerOwnership 的注释) —— 保证"按钮能点 = 后端会放行"。
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  try {
    // 登录者自己的客户档案 id (拦"认领自己"用; ADR-0016 D3 走 ID 不走手机号)
    const [me] = await db
      .select({ customerId: userTable.customerId })
      .from(userTable)
      .where(eq(userTable.id, BigInt(session.user.id)))
      .limit(1);

    const ownership = await getCustomerOwnership(
      BigInt(id),
      BigInt(session.user.id),
      me?.customerId ?? null
    );
    if (!ownership) {
      return NextResponse.json({ error: "客户不存在" }, { status: 404 });
    }
    return NextResponse.json(ownership);
  } catch (error) {
    logger.error("GET /api/customers/[id]/ownership failed", {}, error);
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
