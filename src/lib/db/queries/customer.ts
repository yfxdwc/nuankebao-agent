import { db } from "@/lib/db";
import { customer, type Customer, type NewCustomer } from "@/lib/db/schema";
import { eq, isNull, and, desc, sql, ilike, or, type SQL } from "drizzle-orm";
import {
  encryptField,
  decryptField,
  hashForLookup,
} from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { customerRbacFilter, type RbacContext } from "@/lib/auth/rbac";

// ============================================
// 客户类型 (API 层用, 包含解密的明文)
// ============================================

export interface CustomerView {
  id: string;
  name: string;
  phone: string;
  gender: "M" | "F" | "U" | null;
  birthYear: number | null;
  healthTags: string[];
  diseaseHistory: string | null;
  notes: string | null;
  /** 客户推荐人 (客户图谱数据源), null = 无推荐人 (根/孤儿节点) */
  referrerId: string | null;
  createdAt: Date;
  updatedAt: Date;
}

function toView(row: Customer): CustomerView {
  return {
    id: row.id.toString(),
    name: row.name,
    phone: decryptField(row.phoneEncrypted),
    gender: row.gender,
    birthYear: row.birthYear,
    healthTags: row.healthTagsEncrypted
      ? JSON.parse(decryptField(row.healthTagsEncrypted))
      : [],
    diseaseHistory: row.diseaseHistoryEncrypted
      ? decryptField(row.diseaseHistoryEncrypted)
      : null,
    notes: row.notesEncrypted ? decryptField(row.notesEncrypted) : null,
    referrerId: row.referrerId?.toString() ?? null,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

export interface CreateCustomerInput {
  name: string;
  phone: string;
  gender?: "M" | "F" | "U";
  birthYear?: number;
  healthTags?: string[];
  diseaseHistory?: string;
  notes?: string;
  /** 客户推荐人 (老带新, 客户图谱关系边). null = 无推荐人 */
  referrerId?: string | null;
}

export interface UpdateCustomerInput {
  name?: string;
  phone?: string;
  gender?: "M" | "F" | "U";
  birthYear?: number;
  healthTags?: string[];
  diseaseHistory?: string;
  notes?: string;
  /** 客户推荐人. 显式传 null 可清空推荐人 */
  referrerId?: string | null;
}

export interface ListCustomersOptions {
  search?: string;
  limit?: number;
  offset?: number;
  includeDeleted?: boolean;
  // W5 RBAC: 行级过滤上下文
  rbacCtx?: RbacContext;
}

// ============================================
// CRUD
// ============================================

export async function createCustomer(
  input: CreateCustomerInput,
  ctx: AuditContext,
  createdBy: bigint
): Promise<CustomerView> {
  const encryptedData: NewCustomer = {
    name: input.name,
    phoneEncrypted: encryptField(input.phone),
    phoneHash: hashForLookup(input.phone),
    gender: input.gender,
    birthYear: input.birthYear,
    healthTagsEncrypted: input.healthTags
      ? encryptField(JSON.stringify(input.healthTags))
      : null,
    diseaseHistoryEncrypted: input.diseaseHistory
      ? encryptField(input.diseaseHistory)
      : null,
    notesEncrypted: input.notes ? encryptField(input.notes) : null,
    referrerId: input.referrerId ? BigInt(input.referrerId) : null,
    createdBy,
  };

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx.insert(customer).values(encryptedData).returning();
  });
  return toView(row);
}

export async function getCustomerById(
  id: bigint,
  options?: { includeDeleted?: boolean }
): Promise<CustomerView | null> {
  const conditions = options?.includeDeleted
    ? eq(customer.id, id)
    : and(eq(customer.id, id), isNull(customer.deletedAt));

  const [row] = await db
    .select()
    .from(customer)
    .where(conditions)
    .limit(1);

  return row ? toView(row) : null;
}

export async function listCustomers(
  options: ListCustomersOptions = {}
): Promise<{ items: CustomerView[]; total: number }> {
  const { search, limit = 20, offset = 0, includeDeleted = false, rbacCtx } = options;

  const conditions: SQL[] = [];
  if (!includeDeleted) {
    conditions.push(isNull(customer.deletedAt));
  }
  if (search) {
    const phoneHash = hashForLookup(search);
    conditions.push(
      or(
        ilike(customer.name, `%${search}%`),
        eq(customer.phoneHash, phoneHash)
      )!
    );
  }
  // W5 RBAC: 行级 store_id 过滤 (Q1-A + Q4-A)
  if (rbacCtx) {
    const rbacFilter = customerRbacFilter(rbacCtx);
    if (rbacFilter) {
      conditions.push(rbacFilter);
    }
  }

  const whereClause = conditions.length > 0 ? and(...conditions) : undefined;

  const [rows, [{ count }]] = await Promise.all([
    db.select().from(customer).where(whereClause).orderBy(desc(customer.createdAt)).limit(limit).offset(offset),
    db.select({ count: sql<number>`count(*)::int` }).from(customer).where(whereClause),
  ]);

  return {
    items: rows.map(toView),
    total: count,
  };
}

