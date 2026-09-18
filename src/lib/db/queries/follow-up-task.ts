import { db } from "@/lib/db";
import { followUpTask, type FollowUpTask, type NewFollowUpTask } from "@/lib/db/schema";
import { eq, and, desc, isNull, sql, lte, gte } from "drizzle-orm";
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
} = {}): Promise<{ items: FollowUpTaskView[]; total: number }> {
  const { status = "pending", assignedTo, customerId, limit = 50, offset = 0 } = options;

  const conditions = [eq(followUpTask.status, status)];
  if (assignedTo) {
    conditions.push(eq(followUpTask.assignedTo, BigInt(assignedTo)));
  }
  if (customerId) {
    conditions.push(eq(followUpTask.customerId, BigInt(customerId)));
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