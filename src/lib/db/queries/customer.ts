import { db } from "@/lib/db";
import {
  customer,
  franchisee,
  user,
  type Customer,
  type NewCustomer,
} from "@/lib/db/schema";
import {
  eq,
  ne,
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
import { parseAvatarValue, readAvatarValue } from "@/lib/avatar";
import { customerRbacFilter, type RbacContext } from "@/lib/auth/rbac";
import { directDownlineFranchiseeSql, hasAccountSql } from "./customer-scope";
import { findActiveUserByReferralCode } from "./franchisee-account";
import { maskPhone } from "@/lib/utils";
import {
  memberExistsSql,
  customerFlagsByCustomerId,
} from "@/lib/billing/member-flag";

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
  /**
   * 客户推荐人 (客户图谱数据源) —— ❌ **已废弃** (ADR-0015 Q4, 主人 2026-09-22 拍)
   *   死链路: 端点 / provider / 视图全删; 列保留仅为存量 (ADR-0004 禁 DROP), 新代码不要读写。
   *   「谁带来谁」的唯一真相源 = `referral_reward` (账号推荐) / `franchisee.placement_parent_id` (结构)。
   */
  referrerId: string | null;
  /** 客户头像 (null / 'preset:x' / '/uploads/x.jpg') */
  avatar: string | null;
  /** 种子客户标记 (显式勾选, 主人 2026-09-18 拍) */
  isSeed: boolean;
  /** 客户类型 (混合判定, 派生): 加盟 > 种子 > 普通 (「加盟」= 我的下级加盟商) */
  customerType: CustomerType;
  /**
   * 会员标识 (主人 2026-09-21 拍: 「会员在别人的列表里也要有明显标识」)
   *   口径 = **关联账号**是不是会员 (账号=客户, ADR-0013; role='admin' 也算),
   *   见 src/lib/billing/member-flag.ts。没有账号的客户恒 false。
   *   ★ 每次查询现算 (不落库) → 充值 / 到期后下次拉列表即变, 无需同步任务
   */
  isMember: boolean;
  /**
   * ★ 这条档案**对应一个 app 账号**吗 (ADR-0016 D8, 主人 2026-09-22 拍「UI 上要有区别」)
   *   true  = 她是已注册用户 (user.customer_id 指过来)
   *   false = 凭空建档的客户 (还没注册 / 永远不会注册)
   *   口径 = **ID** (user.customer_id), 不按手机号相等猜。
   */
  hasAccount: boolean;
  /** 上次联系 (互动记录; 跟进紧急度用, 主人 2026-09-20) */
  lastInteractionAt: Date | null;
  /** 上次到店 (养生记录; 跟进紧急度用) */
  lastVisitAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

// ============================================
// 客户类型 (主人 2026-09-18 拍 混合方案 C; 2026-09-22 主人改「加盟」口径)
// ============================================
//
//   - `franchisee` 加盟: **派生** — franchisee 表存在同 phone_hash 记录,
//                        **且她是我的「直推」加盟商 (点位父 = 我, 第 1 层)**
//                        (主人 2026-09-22: 「列表页加盟客户 = 只算我直推的」)
//   - `seed`       种子: **显式** — `customer.is_seed = true` (潜在客户开关, 表单可勾)
//   - `normal`     普通: 其余 (默认)
//
// ⚠ 与图谱 tab **故意不同口径** (主人 2026-09-22 拍):
//   - 图谱 = 我的**整个** placement 子树 (含下级的下级, 「客户的客户也能看到」)
//   - 列表「加盟」= 只要**直推** (点位父 = 我) → 列表 ⊆ 图谱, 数量天然更少
//   直推是**结构口径** (`placement_parent_id`, 拆栏见 AGENTS §6.8), **不是** referrer_id.
//
// 优先级: 加盟 > 种子 > 普通 (已加盟的即使误标种子也显示「加盟」)
//   - 未加盟 viewer (viewerFranchiseeId = null) → 无直推 → 加盟恒 0, 种子/普通照常
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

// 直推加盟判定 (myDirectDownlineFranchiseeSql) 的**定义**已移到
//   queries/customer-scope.ts (单一真相源): rbac.ts (行级过滤) 要用同一口径,
//   而 customer.ts ↔ rbac.ts 不能互相 import。
//   口径: 直推 = 点位父 (placement_parent_id) = 我; 与图谱(整个子树)故意不同;
//         null → 永远 false。
//   本文件 re-export 旧名字 (tests/customer-type.test.ts 在用)。
export {
  directDownlineFranchiseeSql as myDirectDownlineFranchiseeSql,
} from "./customer-scope";

/** 单条判定 (create / get / update 用, 避免为一行拉整个列表) */
async function isMyDirectDownlineFranchisee(
  viewerFranchiseeId: bigint | null,
  phoneHash: string
): Promise<boolean> {
  if (viewerFranchiseeId === null) return false;
  const existsSql = sql`EXISTS (
    SELECT 1 FROM ${franchisee}
    WHERE ${franchisee.deletedAt} IS NULL
      AND ${franchisee.phoneHash} = ${phoneHash}
      AND ${franchisee.placementParentId} = ${viewerFranchiseeId}
  )`;
  const rows = await db.execute<{ d: boolean }>(sql`SELECT ${existsSql} AS d`);
  return rows[0]?.d === true;
}

/** 类型判定 (纯函数, 单测用) */
export function resolveCustomerType(
  row: { isSeed: boolean },
  isMyDirectDownlineFranchisee: boolean
): CustomerType {
  if (isMyDirectDownlineFranchisee) return "franchisee";
  return row.isSeed ? "seed" : "normal";
}

function toView(
  row: Customer,
  isMyDownline: boolean = false,
  isMember: boolean = false,
  hasAccount: boolean = false
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
    referrerId: row.referrerId?.toString() ?? null, // ❌ 废弃字段 (Q4): 只为存量透出, 新代码不要用
    // 读侧兜底: 库里万一有脏值 → null (跟 user 头像同一套 readAvatarValue)
    avatar: readAvatarValue(row.avatar),
    isSeed: row.isSeed,
    customerType: resolveCustomerType(row, isMyDownline),
    isMember,
    hasAccount,
    lastInteractionAt: row.lastInteractionAt ?? null,
    lastVisitAt: row.lastVisitAt ?? null,
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
  /**
   * 排序 (主人 2026-09-20 拍):
   *   urgency = 跟进紧急度 (调用方负责内存排序; 这里按「最久没联系」近似取全集)
   *   recent  = 最近联系 / new = 最近添加 (默认, 老行为) / name = 姓名
   */
  sort?: "urgency" | "recent" | "new" | "name";
  /**
   * 当前登录者自己的**客户档案 id** (user.customer_id) —— 排掉他自己那条 (主人 2026-09-22):
   *   建号即强制建档 → 每个账号有一条自己的 customer 档案 (语义 = "她作为别人的客户"),
   *   那条不该出现在**她自己**的客户列表里。
   * ★ ID 化 (ADR-0016 D3): 不再按手机号 hash 排除 (同号不同人会误伤)。
   * null / 缺省 = 不排除 (web admin 老调用方保持原样)
   */
  excludeCustomerId?: bigint | null;
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

/**
 * 手机号撞车 (同号提醒, ADR-0016 D5, 主人 2026-09-22 拍)
 *
 * 背景: 手机号**不是**身份锚 (唯一识别码是邀请码), 所以撞号**不静默合并**,
 *   也不静默报 500 —— 停下来告诉操作人"这个号已经有档案", 让她决定:
 *   · 用已有档案 → 走 `POST /api/customers/claim` (加为我的客户, 先到先得)
 *   · 不是同一个人 → 换联系方式 (默认不允许同号两条档案; 见 ADR-0016 §4 fork)
 */
export class CustomerPhoneExistsError extends Error {
  readonly existing: {
    id: bigint;
    name: string;
    hasAccount: boolean;
    ownerName: string | null;
  };
  constructor(existing: {
    id: bigint;
    name: string;
    hasAccount: boolean;
    ownerName: string | null;
  }) {
    const bits: string[] = [];
    if (existing.hasAccount) bits.push("对方已注册 app");
    if (existing.ownerName) bits.push(`已是 ${existing.ownerName} 的客户`);
    super(
      `该手机号已有客户档案: ${existing.name}` +
        (bits.length > 0 ? ` (${bits.join("; ")})` : "") +
        " —— 可用「加为我的客户」接过来, 或换一个联系方式"
    );
    this.name = "CustomerPhoneExistsError";
    this.existing = existing;
  }
}

/** 按手机号找已有档案 (带"是否已注册 / 归属谁"两项提醒信息) */
export async function describeExistingCustomerByPhone(phoneHash: string): Promise<{
  id: bigint;
  name: string;
  hasAccount: boolean;
  ownerName: string | null;
} | null> {
  const [row] = await db
    .select({
      id: customer.id,
      name: customer.name,
      hasAccount: hasAccountSql,
      ownerName: user.name,
    })
    .from(customer)
    .leftJoin(user, eq(user.id, customer.ownerId))
    .where(and(eq(customer.phoneHash, phoneHash), isNull(customer.deletedAt)))
    .limit(1);
  return row ?? null;
}

export async function createCustomer(
  input: CreateCustomerInput,
  ctx: AuditContext,
  createdBy: bigint,
  viewerFranchiseeId: bigint | null = null
): Promise<CustomerView> {
  // ★ 同号提醒 (ADR-0016 D5): 撞号 = 停下问人 (而不是让唯一索引炸成 500)
  const inputPhoneHash = hashForLookup(input.phone);
  const dup = await describeExistingCustomerByPhone(inputPhoneHash);
  if (dup) throw new CustomerPhoneExistsError(dup);

  const encryptedData: NewCustomer = {
    name: input.name,
    phoneEncrypted: encryptField(input.phone),
    phoneHash: inputPhoneHash,
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
    avatar: parseAvatarForWrite(input.avatar),
    isSeed: input.isSeed ?? false,
    // 归属 = 建档人 (ADR-0015 Q11): 手工新建的客户 = 归我
    //   (建号/导入/落位建档不自动归属 —— 见 registration.ts / signup.ts 的 ownerId: null)
    ownerId: createdBy,
    createdBy,
  };

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx.insert(customer).values(encryptedData).returning();
  });
  // 新建客户可能同时是「我的下级加盟商」(同手机号有 franchisee 记录) → 类型一次算准
  // 会员标识同理: 这个手机号可能已经是会员账号 (建号即建档, ADR-0013)
  const flags = await customerFlagsByCustomerId(row.id);
  return toView(
    row,
    await isMyDirectDownlineFranchisee(viewerFranchiseeId, row.phoneHash),
    flags.isMember,
    flags.hasAccount
  );
}

