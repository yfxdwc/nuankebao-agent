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
  or,
  type SQL,
} from "drizzle-orm";
import {
  encryptField,
  decryptField,
  hashForLookup,
} from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { parseAvatarValue, readAvatarValue } from "@/lib/avatar";
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
  /** 生日 (月/日; 不知道 = null) — 主人 2026-09-18 拍: 年月日都可缺 */
  birthMonth: number | null;
  birthDay: number | null;
  /** 历法: 'solar' 阳历 / 'lunar' 农历 */
  birthCalendar: "solar" | "lunar";
  /** 生日提醒强度 (7/3/0 天); null = 不提醒 (月+日 都填了才有意义) */
  birthdayRemindDays: number | null;
  healthTags: string[];
  diseaseHistory: string | null;
  /** 过敏史 (2026-09-18 新增; 跟既往病史分开) */
  allergyHistory: string | null;
  notes: string | null;
  /** 客户推荐人 (客户图谱数据源), null = 无推荐人 (根/孤儿节点) */
  referrerId: string | null;
  /** 客户头像 (null / 'preset:x' / '/uploads/x.jpg') */
  avatar: string | null;
  /** 种子客户标记 (显式勾选, 主人 2026-09-18 拍) */
  isSeed: boolean;
  /** 客户类型 (混合判定, 派生): 加盟 > 种子 > 普通 (「加盟」= 我的下级加盟商) */
  customerType: CustomerType;
  createdAt: Date;
  updatedAt: Date;
}

// ============================================
// 客户类型 (主人 2026-09-18 拍 — 混合方案 C + 图谱同口径)
// ============================================
//
//   - `franchisee` 加盟: **派生** — franchisee 表存在同 phone_hash 记录,
//                        **且该加盟商在我的 placement 子树里 (= 我的下级)**
//                        —— 跟客户页「图谱」tab 同口径 (getPlacementTree / ADR-0010)
//   - `seed`       种子: **显式** — `customer.is_seed = true` (潜在客户开关, 表单可勾)
//   - `normal`     普通: 其余 (默认)
//
// 为什么口径是「我的下级」而不是「任意加盟商」 (主人 2026-09-18):
//   客户列表原本显示加盟 0, 而图谱显示 14 位下级加盟商 → 两张表 (customer vs
//   franchisee) 靠 phone_hash 对齐, seed 数据两拨人手机号不重叠 → 对不上.
//   主人拍: 列表「加盟」= 图谱里的人 (我的下级), 不再用「全局任意加盟商」.
//   实现: 同时给加盟商建客户档案 (createFranchisee / backfill 脚本), 两边就能对上.
//
// 优先级: 加盟 > 种子 > 普通 (已加盟的即使误标种子也显示「加盟」)
//   - 未加盟 viewer (viewerFranchiseeId = null) → 无下级 → 加盟恒 0, 种子/普通照常
//   - 三类互斥且穷尽 → 「全部」= 加盟 + 种子 + 普通 (计数同一套 SQL 保证)
//   - 老 APK / 未升级客户端不发 is_seed 也能跑 (DB DEFAULT false, 见 drizzle/0005)

export type CustomerType = "franchisee" | "seed" | "normal";
/** 列表筛选: all = 不筛 (默认, 跟旧行为一致) */
export type CustomerTypeFilter = CustomerType | "all";

export const CUSTOMER_TYPES: readonly CustomerType[] = [
  "franchisee",
  "seed",
  "normal",
];

/**
 * SQL: 「这位客户 (customer.phone_hash) 是不是我 (viewerFranchiseeId) 的下级加盟商」
 *
 * 口径与 `getPlacementTree` (图谱 tab 数据源) 严格一致:
 *   - 我的子树 = placement_path 前缀匹配 (`''` 根 → 所有 path <> '' 的节点)
 *   - 排除我自己
 *   - 软删加盟商不算
 *
 * viewerFranchiseeId = null (未加盟 / dev 无 session) → 永远 false
 */
