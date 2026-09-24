import { db } from "@/lib/db";
import { customer,
  interaction, type Interaction, type NewInteraction } from "@/lib/db/schema";
import { eq, and, desc, sql } from "drizzle-orm";
import { encryptField, decryptField } from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";

export interface InteractionView {
  id: string;
  customerId: string;
  type: string;
  summary: string | null;
  followUpAt: Date | null;
  createdBy: string;
  createdAt: Date;
}

function toView(row: Interaction): InteractionView {
  return {
    id: row.id.toString(),
    customerId: row.customerId.toString(),
    type: row.type,
    summary: row.summaryEncrypted ? decryptField(row.summaryEncrypted) : null,
    followUpAt: row.followUpAt,
    createdBy: row.createdBy.toString(),
    createdAt: row.createdAt,
  };
}

export interface CreateInteractionInput {
  customerId: string;
  type: "phone" | "wechat" | "visit" | "holiday_greeting" | "other";
  summary?: string;
  followUpAt?: string;
}

export async function createInteraction(
  input: CreateInteractionInput,
  ctx: AuditContext,
  createdBy: bigint
): Promise<InteractionView> {
  const data: NewInteraction = {
    customerId: BigInt(input.customerId),
    type: input.type,
    summaryEncrypted: input.summary ? encryptField(input.summary) : null,
    followUpAt: input.followUpAt ? new Date(input.followUpAt) : null,
    createdBy,
  };

  const [row] = await withAuditContext(ctx, async (tx) => {
    const inserted = await tx.insert(interaction).values(data).returning();
    // 跟进紧急度冗余列 (主人 2026-09-20): 记一次互动 = 刷新「上次联系」
    //   同一事务内更新 → 排序口径不会漂移 (只往前推, 不后退, 兼容补录历史)
    await tx
      .update(customer)
      .set({
        lastInteractionAt: sql`GREATEST(COALESCE(${customer.lastInteractionAt}, to_timestamp(0)), ${inserted[0].createdAt.toISOString()}::timestamptz)`,
        updatedAt: sql`NOW()`,
      })
      .where(eq(customer.id, data.customerId));
    return inserted;
  });
  return toView(row);
}

export async function listInteractionsByCustomer(
  customerId: string
): Promise<InteractionView[]> {
  const rows = await db
    .select()
    .from(interaction)
    .where(eq(interaction.customerId, BigInt(customerId)))
    .orderBy(desc(interaction.createdAt));

  return rows.map(toView);
}

export interface UpdateInteractionInput {
  type?: "phone" | "wechat" | "visit" | "holiday_greeting" | "other";
  /**
   * 备注:
   *   - undefined = 不动
   *   - ""        = 清空 (落 null, 但加密列写 null)
   *   - 非空串    = encryptField 覆盖
   */
  summary?: string;
  /**
   * 下次跟进时间:
   *   - undefined = 不动
   *   - null      = 清空
   *   - 字符串     = new Date(input)
   */
  followUpAt?: string | null;
}

export async function getInteractionById(
  id: bigint
): Promise<InteractionView | null> {
  const [row] = await db
    .select()
    .from(interaction)
    .where(eq(interaction.id, id))
    .limit(1);
  return row ? toView(row) : null;
}

export async function updateInteraction(
  id: bigint,
  input: UpdateInteractionInput,
  ctx: AuditContext
): Promise<InteractionView | null> {
  return await withAuditContext(ctx, async (tx) => {
    const updateData: Partial<NewInteraction> = {};
    if (input.type !== undefined) updateData.type = input.type;
    if (input.summary !== undefined) {
      // "" → null (清空); 非空 → encryptField 覆盖
      updateData.summaryEncrypted =
        input.summary === "" ? null : encryptField(input.summary);
    }
    if (input.followUpAt !== undefined) {
      updateData.followUpAt = input.followUpAt
        ? new Date(input.followUpAt)
        : null;
    }

    if (Object.keys(updateData).length === 0) {
      // 没字段要改 → 直接读回当前行
      const [row] = await tx
        .select()
        .from(interaction)
        .where(eq(interaction.id, id))
        .limit(1);
      return row ? toView(row) : null;
    }

    const [row] = await tx
      .update(interaction)
      .set(updateData)
      .where(eq(interaction.id, id))
      .returning();
    return row ? toView(row) : null;
  });
}

export async function deleteInteraction(
  id: bigint,
  ctx: AuditContext
): Promise<boolean> {
  return await withAuditContext(ctx, async (tx) => {
    // 先拿 customerId (同事务 → 一致快照)
    const [target] = await tx
      .select({ customerId: interaction.customerId })
      .from(interaction)
      .where(eq(interaction.id, id))
      .limit(1);
    if (!target) return false;

    const deleted = await tx
      .delete(interaction)
      .where(eq(interaction.id, id))
      .returning({ id: interaction.id });
    if (deleted.length === 0) return false;

    // 跟 createInteraction 对称: create 把 lastInteractionAt 往前推
    // (GREATEST 兜底老行), delete 必须能回退, 否则删掉最近一条后
    // 客户仍显示"刚联系过" → 跟进紧急度排序错位
    // 重算口径 = 该客户剩余 interaction 的 MAX(created_at), 无则 NULL
    const [agg] = await tx
      .select({ maxAt: sql<Date | null>`MAX(${interaction.createdAt})` })
      .from(interaction)
      .where(eq(interaction.customerId, target.customerId));

    // MAX() 返回值在 postgres-js 里是 JS Date, 但保险起见显式 new Date()
    // —— 避免下一步 customer.update 把字符串塞进 timestamptz 列后 .toISOString() 报 "not a function"
    const nextLastInteractionAt = agg?.maxAt ? new Date(agg.maxAt) : null;

    await tx
      .update(customer)
      .set({
        lastInteractionAt: nextLastInteractionAt,
        updatedAt: sql`NOW()`,
      })
      .where(eq(customer.id, target.customerId));

    return true;
  });
}