export async function getCustomerById(
  id: bigint,
  options?: {
    includeDeleted?: boolean;
    viewerFranchiseeId?: bigint | null;
    /**
     * 行级过滤 (ADR-0015 步骤 1/IDOR 修复): 不是「我的客户」→ 当不存在 (404)
     *   undefined = 不过滤 (admin / dev skip-auth 无身份)
     */
    scope?: SQL | undefined;
  }
): Promise<CustomerView | null> {
  const conditions = and(
    eq(customer.id, id),
    options?.includeDeleted ? undefined : isNull(customer.deletedAt),
    options?.scope
  );

  const [row] = await db
    .select()
    .from(customer)
    .where(conditions)
    .limit(1);

  if (!row) return null;
  const flags = await customerFlagsByCustomerId(row.id);
  return toView(
    row,
    await isMyDirectDownlineFranchisee(options?.viewerFranchiseeId ?? null, row.phoneHash),
    flags.isMember,
    flags.hasAccount
  );
}

/**
 * 「自己不应该是自己的客户」—— 排掉**当前登录者自己的客户档案**
 *
 * 背景 (主人 2026-09-22 报 + 拍):
 *   建号即强制建档 (AGENTS §6.6) → 每个账号都有一条**同手机号**的 customer 档案。
 *   那条档案的语义是「她作为**别人**的客户」(出现在她推荐人的列表里);
 *   但**她自己**的客户列表不该出现它 —— 否则客户列表第一条就是自己。
 *
 * 口径 (ADR-0016 D3, 主人 2026-09-22 拍「手机号不作为用户识别内容」):
 *   走 **ID** —— 排掉 `customer.id = 我的档案 id` (user.customer_id);
 *   旧口径按 phone_hash 不等排除 —— 同号不同人会被误伤, 已废。
 * 返回 null = 没有可排除的 (未登录 / dev 空 session) → 不加条件 (老行为)
 */
