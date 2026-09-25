import { NextRequest } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getRbacContextForSession } from "@/lib/auth/rbac";
import { getCustomerById, getCustomerOwnership } from "@/lib/db/queries/customer";
import { customerRbacFilter } from "@/lib/auth/rbac";
import { db } from "@/lib/db";
import { sql } from "drizzle-orm";
import { noStoreJson } from "@/lib/http/no-store";

/**
 * GET /api/customers/[id]/share/candidates
 *
 * 「推送给下级」的候选人 = 我在枝上的下层用户 (与 §3.4 (b2) 四段式子树的判定同口径)。
 *
 * 为什么单独一个端点 (Phase D, D-PRIV-3 一期仅 Flutter):
 *   - 推送写的是 `customer_share.to_user_id` (账号), 而图谱树给的是加盟节点 (franchisee)
 *     → 客户端拿不到「节点 → 账号」映射, 必须在服务端做;
 *   - 候选集合由**我的枝**决定, 属可见性/隐私面 → 集中在这里, 客户端不得自行拼 SQL。
 *
 * 权限: 与 POST share 同口径 —— 该客户必须在我可见范围内, 且我必须是归属人或 admin。
 * 返回: { items: [{ userId, name }] } —— 只回 name + id, 不回手机号 (候选人选择不需要)。
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return noStoreJson({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return noStoreJson({ error: "Invalid id" }, { status: 400 });
  }

  const rbacCtx = await getRbacContextForSession(session);
  const customerId = BigInt(id);

  // 可见性 + 归属权 (与 POST /share 同口径, 越权一律 404 不泄漏存在性)
  const customer = await getCustomerById(customerId, {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
    viewerUserId: rbacCtx?.userId ?? null,
  });
  if (!customer) {
    return noStoreJson({ error: "Not found" }, { status: 404 });
  }
  const isAdmin = rbacCtx?.role === "admin";
  // 归属权判定走唯一真相源 getCustomerOwnership (别自己比 owner_id —— 口径会漂)
  const ownership =
    rbacCtx?.userId != null
      ? await getCustomerOwnership(customerId, rbacCtx.userId, null)
      : null;
  if (!isAdmin && !(ownership?.isMine ?? false)) {
    return noStoreJson({ error: "Not found" }, { status: 404 });
  }

  // admin: 全森林 (与 S1/S2 的 admin 豁免一致); 普通用户: 我的枝的下层 (排除自己)
  const rows = rbacCtx?.franchiseeId != null
    ? await db.execute<{ user_id: string; name: string }>(sql`
        SELECT u.id::text AS user_id, u.name
        FROM "user" u
        JOIN franchisee f ON f.id = u.franchisee_id
        JOIN franchisee me ON me.id = ${rbacCtx.franchiseeId}
        WHERE u.is_active = true
          AND f.deleted_at IS NULL
          AND f.id <> me.id
          AND f.root_id IS NOT DISTINCT FROM me.root_id
          AND (
            (me.placement_path = '' AND f.placement_path <> '')
            OR (me.placement_path <> '' AND f.placement_path LIKE (me.placement_path || '%'))
          )
        ORDER BY f.placement_path
        LIMIT 200
      `)
    : await db.execute<{ user_id: string; name: string }>(sql`
        SELECT u.id::text AS user_id, u.name
        FROM "user" u
        WHERE u.is_active = true
        ORDER BY u.id
        LIMIT 200
      `);

  return noStoreJson({
    items: rows.map((r) => ({ userId: r.user_id, name: r.name })),
  });
}