export function myDownlineFranchiseeSql(
  viewerFranchiseeId: bigint | null
): SQL {
  if (viewerFranchiseeId === null) return sql`false`;
  return sql`EXISTS (
    SELECT 1 FROM ${franchisee}
    WHERE ${franchisee.deletedAt} IS NULL
      AND ${franchisee.phoneHash} = ${customer.phoneHash}
      AND ${franchisee.id} <> ${viewerFranchiseeId}
      AND EXISTS (
        SELECT 1 FROM franchisee me
        WHERE me.id = ${viewerFranchiseeId}
          AND me.deleted_at IS NULL
          AND (
            (me.placement_path = '' AND ${franchisee.placementPath} <> '')
            OR (me.placement_path <> '' AND ${franchisee.placementPath} LIKE me.placement_path || '%')
          )
      )
  )`;
}

/** 单条判定 (create / get / update 用, 避免为一行拉整个列表) */
async function isMyDownlineFranchisee(
  viewerFranchiseeId: bigint | null,
  phoneHash: string
): Promise<boolean> {
  if (viewerFranchiseeId === null) return false;
  const existsSql = sql`EXISTS (
    SELECT 1 FROM ${franchisee}
    WHERE ${franchisee.deletedAt} IS NULL
      AND ${franchisee.phoneHash} = ${phoneHash}
      AND ${franchisee.id} <> ${viewerFranchiseeId}
      AND EXISTS (
        SELECT 1 FROM franchisee me
        WHERE me.id = ${viewerFranchiseeId}
          AND me.deleted_at IS NULL
          AND (
            (me.placement_path = '' AND ${franchisee.placementPath} <> '')
            OR (me.placement_path <> '' AND ${franchisee.placementPath} LIKE me.placement_path || '%')
          )
      )
  )`;
  const rows = await db.execute<{ d: boolean }>(sql`SELECT ${existsSql} AS d`);
  return rows[0]?.d === true;
}

/** 类型判定 (纯函数, 单测用) */
export function resolveCustomerType(
  row: { isSeed: boolean },
  isMyDownlineFranchisee: boolean
): CustomerType {
  if (isMyDownlineFranchisee) return "franchisee";
  return row.isSeed ? "seed" : "normal";
}