export function selfCustomerExclusionSql(
  viewerCustomerId: bigint | null | undefined
): SQL | null {
  return viewerCustomerId ? ne(customer.id, viewerCustomerId) : null;
}

/** 抽出来公用: 列表 / 计数的 WHERE 条件一致 (三者互斥穷尽才能相加==all) */
function buildCustomerConditions(options: ListCustomersOptions): SQL[] {
  const { search, includeDeleted = false, type, rbacCtx, viewerFranchiseeId } = options;
  const conditions: SQL[] = [];
  if (!includeDeleted) {
    conditions.push(isNull(customer.deletedAt));
  }
  // 自己不应该是自己的客户 (主人 2026-09-22): 排掉当前登录者自己的档案
  const selfExclusion = selfCustomerExclusionSql(options.excludeCustomerId);
  if (selfExclusion) {
    conditions.push(selfExclusion);
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
  //   加盟 = 我的**直推**加盟商 (点位父 = 我; 主人 2026-09-22 拍, 不再算整个子树);
  //   种子 = is_seed 且非加盟; 普通 = 其余
  // 存量老客户端不传 type → 不筛 (跟改动前完全一致)
  if (type && type !== "all") {
    const directDownline = directDownlineFranchiseeSql(viewerFranchiseeId ?? null);
    if (type === "franchisee") {
      conditions.push(directDownline);
    } else if (type === "seed") {
      conditions.push(eq(customer.isSeed, true), not(directDownline));
    } else if (type === "normal") {
      conditions.push(eq(customer.isSeed, false), not(directDownline));
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
  const { limit = 20, offset = 0, viewerFranchiseeId, sort = "new" } = options;
  const conditions = buildCustomerConditions(options);
  const whereClause = conditions.length > 0 ? and(...conditions) : undefined;

  // 类型随行算: 一次 SELECT 把「是否我的直推加盟商」当计算列带回来 (不再多一次 IN 查询)
  const directDownline = directDownlineFranchiseeSql(viewerFranchiseeId ?? null);
  const [rows, [{ count }]] = await Promise.all([
    db
      .select({
        row: customer,
        isDownline: sql<boolean>`${directDownline}`,
        // 会员标识: 同手机号账号的会员状态 (EXISTS 子查询, 不产生重复行)
        // ★ ID 化 (ADR-0016 D3): 会员标识走 user.customer_id, 不再按手机号相等
        isMember: memberExistsSql(sql`u.customer_id = ${customer.id}`),
        // ★ 有没有账号 (ADR-0016 D8): 单一真相源 customer-scope.ts::hasAccountSql
        hasAccount: hasAccountSql,
      })
      .from(customer)
      .where(whereClause)
      .orderBy(
        // urgency: 调用方随后内存排序, 这里按「越久没联系越前」取候选集 (NULLS FIRST = 从没联系)
        sort === "urgency"
          ? sql`${customer.lastInteractionAt} ASC NULLS FIRST`
          : sort === "recent"
            ? sql`${customer.lastInteractionAt} DESC NULLS LAST`
            : sort === "name"
              ? customer.name
              : desc(customer.createdAt)
      )
      .limit(limit)
      .offset(offset),
    db.select({ count: sql<number>`count(*)::int` }).from(customer).where(whereClause),
  ]);

  return {
    items: rows.map((r) =>
      toView(r.row, r.isDownline === true, r.isMember === true, r.hasAccount === true)
    ),
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
    // 归属 = NULL (ADR-0015 Q12): 落位建档不自动归属
    //   —— 她在谁的客户列表里由**结构**决定 (直推加盟, 点位父); 归属留给显式添加
    ownerId: null,
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
  /**
   * 当前登录者自己的客户档案 id —— 与列表 / 概览同一口径排掉他自己那条
   * (ADR-0016 D3: ID 化)。不传 = 不排除 (web admin 老调用方保持原样)。
   */
  excludeCustomerId?: bigint | null;
  /**
   * 行级过滤上下文 (ADR-0015 步骤 1): 传了就跟列表**同一口径**
   * (归属我 ∪ 我的直推加盟); 不传 = 全库 (web admin 老调用方保持原样)
   */
  rbacCtx?: RbacContext;
} = {}): Promise<CustomerTypeCounts> {
  const conditions = buildCustomerConditions({
    search: options.search,
    viewerFranchiseeId: options.viewerFranchiseeId,
    excludeCustomerId: options.excludeCustomerId,
    rbacCtx: options.rbacCtx,
  });
  const whereClause = conditions.length > 0 ? and(...conditions) : undefined;
  const directDownline = directDownlineFranchiseeSql(options.viewerFranchiseeId ?? null);

  const [row] = await db
    .select({
      all: sql<number>`count(*)::int`,
      franchisee: sql<number>`(count(*) FILTER (WHERE ${directDownline}))::int`,
      seed: sql<number>`(count(*) FILTER (WHERE ${customer.isSeed} AND NOT (${directDownline})))::int`,
      normal: sql<number>`(count(*) FILTER (WHERE NOT ${customer.isSeed} AND NOT (${directDownline})))::int`,
    })
    .from(customer)
    .where(whereClause);

  return row ?? { all: 0, franchisee: 0, seed: 0, normal: 0 };
}


export async function updateCustomer(
  id: bigint,
  input: UpdateCustomerInput,
  ctx: AuditContext,
  options?: { viewerFranchiseeId?: bigint | null; scope?: SQL | undefined }
): Promise<CustomerView | null> {
  const viewerFranchiseeId = options?.viewerFranchiseeId ?? null;
  const updateData: Partial<NewCustomer> = { updatedAt: new Date() };

  if (input.name !== undefined) updateData.name = input.name;
  if (input.phone !== undefined) {
    const newPhoneHash = hashForLookup(input.phone);
    // ★ 同号提醒 (ADR-0016 D5): 改成别人已用的号 → 停下问人 (排除自己这条)
    const dup = await describeExistingCustomerByPhone(newPhoneHash);
    if (dup && dup.id !== id) throw new CustomerPhoneExistsError(dup);
    updateData.phoneEncrypted = encryptField(input.phone);
    updateData.phoneHash = newPhoneHash;
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
  if (input.isSeed !== undefined) updateData.isSeed = input.isSeed;
  if (input.avatar !== undefined) {
    updateData.avatar = parseAvatarForWrite(input.avatar);
  }

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(customer)
      .set(updateData)
      .where(
        and(
          eq(customer.id, id),
          isNull(customer.deletedAt),
          // IDOR 防护: 不属于我可见范围的客户 → 影响 0 行 → 路由层 404
          options?.scope
        )
      )
      .returning();
  });

  if (!row) return null;
  const flags = await customerFlagsByCustomerId(row.id);
  return toView(
    row,
    await isMyDirectDownlineFranchisee(viewerFranchiseeId, row.phoneHash),
    flags.isMember,
    flags.hasAccount
  );
}

/**
 * 软删除
 */
export async function softDeleteCustomer(
  id: bigint,
  ctx: AuditContext,
  /** 行级过滤 (IDOR 防护); undefined = 不过滤 (admin / dev skip-auth) */
  scope?: SQL | undefined
): Promise<boolean> {
  const result = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(customer)
      .set({ deletedAt: new Date() })
      .where(
        and(eq(customer.id, id), isNull(customer.deletedAt), scope)
      )
      .returning({ id: customer.id });
  });
  return result.length > 0;
}

