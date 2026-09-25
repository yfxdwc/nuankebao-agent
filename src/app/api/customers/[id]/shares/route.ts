import { NextRequest } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getCustomerById, getCustomerOwnership } from "@/lib/db/queries/customer";
import { listSharesOfCustomer } from "@/lib/db/queries/customer-share";
import { noStoreJson } from "@/lib/http/no-store";

/**
 * GET /api/customers/[id]/shares
 *
 * 「这个客户当前推给过谁」—— 归属卡「已推送」列表 + 撤销入口用 (Phase D §6.5)。
 * 权限: 客户在我可见范围内, 且我是归属人或 admin (与 POST /share 同口径);
 *      非 admin 只回**我自己发出的** (admin 回全部)。
 * 返回: { items: [{ toUserId, toName, note, createdAt }] } —— 只回姓名, 不回手机号。
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

  const customer = await getCustomerById(customerId, {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
    viewerUserId: rbacCtx?.userId ?? null,
  });
  if (!customer) {
    return noStoreJson({ error: "Not found" }, { status: 404 });
  }

  const isAdmin = rbacCtx?.role === "admin";
  const ownership =
    rbacCtx?.userId != null
      ? await getCustomerOwnership(customerId, rbacCtx.userId, null)
      : null;
  if (!isAdmin && !(ownership?.isMine ?? false)) {
    return noStoreJson({ error: "Not found" }, { status: 404 });
  }

  const items = await listSharesOfCustomer(
    customerId,
    isAdmin ? null : (ownership?.ownerId != null ? BigInt(ownership.ownerId) : null)
  );
  return noStoreJson({ items });
}
