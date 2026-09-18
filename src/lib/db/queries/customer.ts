import { db } from "@/lib/db";
import {
  customer,
  franchisee,
  type Customer,
  type NewCustomer,
} from "@/lib/db/schema";
import {
  eq,
  isNull,
  and,
  not,
  desc,
  sql,
  ilike,
  inArray,
  or,
  type SQL,
} from "drizzle-orm";
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
  /** 种子客户标记 (显式勾选, 主人 2026-09-18 拍) */
  isSeed: boolean;
  /** 客户类型 (混合判定, 派生): 加盟 > 种子 > 普通 */
  customerType: CustomerType;
  createdAt: Date;
  updatedAt: Date;
}

// ============================================
// 客户类型 (主人 2026-09-18 拍 — 混合方案 C)
// ============================================
//
//   - `franchisee` 加盟: **派生** — `franchisee` 表存在同 phone_hash 且未软删的记录
//                       (客户与加盟商两张表靠 phone_hash 对齐, 不存冗余字段)
//   - `seed`       种子: **显式** — `customer.is_seed = true` (潜在客户开关, 表单可勾)
//   - `normal`     普通: 其余 (默认)
//
// 优先级: 加盟 > 种子 > 普通
//   - 已加盟的客户即使被误标种子也显示「加盟」(加盟是事实关系, 更强)
//   - 老 APK / 未升级客户端不发 is_seed 也能跑 (DB DEFAULT false, 见 drizzle/0005)

export type CustomerType = "franchisee" | "seed" | "normal";
/** 列表筛选: all = 不筛 (默认, 跟旧行为一致) */
export type CustomerTypeFilter = CustomerType | "all";

export const CUSTOMER_TYPES: readonly CustomerType[] = [
  "franchisee",
  "seed",
  "normal",
];

/** SQL: 该客户是否是加盟商 (franchisee 表同手机号 hash + 未软删) */
const isFranchiseeSql = sql`EXISTS (SELECT 1 FROM ${franchisee} WHERE ${franchisee.phoneHash} = ${customer.phoneHash} AND ${franchisee.deletedAt} IS NULL)`;

/**
 * 批量查「哪些 phone_hash 是加盟商」— 列表页一次查完, 避免 N+1
 * (limit ≤ 50 的客户列表 → 一次 IN 查询)
 */
async function loadFranchiseePhoneHashes(
  phoneHashes: string[]
): Promise<Set<string>> {
  if (phoneHashes.length === 0) return new Set();
  const rows = await db
    .select({ phoneHash: franchisee.phoneHash })
    .from(franchisee)
    .where(
      and(
        inArray(franchisee.phoneHash, phoneHashes),
        isNull(franchisee.deletedAt)
      )
    );
  return new Set(rows.map((r) => r.phoneHash));
}

/** 类型判定 (纯函数, 单测用) */
export function resolveCustomerType(
  row: { phoneHash: string; isSeed: boolean },
  franchiseePhoneHashes: Set<string>
): CustomerType {
  if (franchiseePhoneHashes.has(row.phoneHash)) return "franchisee";
  return row.isSeed ? "seed" : "normal";
}

function toView(
  row: Customer,
  franchiseePhoneHashes: Set<string> = new Set()
): CustomerView {
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
    isSeed: row.isSeed,
    customerType: resolveCustomerType(row, franchiseePhoneHashes),
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
  /** 种子客户 (潜在客户开关, 主人 2026-09-18). 缺省 false */
  isSeed?: boolean;
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
  /** 种子客户开关 (true/false 双向可改) */
  isSeed?: boolean;
}

export interface ListCustomersOptions {
  search?: string;
  limit?: number;
  offset?: number;
  includeDeleted?: boolean;
  /** 客户类型筛选 (all / 缺省 = 不筛) */
  type?: CustomerTypeFilter;
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

  return row
    ? toView(row, await loadFranchiseePhoneHashes([row.phoneHash]))
    : null;
}

export async function listCustomers(
  options: ListCustomersOptions = {}
): Promise<{ items: CustomerView[]; total: number }> {
  const {
    search,
    limit = 20,
    offset = 0,
    includeDeleted = false,
    type,
    rbacCtx,
  } = options;

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
  // 客户类型筛选 (胶囊按键, 主人 2026-09-18 拍) — 判定跟 resolveCustomerType 严格对齐:
  //   加盟 = 有 franchisee 记录; 种子 = is_seed 且非加盟; 普通 = 非加盟且非种子
  // 存量老客户端不传 type → 不筛 (跟改动前完全一致)
  if (type && type !== "all") {
    if (type === "franchisee") {
      conditions.push(isFranchiseeSql);
    } else if (type === "seed") {
      conditions.push(eq(customer.isSeed, true), not(isFranchiseeSql));
    } else if (type === "normal") {
      conditions.push(eq(customer.isSeed, false), not(isFranchiseeSql));
    }
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

  const franchiseePhoneHashes = await loadFranchiseePhoneHashes(
    rows.map((r) => r.phoneHash)
  );

  return {
    items: rows.map((r) => toView(r, franchiseePhoneHashes)),
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
  if (input.isSeed !== undefined) updateData.isSeed = input.isSeed;

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(customer)
      .set(updateData)
      .where(and(eq(customer.id, id), isNull(customer.deletedAt)))
      .returning();
  });

  return row
    ? toView(row, await loadFranchiseePhoneHashes([row.phoneHash]))
    : null;
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