// ============================================
// 归属声明 (claim) —— 「把其他用户加为我的客户」的唯一写路径
// ============================================
// 主人 2026-09-22 拍 (ADR-0015 Q11/Q12/Q15):
//   - 建号只建档 (owner_id = NULL), 推荐人在「我推荐的人」页 / 新建客户填推荐码 → **显式**声明归属
//   - 冲突规则 (Q15): **先到先得** → 已有归属 (别人) = 明确报错, 不做抢单
//   - 不能把自己加为客户 (「自己不应该是自己的客户」)
//   - 并发: UPDATE ... WHERE owner_id IS NULL (原子占位); 0 行 = 被别人先占了
//   - 审计: customer 表挂了 audit 触发器 → 这次 UPDATE 自动进 audit_log
export type ClaimCustomerFailure =
  | "NOT_FOUND" // 客户不存在 / 已软删 / 我不存在
  | "SELF" // 不能把自己加为客户
  | "OWNED_BY_OTHER"; // 已有归属 (先到先得)

export type ClaimCustomerResult =
  | { ok: true; alreadyMine: boolean; customer: CustomerView }
  | { ok: false; code: ClaimCustomerFailure };

export async function claimCustomerOwnership(
  customerId: bigint,
  claimantUserId: bigint,
  ctx: AuditContext,
  viewerFranchiseeId: bigint | null = null
): Promise<ClaimCustomerResult> {
  const [me] = await db
    .select({ customerId: user.customerId })
    .from(user)
    .where(eq(user.id, claimantUserId))
    .limit(1);
  if (!me) return { ok: false, code: "NOT_FOUND" };

  const [row] = await db
    .select()
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);
  if (!row) return { ok: false, code: "NOT_FOUND" };

  // 不能把自己加为客户 —— ★ ID 化 (ADR-0016 D3): 比"我的档案 id" (user.customer_id),
  //   不再比手机号 hash (同号不同人会被误拦; 我自己 = 我自己那条档案)
  if (me.customerId != null && row.id === me.customerId) {
    return { ok: false, code: "SELF" };
  }

  if (row.ownerId != null && row.ownerId !== claimantUserId) {
    return { ok: false, code: "OWNED_BY_OTHER" };
  }

  const view = async (r: Customer) => {
    const flags = await customerFlagsByCustomerId(r.id);
    return toView(
      r,
      await isMyDirectDownlineFranchisee(viewerFranchiseeId, r.phoneHash),
      flags.isMember,
      flags.hasAccount
    );
  };

  // 已经是我的 → 幂等成功 (不重复写)
  if (row.ownerId === claimantUserId) {
    return { ok: true, alreadyMine: true, customer: await view(row) };
  }

  // 原子声明: 只在归属仍为空时写入 (并发抢单 → 0 行)
  const [updated] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(customer)
      .set({ ownerId: claimantUserId, updatedAt: new Date() })
      .where(
        and(
          eq(customer.id, customerId),
          isNull(customer.ownerId),
          isNull(customer.deletedAt)
        )
      )
      .returning();
  });
  if (!updated) return { ok: false, code: "OWNED_BY_OTHER" };

  return { ok: true, alreadyMine: false, customer: await view(updated) };
}