function toView(
  row: Customer,
  isMyDownline: boolean = false
): CustomerView {
  return {
    id: row.id.toString(),
    name: row.name,
    phone: decryptField(row.phoneEncrypted),
    gender: row.gender,
    birthYear: row.birthYear,
    birthMonth: row.birthMonth,
    birthDay: row.birthDay,
    birthCalendar: (row.birthCalendar as "solar" | "lunar") ?? "solar",
    birthdayRemindDays: row.birthdayRemindDays,
    healthTags: row.healthTagsEncrypted
      ? JSON.parse(decryptField(row.healthTagsEncrypted))
      : [],
    diseaseHistory: row.diseaseHistoryEncrypted
      ? decryptField(row.diseaseHistoryEncrypted)
      : null,
    allergyHistory: row.allergyHistoryEncrypted
      ? decryptField(row.allergyHistoryEncrypted)
      : null,
    notes: row.notesEncrypted ? decryptField(row.notesEncrypted) : null,
    referrerId: row.referrerId?.toString() ?? null,
    // 读侧兜底: 库里万一有脏值 → null (跟 user 头像同一套 readAvatarValue)
    avatar: readAvatarValue(row.avatar),
    isSeed: row.isSeed,
    customerType: resolveCustomerType(row, isMyDownline),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

export interface CreateCustomerInput {
  name: string;
  phone: string;
  gender?: "M" | "F" | "U";
  birthYear?: number;
  /** 生日月/日 (1-12 / 1-31); 不知道就别传 = null */
  birthMonth?: number | null;
  birthDay?: number | null;
  /** 历法, 默认 solar */
  birthCalendar?: "solar" | "lunar";
  /** 生日提醒强度 (7/3/0); 只在月+日都有时生效 */
  birthdayRemindDays?: number | null;
  healthTags?: string[];
  diseaseHistory?: string;
  /** 过敏史 (2026-09-18 新增) */
  allergyHistory?: string;
  notes?: string;
  /** 客户推荐人 (老带新, 客户图谱关系边). null = 无推荐人 */
  referrerId?: string | null;
  /** 客户头像: 'preset:<id>' / '/uploads/x.jpg' / null (= 默认首字) */
  avatar?: string | null;
  /** 种子客户 (潜在客户开关, 主人 2026-09-18). 缺省 false */
  isSeed?: boolean;
}

export interface UpdateCustomerInput {
  name?: string;
  phone?: string;
  gender?: "M" | "F" | "U";
  birthYear?: number;
  /** 显式传 null = 清空 (不知道) */
  birthMonth?: number | null;
  birthDay?: number | null;
  birthCalendar?: "solar" | "lunar";
  /** 显式传 null = 关掉生日提醒 */
  birthdayRemindDays?: number | null;
  healthTags?: string[];
  diseaseHistory?: string;
  allergyHistory?: string;
  notes?: string;
  /** 客户推荐人. 显式传 null 可清空推荐人 */
  referrerId?: string | null;
  /** 种子客户开关 (true/false 双向可改) */
  isSeed?: boolean;
  /** 客户头像: 传 null = 恢复默认首字 */
  avatar?: string | null;
}

export interface ListCustomersOptions {
  search?: string;
  limit?: number;
  offset?: number;
  includeDeleted?: boolean;
  /** 客户类型筛选 (all / 缺省 = 不筛) */
  type?: CustomerTypeFilter;
  /**
   * 当前登录者的加盟商 id (viewer 视角)
   * —— 「加盟」= 这位客户是我的下级加盟商 (跟图谱同口径)
   * null / 缺省 = 未加盟或未知 → 加盟恒 0, 种子/普通照常
   */
  viewerFranchiseeId?: bigint | null;
  // W5 RBAC: 行级过滤上下文
  rbacCtx?: RbacContext;
}

/** 类型计数 (胶囊上的数量, 主人 2026-09-18 拍) */
export interface CustomerTypeCounts {
  all: number;
  franchisee: number;
  seed: number;
  normal: number;
}

/**
 * 头像值: 写库前过服务端白名单 (跟 user.avatar_url 同一套 src/lib/avatar.ts)
 * 非法值 → 抛错 (路由转 400), 不静默丢掉用户的选择
 */
function parseAvatarForWrite(raw: string | null | undefined): string | null {
  const parsed = parseAvatarValue(raw ?? null);
  if (!parsed.ok) {
    throw new Error(`头像值不合法: ${parsed.reason}`);
  }
  return parsed.value;
}

// ============================================
// 生日 / 提醒 小工具 (主人 2026-09-18 拍)
// ============================================

/** 生日月/日清洗: 空 → null; 越界 → null (不报错, 数据脏也不让表单炸) */
function normalizeBirthPart(
  v: number | null | undefined,
  min: number,
  max: number
): number | null {
  if (v == null) return null;
  if (!Number.isInteger(v) || v < min || v > max) return null;
  return v;
}

/**
 * 生日提醒强度: 只有「月 + 日」都有才存; 否则 null (= 不提醒)
 * @param remindDays 7 / 3 / 0(当天); 不合法或未传 → 默认 3 (主人默认三天前)
 */
function resolveRemindDays(
  month: number | null | undefined,
  day: number | null | undefined,
  remindDays: number | null | undefined
): number | null {
  if (month == null || day == null) return null;
  if (remindDays == null) return 3; // 填了月日 = 开启提醒, 默认提前 3 天
  return [7, 3, 0].includes(remindDays) ? remindDays : 3;
}

// ============================================
// CRUD
// ============================================

export async function createCustomer(
  input: CreateCustomerInput,
  ctx: AuditContext,
  createdBy: bigint,
  viewerFranchiseeId: bigint | null = null
): Promise<CustomerView> {
  const encryptedData: NewCustomer = {
    name: input.name,
    phoneEncrypted: encryptField(input.phone),
    phoneHash: hashForLookup(input.phone),
    gender: input.gender,
    birthYear: input.birthYear,
    birthMonth: normalizeBirthPart(input.birthMonth, 1, 12),
    birthDay: normalizeBirthPart(input.birthDay, 1, 31),
    birthCalendar: input.birthCalendar ?? "solar",
    // 提醒强度只在「月+日」都有时生效 (业务规则: 填了月日 = 开启生日提醒)
    birthdayRemindDays: resolveRemindDays(
      input.birthMonth,
      input.birthDay,
      input.birthdayRemindDays
    ),
    healthTagsEncrypted: input.healthTags
      ? encryptField(JSON.stringify(input.healthTags))
      : null,
    diseaseHistoryEncrypted: input.diseaseHistory
      ? encryptField(input.diseaseHistory)
      : null,
    allergyHistoryEncrypted: input.allergyHistory
      ? encryptField(input.allergyHistory)
      : null,
    notesEncrypted: input.notes ? encryptField(input.notes) : null,
    referrerId: input.referrerId ? BigInt(input.referrerId) : null,
    avatar: parseAvatarForWrite(input.avatar),
    isSeed: input.isSeed ?? false,
    createdBy,
  };

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx.insert(customer).values(encryptedData).returning();
  });
  // 新建客户可能同时是「我的下级加盟商」(同手机号有 franchisee 记录) → 类型一次算准
  return toView(row, await isMyDownlineFranchisee(viewerFranchiseeId, row.phoneHash));
}

