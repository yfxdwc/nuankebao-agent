// ============================================
// POST /api/customers/[id]/share
// Phase D (主文档 §6.5.4 API + ADR-0019 §4.3)
// ============================================
// 推送入口:
//   - 入参只收 { toUserId, note? }, 严禁 fromUserId (推送人 = 拍下时该客户归属人快照,
//     不是 client 传的字段; session.user.id 才是真)
//   - 错误码 4xx 跟既有 route 语义对齐: 400 / 401 / 403 / 404 / 409
// ============================================

import { NextRequest } from "next/server";
import { z } from "zod";
import { eq } from "drizzle-orm";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import { getCustomerById } from "@/lib/db/queries/customer";
import {
  shareCustomer,
  MAX_ACTIVE_SHARES_PER_CUSTOMER,
  MAX_DAILY_SHARES_PER_RECIPIENT,
  type ShareCustomerFailure,
} from "@/lib/db/queries/customer-share";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { logger } from "@/lib/errors";
import { noStoreJson } from "@/lib/http/no-store";

const BodySchema = z.object({
  /** 接收人 user.id (走 picker 后填) */
  toUserId: z.string().regex(/^\d+$/, "toUserId 必须是数字").max(20),
  /** 推送说明 ≤ 200 字, 可选 */
  note: z.string().max(200).nullable().optional(),
});

const FAILURE_MESSAGE: Record<ShareCustomerFailure, string> = {
  CUSTOMER_NOT_FOUND: "客户档案不存在或已删除",
  NOT_OWNER: "只有该客户的归属人或系统管理员能推送 (主文档 §6.5.2 S1)",
  ZERO_PUSH_TO_SELF: "不能把客户推给自己",
  RECIPIENT_NOT_FOUND: "接收人账号不存在",
  RECIPIENT_INACTIVE: "接收人账号已停用, 不能接收推送",
  TO_USER_NOT_IN_SAME_BRANCH: "接收人与推送者不在同一加盟枝 (主文档 §6.5.2 S2)",
  FORBIDDEN_RE_SHARE: "你是收到推送的客户, 不能二次转发 (主文档 §6.5.2 S7)",
  REQUIRES_SAME_BRANCH_ROOT: "非 admin 推送者必须接入加盟枝",
  ALREADY_SHARED: "该客户已经推送给此人 (S4 幂等: 同 (customer, to_user) 仅一条 active)",
  SHARE_LIMIT_EXCEEDED:
    `推送扩散超限 (主文档 §6.5.2 S6: 同客户 active ≤ ${MAX_ACTIVE_SHARES_PER_CUSTOMER}, 同一接收人每日 ≤ ${MAX_DAILY_SHARES_PER_RECIPIENT})`,
};

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return noStoreJson({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return noStoreJson({ error: "需要登录" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return noStoreJson({ error: "Invalid id" }, { status: 400 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return noStoreJson({ error: "Invalid JSON body" }, { status: 400 });
  }
  const parsed = BodySchema.safeParse(body);
  if (!parsed.success) {
    return noStoreJson(
      { error: "参数错误", details: parsed.error.errors },
      { status: 400 },
    );
  }

  try {
    const customerId = BigInt(id);
    const fromUserId = BigInt(session.user.id);
    const toUserId = BigInt(parsed.data.toUserId);

    // 0. 客户档案存在 + 归属人 / admin 校验前置 — 调用 shareCustomer 内部也会校验,
    //    这里提前在 route 层给 404 / 403, 错误码一致 (主文档 §6.5.4)
    const rbacCtx = await getRbacContextForSession(session);
    // admin 豁免 scope (能看见所有客户); 其余按四段式可见集
    const scope = rbacCtx && rbacCtx.role !== "admin" ? customerRbacFilter(rbacCtx) : undefined;
    const customerRow = await getCustomerById(customerId, {
      viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
      scope,
    });
    if (!customerRow) {
      return noStoreJson({ error: "客户档案不存在或你看不到它" }, { status: 404 });
    }
    // 主动校验 admin (DB 真相源): 老 session 没 role 时拿 DB
    const actorAdmin = rbacCtx?.role === "admin";
    if (!actorAdmin) {
      // 查看原始 ownerId (CustomerView 不暴露它, 这里查一次 DB 拿列)
      const [cRow] = await db
        .select({ ownerId: customer.ownerId })
        .from(customer)
        .where(eq(customer.id, customerId))
        .limit(1);
      if (!cRow || cRow.ownerId !== fromUserId) {
        return noStoreJson(
          { error: FAILURE_MESSAGE.NOT_OWNER },
          { status: 403 },
        );
      }
    }

    // 1. 业务校验 + INSERT (走 shareCustomer 内部 7 步校验)
    const ctx = getAuditContextFromRequest(request, session);
    const result = await shareCustomer(
      {
        customerId,
        fromUserId,
        toUserId,
        note: parsed.data.note ?? null,
      },
      ctx,
    );

    if (!result.ok) {
      return noStoreJson(
        {
          error: FAILURE_MESSAGE[result.code],
          code: result.code,
          detail: result.detail,
        },
        { status: codeToStatus(result.code) },
      );
    }

    return noStoreJson(result.row, { status: 201 });
  } catch (e) {
    logger.error("POST /api/customers/[id]/share failed", { id }, e);
    return noStoreJson({ error: "服务器内部错误" }, { status: 500 });
  }
}

/**
 * 业务失败码 → HTTP 状态码 (主文档 §6.5.4 + 既有 route 语义)
 *   - 400: 业务规则不通过 (跨枝 / 自推 / 重复 / 越权 / S7 / S6)
 *   - 403: 推送权缺失 (S1, 非归属人非 admin)
 *   - 404: 客户档案或接收人不存在
 *   - 409: 重复推送 (S4 幂等)
 */
function codeToStatus(code: ShareCustomerFailure): number {
  switch (code) {
    case "CUSTOMER_NOT_FOUND":
    case "RECIPIENT_NOT_FOUND":
    case "RECIPIENT_INACTIVE":
      return 404;
    case "NOT_OWNER":
      return 403;
    case "ALREADY_SHARED":
      return 409;
    case "ZERO_PUSH_TO_SELF":
    case "TO_USER_NOT_IN_SAME_BRANCH":
    case "FORBIDDEN_RE_SHARE":
    case "REQUIRES_SAME_BRANCH_ROOT":
    case "SHARE_LIMIT_EXCEEDED":
      return 400;
    default:
      return 400;
  }
}