// ============================================
// 绑定 app 身份 (填邀请码) —— 手工客户 ↔ 她的账号
// ============================================
// 主人 2026-09-22 拍:
//   「当用户先自建的客户 (没注册 app 账号), 之后这个客户注册使用了 app,
//     要能在**客户详情页**中填写客户的**邀请码 (身份识别码)** 绑定用户身份,
//     并在**客户列表**中显示标识。同为 app 用户方便在 app 内邀请/通过会议。」
//
// 为什么需要"显式绑定":
//   建号时系统会按**手机号**自动认领既有档案 (createAccountWithProfile 复用同号档案),
//   但客户档案上的手机号可能写错 / 她换号注册 → 自动认领不上, 两边就散着。
//   邀请码 = 唯一识别码 (ADR-0016 D1) → 用它把两边合上 (不依赖手机号相等)。
//
// 边界: 只改 user.customer_id (列连接, ADR-0015 Q7); 手机号**默认不动** ——
//   档案上的号可能是销售特意记的另一个联系方式, 要不要同步由调用方显式 syncPhone 决定。
export type BindCustomerAccountFailure =
  | "NOT_FOUND" // 客户不存在 / 已软删
  | "CODE_NOT_FOUND" // 邀请码没有对应账号
  | "BOUND_TO_OTHER" // 该客户已绑别的账号, 或该账号已绑别的客户档案
  | "PHONE_CONFLICT"; // 同步手机号时撞上另一条客户档案

