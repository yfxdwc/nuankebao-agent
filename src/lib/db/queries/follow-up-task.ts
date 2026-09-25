import { db } from "@/lib/db";
import { customer, followUpTask, type FollowUpTask, type NewFollowUpTask } from "@/lib/db/schema";
import { eq, and, desc, isNull, sql, lte, gte, type SQL } from "drizzle-orm";
import { encryptField, decryptField } from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";

export interface FollowUpTaskView {
  id: string;
  customerId: string;
  dueAt: Date;
  reason: string;
  aiSuggestion: string | null;
  status: "pending" | "done" | "cancelled";
  completedAt: Date | null;
  completedNotes: string | null;
  assignedTo: string | null;
  createdBy: string | null;
  createdAt: Date;
}

function toView(row: FollowUpTask): FollowUpTaskView {
  return {
    id: row.id.toString(),
    customerId: row.customerId.toString(),
    dueAt: row.dueAt,
    reason: row.reason,
    aiSuggestion: row.aiSuggestionEncrypted
      ? decryptField(row.aiSuggestionEncrypted)
      : null,
    status: row.status,
    completedAt: row.completedAt,
    completedNotes: row.completedNotesEncrypted
      ? decryptField(row.completedNotesEncrypted)
      : null,
    assignedTo: row.assignedTo?.toString() ?? null,
    createdBy: row.createdBy?.toString() ?? null,
    createdAt: row.createdAt,
  };
}

export interface CreateFollowUpTaskInput {
  customerId: string;
  dueAt: string;
  reason: string;
  aiSuggestion?: string;
  assignedTo?: string;
}

export async function createFollowUpTask(
  input: CreateFollowUpTaskInput,
  ctx: AuditContext,
  createdBy: bigint
): Promise<FollowUpTaskView> {
  const data: NewFollowUpTask = {
    customerId: BigInt(input.customerId),
    dueAt: new Date(input.dueAt),
    reason: input.reason,
    aiSuggestionEncrypted: input.aiSuggestion
      ? encryptField(input.aiSuggestion)
      : null,
    assignedTo: input.assignedTo ? BigInt(input.assignedTo) : null,
    createdBy,
  };

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx.insert(followUpTask).values(data).returning();
  });
  return toView(row);
}