export async function getCustomerById(
  id: bigint,
  options?: { includeDeleted?: boolean; viewerFranchiseeId?: bigint | null }
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
    ? toView(
        row,
        await isMyDownlineFranchisee(options?.viewerFranchiseeId ?? null, row.phoneHash)
      )
    : null;
}

/** 抽出来公用: 列表 / 计数的 WHERE 条件一致 (三者互斥穷尽才能相加==all) */
function buildCustomerConditions(options: ListCustomersOptions): SQL[] {
  const { search, includeDeleted = false, type, rbacCtx, viewerFranchiseeId } = options;
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
  // 客户类型筛选 (胶囊按键, 主人 2026-09-18 拍) — 跟 resolveCustomerType 严格对齐:
  //   加盟 = 我的下级加盟商 (tree 口径, 同图谱); 种子 = is_seed 且非加盟; 普通 = 其余
  // 存量老客户端不传 type → 不筛 (跟改动前完全一致)
  if (type && type !== "all") {
    const downline = myDownlineFranchiseeSql(viewerFranchiseeId ?? null);
    if (type === "franchisee") {
      conditions.push(downline);
    } else if (type === "seed") {
      conditions.push(eq(customer.isSeed, true), not(downline));
    } else if (type === "normal") {
      conditions.push(eq(customer.isSeed, false), not(downline));
    }
  }
  // W5 RBAC: 行级 store_id 过滤 (Q1-A + Q4-A)
  if (rbacCtx) {
    const rbacFilter = customerRbacFilter(rbacCtx);
    if (rbacFilter) {
      conditions.push(rbacFilter);
    }
  }
  return conditions;
}

export async function listCustomers(
  options: ListCustomersOptions = {}
): Promise<{ items: CustomerView[]; total: number }> {
  const { limit = 20, offset = 0, viewerFranchiseeId } = options;
  const conditions = buildCustomerConditions(options);
  const whereClause = conditions.length > 0 ? and(...conditions) : undefined;

  // 类型随行算: 一次 SELECT 把「是否我的下级加盟商」当计算列带回来 (不再多一次 IN 查询)
  const downline = myDownlineFranchiseeSql(viewerFranchiseeId ?? null);
  const [rows, [{ count }]] = await Promise.all([
    db
      .select({ row: customer, isDownline: sql<boolean>`${downline}` })
      .from(customer)
      .where(whereClause)
      .orderBy(desc(customer.createdAt))
      .limit(limit)
      .offset(offset),
    db.select({ count: sql<number>`count(*)::int` }).from(customer).where(whereClause),
  ]);

  return {
    items: rows.map((r) => toView(r.row, r.isDownline === true)),
    total: count,
  };
}

/**
 * 加盟商 → 客户档案打通 (主人 2026-09-18 拍, 方案 A)
 *
 * 背景: customer / franchisee 是两张表 (靠 phone_hash 对齐):
 *   - 客户页「列表」画 customer; 「图谱」画 franchisee
 *   - 不打通 → 列表「加盟」筛不出人 (实测 seed 31 位加盟商 vs 客户 15 位, 交集 0)
 *
 * 语义: 加盟商本身也是销售员要维护的人 → 建加盟商时同时落一份客户档案。
 * 幂等: 同手机号已有客户不动 (onConflictDoNothing; 不覆盖客户维护的姓名/健康数据)。
 * 调用方自己执行 insert (同一事务内), 保证审计 + 回滚一致。
 */