export interface BindCustomerAccountOk {
  ok: true;
  /** 本来就绑着 (幂等) */
  alreadyBound: boolean;
  /** 客户档案的手机号与账号手机号不一致 */
  phoneMismatch: boolean;
  /** 本次是否把档案手机号同步成了账号手机号 */
  phoneSynced: boolean;
  /**
   * 是否**接管**了她注册时系统自动建的空档案 (那条被删掉, 让位给这条手工档案)
   *   —— 主人 2026-09-22 场景: 客户先被手工建档, 后来自己注册 → 系统按她的号另建了一条;
   *      绑定 = 用手工那条(带记录)当她的正式档案, 删掉系统那条空档案
   */
  replacedEmptyProfile: boolean;
  account: { userId: bigint; name: string; phoneMasked: string };
}

/** 这条档案是不是"空的" (没有任何维护记录) —— 接管前必须为空, 否则要人工合并 */
async function isCustomerProfileEmpty(customerId: bigint): Promise<boolean> {
  const rows = await db.execute<{ n: number }>(sql`
    SELECT (
      (SELECT count(*) FROM interaction WHERE customer_id = ${customerId}) +
      (SELECT count(*) FROM wellness_record WHERE customer_id = ${customerId}) +
      (SELECT count(*) FROM follow_up_task WHERE customer_id = ${customerId})
    )::int AS n
  `);
  return Number(rows[0]?.n ?? 0) === 0;
}