export async function listFollowUpTasks(options: {
  status?: "pending" | "done" | "cancelled";
  assignedTo?: string;
  /** 只看某个客户的任务 (客户详情页用, 主人 2026-09-18) */
  customerId?: string;
  limit?: number;
  offset?: number;
  /**
   * 行级可见性 (R-12 同源 IDOR 修复, 2026-09-25, 见 docs/customer-idor-audit.md §5):
   *   任务可见 = 「任务关联客户在 viewer 可见范围内」∪「任务 assigned_to = viewer 本人」
   *   - SQL 应是 customer 表上的过滤条件 (典型来源 = `customerRbacFilter(rbacCtx)`)
   *   - undefined = 不过滤 (admin / dev skip-auth 无身份)
   *   - 单一真相源: caller 传 `customerRbacFilter(rbacCtx)`; Phase D 升级
   *     viewerCustomerScopeSql 时只换 rbac.ts 内一处, 本函数不需要再改
   */
  scope?: SQL;
  /** 「任务 assigned_to = viewer 本人」半边的 viewer id (与 OR 配合) */
  viewerUserId?: bigint | null;
} = {}): Promise<{ items: FollowUpTaskView[]; total: number }> {
  const {
    status = "pending",
    assignedTo,
    customerId,
    limit = 50,
    offset = 0,
    scope,
    viewerUserId,
  } = options;

  const conditions: SQL[] = [eq(followUpTask.status, status)];
  if (assignedTo) {
    conditions.push(eq(followUpTask.assignedTo, BigInt(assignedTo)));
  }
  if (customerId) {
    conditions.push(eq(followUpTask.customerId, BigInt(customerId)));
  }
  // 可见性: 任务关联客户在 scope 内 (EXISTS, 不破坏 customerId 过滤)
  //          OR 任务指派给 viewer 本人 (assigned_to = viewerUserId)
  //   - admin / dev skip-auth 无身份 → 不传 scope, 这两条都不加
  //   - sales / manager → scope 已含 owner + 直推加盟 + 店口径; 「assigned_to = 我」补漏
  if (scope) {
    // EXISTS 子查询 (与 customer_id 行级过滤叠加, 不需 innerJoin):
    //   - 子查询里 `${customer}.*` 列名解析到该 EXISTS 内的 customer 表 (无别名冲突)
    //   - caller 传的 `${scope}` (来自 customerRbacFilter) 内含 `${customer.ownerId}` 等引用,
    //     同样解析到本 EXISTS 内的 customer 表 —— Drizzle 渲染成 `"customer"."owner_id"`,
    //     PG 在没有别名的 customer 表的 EXISTS 里精确解析
    const inScope = sql`EXISTS (
      SELECT 1 FROM ${customer}
      WHERE ${customer.id} = ${followUpTask.customerId}
        AND ${customer.deletedAt} IS NULL
        AND (${scope})
    )`;
    conditions.push(
      viewerUserId != null
        ? sql`(${inScope} OR ${followUpTask.assignedTo} = ${viewerUserId})`
        : inScope
    );
  }

  const whereClause = and(...conditions);

  const [rows, [{ count }]] = await Promise.all([
    db
      .select()
      .from(followUpTask)
      .where(whereClause)
      .orderBy(followUpTask.dueAt)
      .limit(limit)
      .offset(offset),
    db
      .select({ count: sql<number>`count(*)::int` })
      .from(followUpTask)
      .where(whereClause),
  ]);

  return {
    items: rows.map(toView),
    total: count,
  };
}

/**
 * 加载跟进任务的 scope 判定字段 (customerId + assignedTo) — 用于 PATCH [id] 闸门
 * (R-12 同源 IDOR 修复, 2026-09-25):
 *   - 返回 null = 任务不存在
 *   - 返回 row → caller 用 `getCustomerById(customerId, { scope })` + row.assignedTo 做
 *     「任务关联客户在范围内 ∪ 任务指派给我」判定
 *
 * 为何不调 getCustomerById 顺带拿 assignedTo:
 *   跟 interactions/[id] 的 guardInteractionScope 同口径 —— route 层判定, query 层只
 *   提供最小原语。Phase D 升级 viewerCustomerScopeSql 时不需要再动本函数。
 */
export async function loadFollowUpTaskScopeById(
  id: bigint
): Promise<{ customerId: bigint; assignedTo: bigint | null } | null> {
  const [row] = await db
    .select({
      customerId: followUpTask.customerId,
      assignedTo: followUpTask.assignedTo,
    })
    .from(followUpTask)
    .where(eq(followUpTask.id, id))
    .limit(1);
  return row ?? null;
}

export async function completeFollowUpTask(
  id: bigint,
  notes: string | undefined,
  ctx: AuditContext
): Promise<FollowUpTaskView | null> {
  const updateData: Partial<NewFollowUpTask> = {
    status: "done",
    completedAt: new Date(),
    completedNotesEncrypted: notes ? encryptField(notes) : null,
  };

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(followUpTask)
      .set(updateData)
      .where(and(eq(followUpTask.id, id), eq(followUpTask.status, "pending")))
      .returning();
  });
  return row ? toView(row) : null;
}

export async function cancelFollowUpTask(
  id: bigint,
  ctx: AuditContext
): Promise<FollowUpTaskView | null> {
  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(followUpTask)
      .set({ status: "cancelled" })
      .where(and(eq(followUpTask.id, id), eq(followUpTask.status, "pending")))
      .returning();
  });
  return row ? toView(row) : null;
}