export async function updateCustomer(
  id: bigint,
  input: UpdateCustomerInput,
  ctx: AuditContext
): Promise<CustomerView | null> {
  const updateData: Partial<NewCustomer> = { updatedAt: new Date() };

  if (input.name !== undefined) updateData.name = input.name;
  if (input.phone !== undefined) {
    updateData.phoneEncrypted = encryptField(input.phone);
    updateData.phoneHash = hashForLookup(input.phone);
  }
  if (input.gender !== undefined) updateData.gender = input.gender;
  if (input.birthYear !== undefined) updateData.birthYear = input.birthYear;
  if (input.healthTags !== undefined) {
    updateData.healthTagsEncrypted = encryptField(JSON.stringify(input.healthTags));
  }
  if (input.diseaseHistory !== undefined) {
    updateData.diseaseHistoryEncrypted = input.diseaseHistory
      ? encryptField(input.diseaseHistory)
      : null;
  }
  if (input.notes !== undefined) {
    updateData.notesEncrypted = input.notes ? encryptField(input.notes) : null;
  }
  if (input.referrerId !== undefined) {
    // 显式传 null = 清空推荐人
    // 闭环检查: 客户不能推荐自己 (DB 层无 self-FK 约束, 应用层必做)
    const newReferrerId = input.referrerId ? BigInt(input.referrerId) : null;
    if (newReferrerId !== null && newReferrerId === id) {
      throw new Error("客户不能推荐自己");
    }
    updateData.referrerId = newReferrerId;
  }

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(customer)
      .set(updateData)
      .where(and(eq(customer.id, id), isNull(customer.deletedAt)))
      .returning();
  });

  return row ? toView(row) : null;
}

/**
 * 软删除
 */
export async function softDeleteCustomer(
  id: bigint,
  ctx: AuditContext
): Promise<boolean> {
  const result = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(customer)
      .set({ deletedAt: new Date() })
      .where(and(eq(customer.id, id), isNull(customer.deletedAt)))
      .returning({ id: customer.id });
  });
  return result.length > 0;
}

// ============================================
// 客户推荐关系图 (客户页图谱视图数据源)
// ============================================

/**
 * 图谱节点 (简化字段, 避免解密全部 PII)
 * 边界: 手机号不解密, 名字明文 (UI 需要)
 */
export interface CustomerGraphNode {
  id: string;
  name: string;
  /** 推荐人 customer.id, null = 根/孤儿 (无推荐人) */
  referrerId: string | null;
}

/**
 * 获取「当前用户」可见客户的推荐关系图 (节点 + 边由前端从 referrerId 派生)
 * 范围:
 *   - sales: createdBy = me (默认 RBAC 策略)
 *   - admin: 全网
 *   - manager: 本店所有客户的子图 (基于 RBAC filter)
 *
 * 设计: 返回节点列表, 边 = referrerId -> id 的关系由前端构建
 *   - 节点上限 1000 (中老年销售不会超过, 超了前端再分页)
 *   - 不返回手机号/健康数据 (图谱视图不需要 PII)
 *   - 已软删客户过滤掉
 */
export async function getCustomerReferralGraph(
  options: { rbacCtx?: RbacContext; limit?: number } = {}
): Promise<CustomerGraphNode[]> {
  const { rbacCtx, limit = 1000 } = options;

  const conditions: SQL[] = [isNull(customer.deletedAt)];
  if (rbacCtx) {
    const rbacFilter = customerRbacFilter(rbacCtx);
    if (rbacFilter) {
      conditions.push(rbacFilter);
    }
  }

  const rows = await db
    .select({
      id: customer.id,
      name: customer.name,
      referrerId: customer.referrerId,
    })
    .from(customer)
    .where(and(...conditions))
    .limit(limit);

  return rows.map((r) => ({
    id: r.id.toString(),
    name: r.name,
    referrerId: r.referrerId?.toString() ?? null,
  }));
}