export async function bindCustomerAccount(
  customerId: bigint,
  referralCode: string,
  opts: { syncPhone?: boolean } = {},
  ctx: AuditContext
): Promise<BindCustomerAccountOk | { ok: false; code: BindCustomerAccountFailure; detail?: string }> {
  const [row] = await db
    .select()
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);
  if (!row) return { ok: false, code: "NOT_FOUND" };

  const account = await findActiveUserByReferralCode(db, referralCode);
  if (!account) return { ok: false, code: "CODE_NOT_FOUND" };

  const okView = (
    alreadyBound: boolean,
    phoneMismatch: boolean,
    phoneSynced: boolean,
    replacedEmptyProfile = false
  ): BindCustomerAccountOk => ({
    ok: true,
    alreadyBound,
    phoneMismatch,
    phoneSynced,
    replacedEmptyProfile,
    account: { userId: account.userId, name: account.name, phoneMasked: maskPhone(account.phone) },
  });

  // 这条档案当前绑的是谁 (user.customer_id 指过来)
  const [currentLink] = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.customerId, customerId))
    .limit(1);

  const phoneMismatch = row.phoneHash !== account.phoneHash;

  if (currentLink && currentLink.id === account.userId) {
    return okView(true, phoneMismatch, false); // 幂等
  }
  if (currentLink && currentLink.id !== account.userId) {
    return { ok: false, code: "BOUND_TO_OTHER", detail: "这条档案已经绑定另一个账号了" };
  }

  // 她注册时系统可能已经按她的手机号**自动建了一条档案** → 要判断能不能接管
  let staleProfileId: bigint | null = null;
  if (account.customerId != null && account.customerId !== customerId) {
    const empty = await isCustomerProfileEmpty(account.customerId);
    if (!empty) {
      return {
        ok: false,
        code: "BOUND_TO_OTHER",
        detail:
          "她的账号上已有一条**带记录的**客户档案 (互动/养生/跟进) —— 需要人工合并, 不能直接接管",
      };
    }
    staleProfileId = account.customerId;
  }

  // 手机号: 要写入档案的号 = 账号的号 (她注册时用的真号)
  //   - 接管空档案时**默认写** (空档案让位, 不写就白接管了)
  //   - 没有空档案时按调用方 syncPhone 决定 (档案上的号可能是销售特意记的另一个联系方式)
  const shouldSyncPhone = phoneMismatch && (staleProfileId != null || opts.syncPhone === true);
  if (shouldSyncPhone) {
    const others = [customerId];
    if (staleProfileId != null) others.push(staleProfileId);
    const [conflict] = await db
      .select({ id: customer.id })
      .from(customer)
      .where(
        and(
          eq(customer.phoneHash, account.phoneHash),
          not(inArray(customer.id, others)),
          isNull(customer.deletedAt)
        )
      )
      .limit(1);
    if (conflict) {
      return {
        ok: false,
        code: "PHONE_CONFLICT",
        detail: "账号的手机号已经是另一条客户档案了 —— 先处理重复档案",
      };
    }
  }

  await withAuditContext(ctx, async (tx) => {
    // ① 接管: 删掉她注册时系统自动建的空档案 (无任何记录 → 删了不丢东西; 腾出手机号)
    if (staleProfileId != null) {
      await tx.delete(customer).where(eq(customer.id, staleProfileId));
    }
    // ② 手机号对齐 (用她账号里的真号)
    if (shouldSyncPhone) {
      await tx
        .update(customer)
        .set({
          phoneEncrypted: encryptField(account.phone),
          phoneHash: account.phoneHash,
          updatedAt: new Date(),
        })
        .where(eq(customer.id, customerId));
    }
    // ③ 连接: user.customer_id = 这条档案 (账号↔档案 的唯一真相, ADR-0015 Q7)
    await tx
      .update(user)
      .set({ customerId, updatedAt: new Date() })
      .where(eq(user.id, account.userId));
  });

  return {
    ...okView(false, phoneMismatch, shouldSyncPhone),
    replacedEmptyProfile: staleProfileId != null,
  };
}

