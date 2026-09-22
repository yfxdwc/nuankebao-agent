// ============================================
// API 管理员鉴权 (共享 helper)
//
// 背景: admin 路由原先各自复制「查 session → 查 DB role」8 行 (admin/users,
// billing/admin/*, admin/nodes/* ...)。新用量管理 3 条路由不再复制。
//   ⚠ 真相源 = DB `user.role` (AGENTS §6.6 步骤 0), 不是 session.role
//
// 用法:
//   const admin = await requireAdminApi();
//   if (!admin.ok) return admin.response;
// ============================================

import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";

import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";

export type AdminApiCheck =
  | { ok: true; userId: bigint }
  | { ok: false; response: NextResponse };

export async function requireAdminApi(): Promise<AdminApiCheck> {
  const session = await auth();
  if (!session?.user?.id) {
    return {
      ok: false,
      response: NextResponse.json({ error: "需要登录" }, { status: 401 }),
    };
  }

  const [actor] = await db
    .select({ role: userTable.role })
    .from(userTable)
    .where(eq(userTable.id, BigInt(session.user.id)))
    .limit(1);

  if (actor?.role !== "admin") {
    return {
      ok: false,
      response: NextResponse.json(
        { error: "只有管理员能访问", code: "FORBIDDEN" },
        { status: 403 }
      ),
    };
  }

  return { ok: true, userId: BigInt(session.user.id) };
}
