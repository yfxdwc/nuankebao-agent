// GET /api/admin/users — 管理员: 全部注册用户 + 加盟树节点总览
//   (主人 2026-09-21 拍: 「我的」→ 用户管理; 列表/图谱两视图; 区分 加盟/未加盟 + 会员标识)
// 权限: 服务端查库判 role=admin (客户端隐藏入口只是体验, 不是权限)
// 隐私: 手机号**只返回打码** (138****8000), 明文不出服务端

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { getAdminUsersOverview } from "@/lib/db/queries/admin-users";

export async function GET(_request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
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
      { error: "只有管理员能看用户管理", code: "FORBIDDEN" },
      { status: 403 }
    );
  }

  const overview = await getAdminUsersOverview();
  return NextResponse.json(overview);
}