// ============================================
// (已删) 客户推荐关系图 —— ADR-0015 Q4 死链路
// ============================================
// 原 getCustomerReferralGraph + /api/customers/graph + Flutter CustomerGraphView
// 全部零调用方 (2026-09-22 实测), 但会误导后来人当真相源 → 主人拍「废弃」已删。
// 「谁带来谁」看: referral_reward (账号推荐) / franchisee.placement_parent_id (点位父)。

// ============================================
// 归属 (谁的客户) —— 管理维度 (2026-09-23, P7)
// ============================================
// 背景: 主人 2026-09-23 指出「记录、管理、分析三个维度都还相当粗糙」,
//   而管理维度里**唯一真缺口就是归属** —— 编辑表单已覆盖姓名/手机/生日/提醒/
//   健康标签/病史/过敏/备注, 但**详情页看不到"这是谁的客户", 也没法认领**。
//
// 为什么口径必须与 `claimCustomerOwnership` 完全一致:
//   UI 的按钮可用性判断 (canClaim) 必须等于**后端真正会不会放行** ——
//   否则就是"按钮能点但一点就 409" (最气的交互)。
//   所以这里逐条对齐那个函数的判定顺序:
//     ① 我自己那条档案    → 不能认领 (后端返 SELF)
//     ② ownerId == null   → 可认领
//     ③ ownerId == 我     → 可认领 (幂等, 后端返 alreadyMine)
//     ④ ownerId == 别人   → 不可认领 (后端返 OWNED_BY_OTHER)
//
// ⚠ 与 `customer.owner_id` 的关系 (ADR-0015 Q11):
//   owner_id = "谁把她当客户在管" (谁的客户列表);
//   与 `referrer_id`(谁拉她进加盟) / `created_by`(谁录入的) 是**三件不同的事**,
//   不要互相推导 —— 建档 ≠ 归属 (Q11 明文)。

export interface CustomerOwnershipView {
  customerId: string;
  /** 归属人 user.id; null = 无归属 */
  ownerId: string | null;
  ownerName: string | null;
  /** 登录者就是归属人 */
  isMine: boolean;
  /** UI 按钮可用性 —— 与 claimCustomerOwnership 的放行条件一一对应 */
  canClaim: boolean;
  /** 不能认领的原因 (人话; canClaim=true 时为 null) */
  blockedReason: string | null;
  /** 一句话状态 (后端算好, 前端不拼文案 —— 免得两处措辞不一致) */
  statusLabel: string;
}

/**
 * 查一位客户的归属状态 (管理 Tab 的「归属」卡用)
 *
 * @param viewerUserId    登录者 user.id
 * @param viewerCustomerId 登录者自己的客户档案 id (user.customer_id) —— 用来拦"认领自己"
 */
export async function getCustomerOwnership(
  customerId: bigint,
  viewerUserId: bigint,
  viewerCustomerId: bigint | null
): Promise<CustomerOwnershipView | null> {
  const [row] = await db
    .select({
      id: customer.id,
      ownerId: customer.ownerId,
      ownerName: user.name,
    })
    .from(customer)
    .leftJoin(user, eq(user.id, customer.ownerId))
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);

  if (!row) return null;

  const isMine = row.ownerId != null && row.ownerId === viewerUserId;
  const isMyOwnProfile = viewerCustomerId != null && row.id === viewerCustomerId;

  let canClaim = false;
  let blockedReason: string | null = null;
  let statusLabel: string;

  if (isMyOwnProfile) {
    // ① 她就是我自己的客户档案 (建号即建档的产物) —— 后端会返 SELF
    statusLabel = "这是你自己的档案";
    blockedReason = "不能把自己加为客户";
  } else if (row.ownerId == null) {
    // ② 无归属 → 先到先得 (ADR-0015 Q15)
    canClaim = true;
    statusLabel = "还没有归属人";
  } else if (isMine) {
    // ③ 已经是我的 → 幂等, 按钮仍给 (点了不报错, 提示"已经是你的客户")
    canClaim = true;
    statusLabel = "我的客户";
  } else {
    // ④ 归属别人 → 先到先得, 不给按钮 (给了就是"一点就 409")
    statusLabel = `已是 ${row.ownerName ?? "他人"} 的客户`;
    blockedReason = "已被别人先认领 (先到先得); 要转移需与对方协商";
  }

  return {
    customerId: row.id.toString(),
    ownerId: row.ownerId?.toString() ?? null,
    ownerName: row.ownerName ?? null,
    isMine,
    canClaim,
    blockedReason,
    statusLabel,
  };
}
