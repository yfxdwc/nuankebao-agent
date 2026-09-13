import { db } from "@/lib/db";
import { interaction, type Interaction, type NewInteraction } from "@/lib/db/schema";
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
    return await tx.insert(interaction).values(data).returning();
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