export function franchiseeCustomerValues(input: {
  name: string;
  phone: string;
  createdBy: bigint;
}): NewCustomer {
  return {
    name: input.name,
    phoneEncrypted: encryptField(input.phone),
    phoneHash: hashForLookup(input.phone),
    isSeed: false,
    createdBy: input.createdBy,
  };
}

/**
 * 胶囊上的数量 (主人 2026-09-18 拍): 一次查询算四个桶
 * 口径与 listCustomers 完全一致 (共用 buildCustomerConditions), 且三类互斥 → 相加 = all
 */
export async function customerTypeCounts(options: {
  search?: string;
  viewerFranchiseeId?: bigint | null;
} = {}): Promise<CustomerTypeCounts> {
  const conditions = buildCustomerConditions({
    search: options.search,
    viewerFranchiseeId: options.viewerFranchiseeId,
  });
  const whereClause = conditions.length > 0 ? and(...conditions) : undefined;
  const downline = myDownlineFranchiseeSql(options.viewerFranchiseeId ?? null);

  const [row] = await db
    .select({
      all: sql<number>`count(*)::int`,
      franchisee: sql<number>`(count(*) FILTER (WHERE ${downline}))::int`,
      seed: sql<number>`(count(*) FILTER (WHERE ${customer.isSeed} AND NOT (${downline})))::int`,
      normal: sql<number>`(count(*) FILTER (WHERE NOT ${customer.isSeed} AND NOT (${downline})))::int`,
    })
    .from(customer)
    .where(whereClause);

  return row ?? { all: 0, franchisee: 0, seed: 0, normal: 0 };
}


export async function updateCustomer(
  id: bigint,
  input: UpdateCustomerInput,
  ctx: AuditContext,
  viewerFranchiseeId: bigint | null = null
): Promise<CustomerView | null> {
  const updateData: Partial<NewCustomer> = { updatedAt: new Date() };

  if (input.name !== undefined) updateData.name = input.name;
  if (input.phone !== undefined) {
    updateData.phoneEncrypted = encryptField(input.phone);
    updateData.phoneHash = hashForLookup(input.phone);
  }
  if (input.gender !== undefined) updateData.gender = input.gender;
  if (input.birthYear !== undefined) updateData.birthYear = input.birthYear;
  if (input.birthMonth !== undefined) {
    updateData.birthMonth = normalizeBirthPart(input.birthMonth, 1, 12);
  }
  if (input.birthDay !== undefined) {
    updateData.birthDay = normalizeBirthPart(input.birthDay, 1, 31);
  }
  if (input.birthCalendar !== undefined) {
    updateData.birthCalendar = input.birthCalendar;
  }
  if (
    input.birthdayRemindDays !== undefined ||
    input.birthMonth !== undefined ||
    input.birthDay !== undefined
  ) {
    // 月/日 变动 → 重算提醒: 未传的字段用库里现值, 显式 null = 真的清空
    //   (bug fix: 之前 `input.birthMonth ?? current.m` 把显式 null 当成未传 → 清不掉提醒)
    const [current] = await db
      .select({ m: customer.birthMonth, d: customer.birthDay })
      .from(customer)
      .where(eq(customer.id, id))
      .limit(1);
    const month =
      input.birthMonth !== undefined ? input.birthMonth : (current?.m ?? null);
    const day =
      input.birthDay !== undefined ? input.birthDay : (current?.d ?? null);
    updateData.birthdayRemindDays = resolveRemindDays(
      month,
      day,
      input.birthdayRemindDays ?? null
    );
  }
  if (input.healthTags !== undefined) {
    updateData.healthTagsEncrypted = encryptField(JSON.stringify(input.healthTags));
  }
  if (input.diseaseHistory !== undefined) {
    updateData.diseaseHistoryEncrypted = input.diseaseHistory
      ? encryptField(input.diseaseHistory)
      : null;
  }
  if (input.allergyHistory !== undefined) {
    updateData.allergyHistoryEncrypted = input.allergyHistory
      ? encryptField(input.allergyHistory)
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
  if (input.avatar !== undefined) {
    updateData.avatar = parseAvatarForWrite(input.avatar);
  }

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(customer)
      .set(updateData)
      .where(and(eq(customer.id, id), isNull(customer.deletedAt)))
      .returning();
  });

  return row
    ? toView(row, await isMyDownlineFranchisee(viewerFranchiseeId, row.phoneHash))
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