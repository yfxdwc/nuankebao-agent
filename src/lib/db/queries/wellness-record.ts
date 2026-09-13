import { db } from "@/lib/db";
import {
  wellnessRecord,
  wellnessRecordBodyPart,
  wellnessRecordProduct,
  bodyPart,
  product,
  type WellnessRecord,
  type NewWellnessRecord,
} from "@/lib/db/schema";
import { eq, and, desc, sql, inArray } from "drizzle-orm";
import {
  encryptField,
  decryptField,
} from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";

// ============================================
// 养生记录 View (API 层用)
// ============================================

export interface WellnessRecordView {
  id: string;
  customerId: string;
  serviceDate: string; // YYYY-MM-DD
  serviceItemId: string;
  staffId: string | null;
  storeId: string | null;
  bodyPartIds: string[];
  productUsages: Array<{ productId: string; quantity: string | null }>;
  preCondition: Record<string, unknown>;
  postCondition: Record<string, unknown>;
  processNote: string | null;
  customerFeedback: string | null;
  photos: string[];
  nextAdviceDate: string | null;
  createdAt: Date;
  updatedAt: Date;
}

function toView(
  row: WellnessRecord,
  bodyPartIds: bigint[],
  productUsages: Array<{ productId: bigint; quantity: string | null }>
): WellnessRecordView {
  const dateToStr = (d: Date | string | null): string => {
    if (!d) return "";
    if (typeof d === "string") return d;
    return d.toISOString().split("T")[0];
  };
  return {
    id: row.id.toString(),
    customerId: row.customerId.toString(),
    serviceDate: dateToStr(row.serviceDate),
    serviceItemId: row.serviceItemId.toString(),
    staffId: row.staffId?.toString() ?? null,
    storeId: row.storeId?.toString() ?? null,
    bodyPartIds: bodyPartIds.map((id) => id.toString()),
    productUsages: productUsages.map((p) => ({
      productId: p.productId.toString(),
      quantity: p.quantity,
    })),
    preCondition: row.preConditionEncrypted
      ? JSON.parse(decryptField(row.preConditionEncrypted))
      : {},
    postCondition: row.postConditionEncrypted
      ? JSON.parse(decryptField(row.postConditionEncrypted))
      : {},
    processNote: row.processNoteEncrypted
      ? decryptField(row.processNoteEncrypted)
      : null,
    customerFeedback: row.customerFeedbackEncrypted
      ? decryptField(row.customerFeedbackEncrypted)
      : null,
    photos: row.photos ?? [],
    nextAdviceDate: row.nextAdviceDate
      ? dateToStr(row.nextAdviceDate)
      : null,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

export interface CreateWellnessRecordInput {
  customerId: string;
  serviceDate: string; // YYYY-MM-DD
  serviceItemId: string;
  staffId?: string;
  storeId?: string;
  bodyPartIds: string[];
  productUsages?: Array<{ productId: string; quantity?: number }>;
  preCondition: Record<string, unknown>;
  postCondition: Record<string, unknown>;
  processNote?: string;
  customerFeedback?: string;
  photos?: string[];
  nextAdviceDate?: string;
}

export interface UpdateWellnessRecordInput {
  serviceDate?: string;
  serviceItemId?: string;
  staffId?: string | null;
  storeId?: string | null;
  bodyPartIds?: string[];
  productUsages?: Array<{ productId: string; quantity?: number }>;
  preCondition?: Record<string, unknown>;
  postCondition?: Record<string, unknown>;
  processNote?: string;
  customerFeedback?: string;
  photos?: string[];
  nextAdviceDate?: string | null;
}

// ============================================
// CRUD
// ============================================

export async function createWellnessRecord(
  input: CreateWellnessRecordInput,
  ctx: AuditContext,
  createdBy: bigint
): Promise<WellnessRecordView> {
  const encryptedData: NewWellnessRecord = {
    customerId: BigInt(input.customerId),
    serviceDate: input.serviceDate,
    storeId: input.storeId ? BigInt(input.storeId) : null,
    staffId: input.staffId ? BigInt(input.staffId) : null,
    serviceItemId: BigInt(input.serviceItemId),
    preConditionEncrypted: encryptField(JSON.stringify(input.preCondition)),
    postConditionEncrypted: encryptField(JSON.stringify(input.postCondition)),
    processNoteEncrypted: input.processNote
      ? encryptField(input.processNote)
      : null,
    customerFeedbackEncrypted: input.customerFeedback
      ? encryptField(input.customerFeedback)
      : null,
    photos: input.photos ?? [],
    nextAdviceDate: input.nextAdviceDate ?? null,
    createdBy,
  };

  return await withAuditContext(ctx, async (tx) => {
    const [row] = await tx
      .insert(wellnessRecord)
      .values(encryptedData)
      .returning();

    // 插入身体部位中间表
    if (input.bodyPartIds.length > 0) {
      await tx.insert(wellnessRecordBodyPart).values(
        input.bodyPartIds.map((id) => ({
          wellnessRecordId: row.id,
          bodyPartId: BigInt(id),
        }))
      );
    }

    // 插入耗材中间表
    if (input.productUsages && input.productUsages.length > 0) {
      await tx.insert(wellnessRecordProduct).values(
        input.productUsages.map((p) => ({
          wellnessRecordId: row.id,
          productId: BigInt(p.productId),
          quantity: p.quantity?.toString() ?? null,
        }))
      );
    }

    return toView(row, input.bodyPartIds.map(BigInt), input.productUsages?.map((p) => ({
      productId: BigInt(p.productId),
      quantity: p.quantity?.toString() ?? null,
    })) ?? []);
  });
}

export async function getWellnessRecordById(
  id: bigint
): Promise<WellnessRecordView | null> {
  const [row] = await db
    .select()
    .from(wellnessRecord)
    .where(eq(wellnessRecord.id, id))
    .limit(1);

  if (!row) return null;

  const [bpRows, prodRows] = await Promise.all([
    db
      .select({ id: wellnessRecordBodyPart.bodyPartId })
      .from(wellnessRecordBodyPart)
      .where(eq(wellnessRecordBodyPart.wellnessRecordId, id)),
    db
      .select({
        productId: wellnessRecordProduct.productId,
        quantity: wellnessRecordProduct.quantity,
      })
      .from(wellnessRecordProduct)
      .where(eq(wellnessRecordProduct.wellnessRecordId, id)),
  ]);

  return toView(row, bpRows.map((r) => r.id), prodRows);
}

export async function listWellnessRecords(options: {
  customerId?: string;
  limit?: number;
  offset?: number;
} = {}): Promise<{ items: WellnessRecordView[]; total: number }> {
  const { customerId, limit = 20, offset = 0 } = options;

  const conditions = [];
  if (customerId) {
    conditions.push(eq(wellnessRecord.customerId, BigInt(customerId)));
  }
  const whereClause =
    conditions.length > 0 ? and(...conditions) : undefined;

  const [rows, [{ count }]] = await Promise.all([
    db
      .select()
      .from(wellnessRecord)
      .where(whereClause)
      .orderBy(desc(wellnessRecord.serviceDate), desc(wellnessRecord.createdAt))
      .limit(limit)
      .offset(offset),
    db
      .select({ count: sql<number>`count(*)::int` })
      .from(wellnessRecord)
      .where(whereClause),
  ]);

  // 批量查询关联 (避免 N+1)
  const ids = rows.map((r) => r.id);
  const [bpRows, prodRows] = ids.length === 0 ? [[], []] : await Promise.all([
    db
      .select()
      .from(wellnessRecordBodyPart)
      .where(inArray(wellnessRecordBodyPart.wellnessRecordId, ids)),
    db
      .select()
      .from(wellnessRecordProduct)
      .where(inArray(wellnessRecordProduct.wellnessRecordId, ids)),
  ]);

  const items = rows.map((row) => {
    const bpIds = (bpRows as Array<{ wellnessRecordId: bigint; bodyPartId: bigint }>)
      .filter((r) => r.wellnessRecordId === row.id)
      .map((r) => r.bodyPartId);
    const pUsages = (prodRows as Array<{ wellnessRecordId: bigint; productId: bigint; quantity: string | null }>)
      .filter((r) => r.wellnessRecordId === row.id)
      .map((r) => ({ productId: r.productId, quantity: r.quantity }));
    return toView(row, bpIds, pUsages);
  });

  return { items, total: count };
}

export async function updateWellnessRecord(
  id: bigint,
  input: UpdateWellnessRecordInput,
  ctx: AuditContext
): Promise<WellnessRecordView | null> {
  const updateData: Partial<NewWellnessRecord> = { updatedAt: new Date() };
  if (input.serviceDate !== undefined) updateData.serviceDate = input.serviceDate;
  if (input.serviceItemId !== undefined) updateData.serviceItemId = BigInt(input.serviceItemId);
  if (input.staffId !== undefined) updateData.staffId = input.staffId ? BigInt(input.staffId) : null;
  if (input.storeId !== undefined) updateData.storeId = input.storeId ? BigInt(input.storeId) : null;
  if (input.preCondition !== undefined) {
    updateData.preConditionEncrypted = encryptField(JSON.stringify(input.preCondition));
  }
  if (input.postCondition !== undefined) {
    updateData.postConditionEncrypted = encryptField(JSON.stringify(input.postCondition));
  }
  if (input.processNote !== undefined) {
    updateData.processNoteEncrypted = input.processNote ? encryptField(input.processNote) : null;
  }
  if (input.customerFeedback !== undefined) {
    updateData.customerFeedbackEncrypted = input.customerFeedback ? encryptField(input.customerFeedback) : null;
  }
  if (input.photos !== undefined) updateData.photos = input.photos;
  if (input.nextAdviceDate !== undefined) updateData.nextAdviceDate = input.nextAdviceDate ?? null;

  return await withAuditContext(ctx, async (tx) => {
    const [row] = await tx
      .update(wellnessRecord)
      .set(updateData)
      .where(eq(wellnessRecord.id, id))
      .returning();

    if (!row) return null;

    // 关联表更新: 先删后插 (简化)
    if (input.bodyPartIds !== undefined) {
      await tx
        .delete(wellnessRecordBodyPart)
        .where(eq(wellnessRecordBodyPart.wellnessRecordId, id));
      if (input.bodyPartIds.length > 0) {
        await tx.insert(wellnessRecordBodyPart).values(
          input.bodyPartIds.map((bid) => ({
            wellnessRecordId: id,
            bodyPartId: BigInt(bid),
          }))
        );
      }
    }
    if (input.productUsages !== undefined) {
      await tx
        .delete(wellnessRecordProduct)
        .where(eq(wellnessRecordProduct.wellnessRecordId, id));
      if (input.productUsages.length > 0) {
        await tx.insert(wellnessRecordProduct).values(
          input.productUsages.map((p) => ({
            wellnessRecordId: id,
            productId: BigInt(p.productId),
            quantity: p.quantity?.toString() ?? null,
          }))
        );
      }
    }

    // 重新查询
    return await getWellnessRecordById(id);
  });
}

export async function deleteWellnessRecord(
  id: bigint,
  ctx: AuditContext
): Promise<boolean> {
  const result = await withAuditContext(ctx, async (tx) => {
    return await tx
      .delete(wellnessRecord)
      .where(eq(wellnessRecord.id, id))
      .returning({ id: wellnessRecord.id });
  });
  return result.length > 0;
}