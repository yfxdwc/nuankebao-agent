// @ts-nocheck  // drizzle-orm 类型推断在 strict 模式有 known issue, 暂时跳过
import {
  pgTable,
  pgEnum,
  bigserial,
  bigint,
  text,
  integer,
  timestamp,
  date,
  boolean,
  numeric,
  jsonb,
  inet,
  uniqueIndex,
  index,
  primaryKey,
} from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

// ============================================
// 枚举
// ============================================

export const genderEnum = pgEnum("gender", ["M", "F", "U"]);
export const interactionTypeEnum = pgEnum("interaction_type", [
  "phone",
  "wechat",
  "visit",
  "holiday_greeting",
  "other",
]);
export const taskStatusEnum = pgEnum("task_status", [
  "pending",
  "done",
  "cancelled",
]);
export const userRoleEnum = pgEnum("user_role", ["admin", "manager", "sales"]);

// ============================================
// 字典表
// ============================================

export const bodyPart = pgTable("body_part", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  name: text("name").notNull().unique(),
  description: text("description"),
});

export const serviceItem = pgTable("service_item", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  name: text("name").notNull().unique(),
  durationMinutes: integer("duration_minutes"),
  defaultPriceCents: integer("default_price_cents"),
  description: text("description"),
});

export const product = pgTable("product", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  name: text("name").notNull().unique(),
  unit: text("unit"),
  description: text("description"),
});

// ============================================
// 加盟商 (F1 + ADR-0006)
// ============================================
// 纯展示, 不算钱 / 不算业绩 / 不算提成
// 二叉树结构: referrer + placement_side (left/right) + placement_path
// 边界: 见 ADR-0006 边界 1 (系统永不做任何金额字段)

export const franchisee = pgTable(
  "franchisee",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    name: text("name").notNull(),
    phoneEncrypted: text("phone_encrypted").notNull(),
    phoneHash: text("phone_hash").notNull(),

    // 二叉树结构
    referrerId: bigint("referrer_id", { mode: "bigint" }),
    placementSide: text("placement_side", { enum: ["left", "right"] }),
    placementPath: text("placement_path").notNull().default(""),
    placementDepth: integer("placement_depth").notNull().default(0),

    // 元信息
    joinedAt: timestamp("joined_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    isActive: boolean("is_active").notNull().default(true),
    notesEncrypted: text("notes_encrypted"),

    // RBAC 字段 (CHARTER §3.6 预留 hook, W5 才实际使用)
    createdBy: bigint("created_by", { mode: "bigint" }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => ({
    phoneHashUnique: uniqueIndex("idx_franchisee_phone_hash").on(
      table.phoneHash
    ),
    referrerIdx: index("idx_franchisee_referrer").on(table.referrerId),
    referrerSideIdx: index("idx_franchisee_referrer_side").on(
      table.referrerId,
      table.placementSide
    ),
    pathIdx: index("idx_franchisee_path").on(table.placementPath),
    deletedAtIdx: index("idx_franchisee_deleted_at").on(table.deletedAt),
  })
);

// ADR-0010: ≤4 层硬约束 (主人 2026-09-16 override)
//   历史: ADR-0006 设 ≤3 层 (《禁止传销条例》红线) → ADR-0010 放宽到 ≤4 (dev/test seed data)
//   注: schema.ts 的 sql raw block 当前未被 migrate 应用, 约束只在 src/lib/db/queries/franchisee-tree.ts:46 service 层 enforce
//       所以本 sql block 实际是「文档 / 漂移预防」作用, 真改要去改 service. 真上 prod 时要么:
//         (a) 把这段 sql 真接到 drizzle migrate 加 CHECK constraint (防御性)
//         (b) 删掉这段 (避免跟 service drift, 靠单层 service 兜底)
export const franchiseeMaxDepthCheck = sql`
  ALTER TABLE franchisee ADD CONSTRAINT franchisee_max_depth_4
  CHECK (placement_depth <= 4)
`;

// ============================================
// 加盟落位「三方确认」工作流 (主人 2026-09-18 拍, 见 docs/placement-confirmation-design.md)
// ============================================
// 规则:
//   - 新设节点 / 移动节点位置 → 必须三方确认: 设置者本人 + 新加盟商本人 + 新位置父节点加盟商
//     (父节点 == 设置者 → 只需双方)
//   - 确认载体 = App 内「待我确认」(Q1/Q2 拍板: 都走 in_app; 没账号的人先注册登录再确认)
//   - 超时 72h 自动失效 (Q3); 待确认期间点位**预占** (Q4, 部分唯一索引兜底)
//   - 移动: 原位置父节点**不需要**确认, 推荐人(referrer_id)不变 (Q5)
//   - 权限: 只能在**自己 placement 子树内**的点位发起 (Q7)
//   - 历史节点回填「已确认」记录 (Q6, backfilled=true)
export const franchisePlacementRequest = pgTable(
  "franchise_placement_request",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    // create 新设 / move 改位置 / unjoin 解除加盟 (主人 2026-09-18 拍)
    // 主人 2026-09-19 拍: 「移动到其他点位」功能下线 (点位不能直接移动, 必须先解除再重新加盟)
    //   → kind 不再产生 'move'; 列类型保留 text (DB 无 enum 约束, 存量无 move 行)
    kind: text("kind", { enum: ["create", "unjoin"] }).notNull(),
    status: text("status", {
      enum: ["pending", "executed", "rejected", "expired", "cancelled"],
    })
      .notNull()
      .default("pending"),

    // 发起人 (设置者)
    initiatorFid: bigint("initiator_fid", { mode: "bigint" }).notNull(),
    initiatorUserId: bigint("initiator_user_id", { mode: "bigint" }).notNull(),

    // kind=create: 新加盟商资料 (三方确认通过后才真正 insert franchisee)
    newName: text("new_name"),
    newPhoneEncrypted: text("new_phone_encrypted"),
    newPhoneHash: text("new_phone_hash"),
    newNotesEncrypted: text("new_notes_encrypted"),

    // kind=move / unjoin: 被移动 / 被解除的节点
    moveFid: bigint("move_fid", { mode: "bigint" }),

    // 目标点位 = 父节点 + 左/右
    targetParentFid: bigint("target_parent_fid", { mode: "bigint" }).notNull(),
    targetSide: text("target_side", { enum: ["left", "right"] }).notNull(),

    // 执行结果: create → 新 franchisee.id; move → moveFid
    resultFid: bigint("result_fid", { mode: "bigint" }),

    // Q6 回填的历史数据 (豁免真实三方, 只留痕)
    backfilled: boolean("backfilled").notNull().default(false),

    // Q3: 72h 超时
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    executedAt: timestamp("executed_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    // Q4 预占: 同一个 (父节点, 左/右) 只能有一个 pending —— DB 层兜底防并发抢位
    pendingSlotUnique: uniqueIndex("idx_placement_pending_slot")
      .on(table.targetParentFid, table.targetSide)
      .where(sql`status = 'pending'`),
    initiatorIdx: index("idx_placement_initiator").on(table.initiatorFid),
    statusIdx: index("idx_placement_status").on(table.status, table.expiresAt),
    moveFidIdx: index("idx_placement_move_fid").on(table.moveFid),
  })
);

export const franchisePlacementConfirm = pgTable(
  "franchise_placement_confirm",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    requestId: bigint("request_id", { mode: "bigint" }).notNull(),
    confirmerRole: text("confirmer_role", {
      enum: ["initiator", "new_franchisee", "target_parent"],
    }).notNull(),
    /** 对应 franchisee.id (回填/无账号时可能为 null) */
    confirmerFid: bigint("confirmer_fid", { mode: "bigint" }),
    /** 实际点确认的账号 (in_app 确认时必有) */
    confirmerUserId: bigint("confirmer_user_id", { mode: "bigint" }),
    decision: text("decision", { enum: ["approve", "reject"] }).notNull(),
    /** in_app = 账号在 App 里点的; backfill = 上线前回填; admin = 管理员单免确认自动落位 */
    verifiedBy: text("verified_by", { enum: ["in_app", "backfill", "admin"] })
      .notNull()
      .default("in_app"),
    decidedAt: timestamp("decided_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    requestRoleUnique: uniqueIndex("idx_placement_confirm_request_role").on(
      table.requestId,
      table.confirmerRole
    ),
  })
);

export type FranchisePlacementRequest =
  typeof franchisePlacementRequest.$inferSelect;
export type NewFranchisePlacementRequest =
  typeof franchisePlacementRequest.$inferInsert;
export type FranchisePlacementConfirm =
  typeof franchisePlacementConfirm.$inferSelect;
export type PlacementRequestStatusType =
  | "pending"
  | "executed"
  | "rejected"
  | "expired"
  | "cancelled";
export type PlacementConfirmerRoleType =
  | "initiator"
  | "new_franchisee"
  | "target_parent";

export type Franchisee = typeof franchisee.$inferSelect;
export type NewFranchisee = typeof franchisee.$inferInsert;
export type PlacementSide = "left" | "right";

// 用户
// ============================================
// 每个 user 都是加盟商 (1:1 强约束, 见 ADR-0006 + Plan F1)
// 决策 4A: role enum 保留 (App 端 sales only, web admin 才用 admin/manager)
// 注意: franchiseeId nullable (CHARTER §3.5 兼容, DB 层 NOT NULL 不可行)
//       应用层 + service + Zod + cron 4 重兜底

export const user = pgTable(
  "user",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    name: text("name").notNull(),
    phoneEncrypted: text("phone_encrypted").notNull(),
    phoneHash: text("phone_hash").notNull(),
    // 账号密码登录 (2026-09-19 P2; 邀请制 — 不开放自助注册)
    //   username: 登录名 (如 admin); sales 默认用手机号登录 (phoneHash 查询)
    //   passwordHash: scrypt$cost$salt$hash (src/lib/auth/password.ts)
    // 两列可空 = 兼容 0011 之前的历史行 (CHARTER §3.5 向后兼容)
    username: text("username"),
    passwordHash: text("password_hash"),
    role: userRoleEnum("role").notNull().default("sales"),
    isActive: boolean("is_active").notNull().default(true),
    // F1: 1:1 绑 franchisee (nullable, 应用层强制非空)
    franchiseeId: bigint("franchisee_id", { mode: "bigint" }),
    // W5 RBAC: 默认门店 (sales 角色专用, manager 看本店)
    defaultStoreId: bigint("default_store_id", { mode: "bigint" }),
    // 「我的」页自定义头像 (2026-09-18 主人要: 支持上传 + 候选头像)
    //   null                = 默认 (画姓名首字)
    //   'preset:<id>'       = 内置候选头像 (前端本地画, 不占服务器存储)
    //   '/uploads/xxx.jpg'  = 自己上传的照片 (走 POST /api/photos)
    // 白名单 / 格式校验在 src/lib/avatar.ts; 自改走 PATCH /api/me
    // (user 表已挂 user_audit 触发器 → 改头像也进审计日志)
    avatarUrl: text("avatar_url"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    phoneHashUnique: uniqueIndex("idx_user_phone_hash").on(table.phoneHash),
    usernameUnique: uniqueIndex("idx_user_username").on(table.username),
    franchiseeIdx: index("idx_user_franchisee").on(table.franchiseeId),
    defaultStoreIdx: index("idx_user_default_store").on(table.defaultStoreId),
  })
);

export type User = typeof user.$inferSelect;
export type NewUser = typeof user.$inferInsert;
export type UserRole = (typeof userRoleEnum.enumValues)[number];

// ============================================
// 门店 + 员工
// ============================================

export const store = pgTable("store", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  name: text("name").notNull(),
  address: text("address"),
  phoneEncrypted: text("phone_encrypted"),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .default(sql`NOW()`),
});

export const staff = pgTable("staff", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  userId: bigint("user_id", { mode: "bigint" }),
  displayName: text("display_name").notNull(),
  storeId: bigint("store_id", { mode: "bigint" }),
  specialties: jsonb("specialties").$type<string[]>().default([]),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .default(sql`NOW()`),
});

// ============================================
// 客户
// ============================================

export const customer = pgTable(
  "customer",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),

    name: text("name").notNull(),
    gender: genderEnum("gender"),
    birthYear: integer("birth_year"),
    // 生日细化 (主人 2026-09-18 拍): 年/月/日 都可缺 (不知道就留空)
    //   例: 只知道属相/年份 → 只有 birth_year; 知道农历八月十五 → month=8 day=15 + lunar
    birthMonth: integer("birth_month"),
    birthDay: integer("birth_day"),
    // 历法: 'solar' 阳历 (默认) / 'lunar' 农历
    birthCalendar: text("birth_calendar", { enum: ["solar", "lunar"] })
      .notNull()
      .default("solar"),
    // 生日提醒强度 (天数: 7 / 3 / 0=当天); null = 不提醒
    //   业务规则: 月+日 都填了 = 开启提醒 (前端默认给 3 天前); 清空月/日 → 自动置 null
    birthdayRemindDays: integer("birthday_remind_days"),

    phoneEncrypted: text("phone_encrypted").notNull(),
    phoneHash: text("phone_hash").notNull(),

    healthTagsEncrypted: text("health_tags_encrypted"),
    diseaseHistoryEncrypted: text("disease_history_encrypted"),
    // 过敏史 (主人 2026-09-18 新增; 与既往病史分开: 过敏关系到能不能用某些药/精油)
    allergyHistoryEncrypted: text("allergy_history_encrypted"),
    notesEncrypted: text("notes_encrypted"),

    // W5 RBAC: store_id (CHARTER §3.6 行级过滤)
    storeId: bigint("store_id", { mode: "bigint" }),

    // 客户图谱: 客户推荐人 (老带新关系, 客户页图谱视图数据源)
    // nullable: 存量客户 / 首次到店客户无推荐人, 显示为根/孤儿节点
    // 边界: 不能跟 customer 形成环 (DB 层无 FK self-ref 是为简化;
    //   应用层 + service 层校验避免 referrerId == id 闭环, see customer service)
    referrerId: bigint("referrer_id", { mode: "bigint" }),

    // 客户类型 (混合判定, 主人 2026-09-18 拍):
    //   - 加盟  franchisee (派生: franchisee 表存在同手机号 hash 记录)
    //   - 种子  is_seed=true (显式勾选, 潜在客户开关)
    //   - 普通  其余 (默认, 不存字段)
    // 优先级: 加盟 > 种子 > 普通 (见 queries/customer.ts resolveCustomerType)
    // 客户头像 (主人 2026-09-18 拍: 详情页头像右下角相机图标可设)
    //   取值约定与 user.avatar_url 完全一致 (src/lib/avatar.ts 白名单):
    //     null            → 默认: 姓名首字
    //     'preset:<id>'   → 内置候选 (前端本地画, 不占存储)
    //     '/uploads/x.jpg'→ 自己上传 (POST /api/photos 产物)
    avatar: text("avatar"),

    isSeed: boolean("is_seed").notNull().default(false),

    createdBy: bigint("created_by", { mode: "bigint" }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => ({
    phoneHashUnique: uniqueIndex("idx_customer_phone_hash").on(
      table.phoneHash
    ),
    deletedAtIdx: index("idx_customer_deleted_at").on(table.deletedAt),
    // W5 RBAC: store_id 索引 (供 middleware 行级过滤用)
    storeIdx: index("idx_customer_store").on(table.storeId),
    // 客户图谱: 推荐人索引 (查"我推荐了谁"用)
    referrerIdx: index("idx_customer_referrer").on(table.referrerId),
  })
);

export type Customer = typeof customer.$inferSelect;
export type NewCustomer = typeof customer.$inferInsert;

// W5 RBAC: store-staff 多对多表
export const storeStaff = pgTable(
  "store_staff",
  {
    storeId: bigint("store_id", { mode: "bigint" }).notNull(),
    staffId: bigint("staff_id", { mode: "bigint" }).notNull(),
    isManager: boolean("is_manager").notNull().default(false),
    joinedAt: timestamp("joined_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    pk: primaryKey({ columns: [table.storeId, table.staffId] }),
    storeIdx: index("idx_store_staff_store").on(table.storeId),
    staffIdx: index("idx_store_staff_staff").on(table.staffId),
  })
);

export type StoreStaff = typeof storeStaff.$inferSelect;
export type NewStoreStaff = typeof storeStaff.$inferInsert;

// ============================================
// 养生记录
// ============================================

export const wellnessRecord = pgTable(
  "wellness_record",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    customerId: bigint("customer_id", { mode: "bigint" }).notNull(),

    serviceDate: date("service_date").notNull(),
    storeId: bigint("store_id", { mode: "bigint" }),
    staffId: bigint("staff_id", { mode: "bigint" }),
    serviceItemId: bigint("service_item_id", { mode: "bigint" }).notNull(),

    preConditionEncrypted: text("pre_condition_encrypted").notNull(),
    postConditionEncrypted: text("post_condition_encrypted").notNull(),
    processNoteEncrypted: text("process_note_encrypted"),
    customerFeedbackEncrypted: text("customer_feedback_encrypted"),

    photos: jsonb("photos").$type<string[]>().default([]),
    nextAdviceDate: date("next_advice_date"),

    createdBy: bigint("created_by", { mode: "bigint" }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    customerDateIdx: index("idx_wellness_customer").on(
      table.customerId,
      table.serviceDate.desc()
    ),
    serviceDateIdx: index("idx_wellness_service_date").on(table.serviceDate),
    staffDateIdx: index("idx_wellness_staff").on(
      table.staffId,
      table.serviceDate
    ),
  })
);

export type WellnessRecord = typeof wellnessRecord.$inferSelect;
export type NewWellnessRecord = typeof wellnessRecord.$inferInsert;

// 中间表: 养生记录 - 身体部位
export const wellnessRecordBodyPart = pgTable(
  "wellness_record_body_part",
  {
    wellnessRecordId: bigint("wellness_record_id", { mode: "bigint" }).notNull(),
    bodyPartId: bigint("body_part_id", { mode: "bigint" }).notNull(),
  },
  (table) => ({
    pk: primaryKey({
      columns: [table.wellnessRecordId, table.bodyPartId],
    }),
  })
);

// 中间表: 养生记录 - 耗材
export const wellnessRecordProduct = pgTable(
  "wellness_record_product",
  {
    wellnessRecordId: bigint("wellness_record_id", { mode: "bigint" }).notNull(),
    productId: bigint("product_id", { mode: "bigint" }).notNull(),
    quantity: numeric("quantity", { precision: 10, scale: 2 }),
  },
  (table) => ({
    pk: primaryKey({
      columns: [table.wellnessRecordId, table.productId],
    }),
  })
);

// ============================================
// 联系记录
// ============================================

export const interaction = pgTable(
  "interaction",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    customerId: bigint("customer_id", { mode: "bigint" }).notNull(),
    type: interactionTypeEnum("type").notNull(),
    summaryEncrypted: text("summary_encrypted"),
    followUpAt: timestamp("follow_up_at", { withTimezone: true }),

    createdBy: bigint("created_by", { mode: "bigint" }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    customerIdx: index("idx_interaction_customer").on(
      table.customerId,
      table.createdAt.desc()
    ),
  })
);

export type Interaction = typeof interaction.$inferSelect;
export type NewInteraction = typeof interaction.$inferInsert;

// ============================================
// 跟进任务
// ============================================

export const followUpTask = pgTable(
  "follow_up_task",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    customerId: bigint("customer_id", { mode: "bigint" }).notNull(),
    dueAt: timestamp("due_at", { withTimezone: true }).notNull(),
    reason: text("reason").notNull(),
    aiSuggestionEncrypted: text("ai_suggestion_encrypted"),

    status: taskStatusEnum("status").notNull().default("pending"),
    completedAt: timestamp("completed_at", { withTimezone: true }),
    completedNotesEncrypted: text("completed_notes_encrypted"),

    assignedTo: bigint("assigned_to", { mode: "bigint" }),
    createdBy: bigint("created_by", { mode: "bigint" }),

    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    dueIdx: index("idx_followup_due")
      .on(table.dueAt)
      .where(sql`status = 'pending'`),
    assignedIdx: index("idx_followup_assigned").on(
      table.assignedTo,
      table.status
    ),
  })
);

export type FollowUpTask = typeof followUpTask.$inferSelect;
export type NewFollowUpTask = typeof followUpTask.$inferInsert;

// ============================================
// 养生知识库 (RAG 数据源)
// ============================================

export const knowledgeCategoryEnum = pgEnum("knowledge_category", [
  "physiotherapy",  // 理疗手法
  "wellness_tip",   // 养生建议
  "product_guide",  // 产品使用
  "customer_care",  // 客户关怀
  "seasonal",       // 季节性
]);

export const wellnessKnowledge = pgTable(
  "wellness_knowledge",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    title: text("title").notNull(),
    content: text("content").notNull(),
    category: knowledgeCategoryEnum("category").notNull(),
    tags: jsonb("tags").$type<string[]>().default([]),
    // pgvector embedding (W10 启用, 暂时 nullable)
    // embedding: vector("embedding", { dimensions: 1536 }),
    createdBy: bigint("created_by", { mode: "bigint" }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    // 普通索引 (非 unique): 同一 category 下可有多条知识
    // 历史: 由 0001_demonic_redwing 误建为 UNIQUE (schema 当时写 uniqueIndex)
    //   → 0009 migration 修正为普通索引, 与 0002_wellness_knowledge.sql 的原意一致
    //   (seed 有 10 条 / 5 个 category, unique 会让 seed 直接失败)
    categoryIdx: index("idx_knowledge_category").on(table.category),
  })
);

export type WellnessKnowledge = typeof wellnessKnowledge.$inferSelect;
export type NewWellnessKnowledge = typeof wellnessKnowledge.$inferInsert;

// ============================================
// 审计日志
// ============================================

export const auditLog = pgTable(
  "audit_log",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    tableName: text("table_name").notNull(),
    recordId: bigint("record_id", { mode: "bigint" }).notNull(),
    operation: text("operation").notNull(),
    userId: bigint("user_id", { mode: "bigint" }),
    changedFields: jsonb("changed_fields"),
    ipAddress: inet("ip_address"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    tableRecordIdx: index("idx_audit_table_record").on(
      table.tableName,
      table.recordId
    ),
  })
);

export type AuditLog = typeof auditLog.$inferSelect;
// ============================================
// 沙龙 (v0.1.5 Phase 7, 主人 2026-09-18 拍板: 完整方案)
// ============================================
// 场景: 销售员 / 公司主理的 聚会 / 沙龙 / 健康讲座 / 客户答谢会 / 团建
// 三种角色: 主理人 (salons.organizer_user_id) / 会务 (invitation.role=staff) / 受邀者 (attendee)
// 边界 (主人 2026-09-18 拍):
//   1. 受邀者可填「预计带约人数」(expected_guest_count), 主理人手动核对 (简单版, 不做全链追踪)
//   2. 受邀者允许非 app 用户 (姓名 + 手机号, 手机号走应用层加密, 与 customer/user 同口径)
//   3. 不建统一关系图谱: 沙龙内用 salon_invitation 树 + user 表; 后期用 RelationSystem 接口包装
//   4. 会务人员 = invitation(role=staff) 行 —— 不存 jsonb, 否则手机号无法加密 (AGENTS §3 红线)
//   5. 敏感字段 (手机号/留言) 一律 *_encrypted + *_hash, 与既有 customer/franchisee 一致
// ============================================

export const salonStatusEnum = pgEnum("salon_status", [
  "draft",                // 草稿 (仅主理人可见)
  "published",            // 已发布 (报名中)
  "registration_closed",  // 报名已截止
  "ongoing",              // 进行中
  "finished",             // 已结束
  "cancelled",            // 已取消
]);

export const salonRoleEnum = pgEnum("salon_role", [
  "organizer", // 主理人 (salons.organizer_user_id, 不占 invitation 行)
  "staff",     // 会务 (主持人 / 讲师 / 摄影 / 后勤 / 接待)
  "attendee",  // 受邀者
]);

export const salonInvitationStatusEnum = pgEnum("salon_invitation_status", [
  "pending",   // 待回复
  "accepted",  // 已接受
  "tentative", // 待定
  "declined",  // 已婉拒
  "waitlist",  // 候补
  "attended",  // 已到场 (主理人事后核销)
  "absent",    // 未到场
  "cancelled", // 邀请已撤销 (主理人移除)
]);

export const salonGuestStatusEnum = pgEnum("salon_guest_status", [
  "pending",
  "accepted",
  "declined",
  "attended",
  "absent",
  "cancelled",
]);

export const salonActivityTypeEnum = pgEnum("salon_activity_type", [
  "system",       // 系统消息 (自动生成: 谁接受了邀请等)
  "announcement", // 公告 (主理人 / 会务)
  "question",     // 提问
  "comment",      // 留言
]);

export const salonVisibilityEnum = pgEnum("salon_visibility", [
  "all",       // 全部参与者可见
  "staff",     // 仅主理人 + 会务
  "organizer", // 仅主理人
]);

// ---------- 沙龙主表 ----------

export const salon = pgTable(
  "salon",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),

    // 基础信息
    title: text("title").notNull(),
    subtitle: text("subtitle"),
    description: text("description"),
    coverUrl: text("cover_url"),
    themeTags: jsonb("theme_tags").$type<string[]>().default([]),

    // 主理人 = 创建者 (app 用户). 会务/受邀者走 salon_invitation
    organizerUserId: bigint("organizer_user_id", { mode: "bigint" }).notNull(),

    status: salonStatusEnum("status").notNull().default("draft"),

    // 时间 (起止 + 报名截止; timezone 存 IANA 名, 默认中国区)
    startAt: timestamp("start_at", { withTimezone: true }).notNull(),
    endAt: timestamp("end_at", { withTimezone: true }),
    registrationDeadlineAt: timestamp("registration_deadline_at", { withTimezone: true }),
    timezone: text("timezone").notNull().default("Asia/Shanghai"),

    // 地点
    locationName: text("location_name"),
    address: text("address"),
    floorRoom: text("floor_room"),      // 楼层/包间/会场名
    lat: numeric("lat", { precision: 10, scale: 7 }),
    lng: numeric("lng", { precision: 10, scale: 7 }),
    parkingInfo: text("parking_info"),  // 停车位 / 费用

    // 交通 (受邀者怎么来)
    transportPublic: text("transport_public"),  // 公交/地铁指引
    transportDriving: text("transport_driving"),// 自驾路线
    transportPickup: text("transport_pickup"),  // 接站安排 (高铁/机场)

    // 餐饮
    cateringMealType: text("catering_meal_type"), // lunch / dinner / tea / none (zod 校验)
    cateringCuisine: text("catering_cuisine"),
    cateringDietary: text("catering_dietary"),    // 过敏 / 清真 / 素食 备注
    cateringTime: text("catering_time"),          // 用餐时间 (自由文本, 例 "12:00")
    cateringPayer: text("catering_payer"),        // 谁承担 (主理人 / AA / 自费)

    // 住宿
    lodgingHotelName: text("lodging_hotel_name"),
    lodgingRoomType: text("lodging_room_type"),
    lodgingPriceCents: integer("lodging_price_cents"),
    lodgingContactName: text("lodging_contact_name"),
    // 订房联系人手机号 (敏感: 加密 + hash; 与 customer 同口径)
    lodgingContactPhoneEncrypted: text("lodging_contact_phone_encrypted"),
    lodgingDeadlineAt: timestamp("lodging_deadline_at", { withTimezone: true }),
    lodgingNote: text("lodging_note"),

    // 着装 / 费用
    dressCode: text("dress_code"),
    feeType: text("fee_type").notNull().default("free"), // free / aa / organizer_pays / paid
    feeAmountCents: integer("fee_amount_cents"),
    feeNote: text("fee_note"),

    // 人数
    capacityTotal: integer("capacity_total"),        // 总名额 (null = 不限)
    capacityReserved: integer("capacity_reserved").notNull().default(0), // 主理人/嘉宾保留

    // 日程 (时间轴) — [{ start, end, title, desc }]
    agenda: jsonb("agenda").$type<SalonAgendaItem[]>().default([]),

    // 报名表单动态字段 — [{ key, label, type, required, options }]
    // 通用 (不存敏感值本身; 受邀者的填写值存 invitation.registration_data)
    registrationFormSchema: jsonb("registration_form_schema")
      .$type<SalonFormField[]>()
      .default([]),

    // 可见性设置 — { attendeeList, staffContact }
    visibilitySettings: jsonb("visibility_settings")
      .$type<SalonVisibilitySettings>()
      .default({ attendeeList: "all", staffContact: "all" }),

    // 审计
    createdBy: bigint("created_by", { mode: "bigint" }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => ({
    organizerIdx: index("idx_salon_organizer").on(table.organizerUserId),
    startAtIdx: index("idx_salon_start_at").on(table.startAt),
    statusIdx: index("idx_salon_status").on(table.status),
    deletedAtIdx: index("idx_salon_deleted_at").on(table.deletedAt),
  })
);

/** 日程条目 (jsonb, 不加密: 不含 PII) */
export interface SalonAgendaItem {
  start?: string;   // "14:00"
  end?: string;
  title: string;
  desc?: string;
}

/** 报名表单字段定义 (jsonb) */
export interface SalonFormField {
  key: string;
  label: string;
  type: "text" | "number" | "select" | "multiselect" | "textarea" | "date" | "boolean";
  required?: boolean;
  options?: string[];
  placeholder?: string;
}

/** 可见性设置 (jsonb) */
export interface SalonVisibilitySettings {
  /** 受邀者名单 (姓名/状态) 谁能看 */
  attendeeList: "all" | "staff" | "organizer";
  /** 会务人员联系方式 谁能看 */
  staffContact: "all" | "staff";
}

export type Salon = typeof salon.$inferSelect;
export type NewSalon = typeof salon.$inferInsert;

// ---------- 邀请 (受邀者 + 会务) ----------

export const salonInvitation = pgTable(
  "salon_invitation",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    salonId: bigint("salon_id", { mode: "bigint" }).notNull(),

    // 受邀者身份:
    //   invitee_user_id 非空 = 该手机号对应 app 用户 (受邀者本人也能在 app 里看到)
    //   invitee_user_id 为空 = 非 app 用户 (仅存姓名 + 加密手机号)
    inviteeUserId: bigint("invitee_user_id", { mode: "bigint" }),
    inviteeName: text("invitee_name").notNull(),
    inviteePhoneEncrypted: text("invitee_phone_encrypted").notNull(),
    inviteePhoneHash: text("invitee_phone_hash").notNull(),

    roleInSalon: salonRoleEnum("role_in_salon").notNull().default("attendee"),
    // 会务角色 (role_in_salon='staff' 时有意义, 例: 主持人 / 讲师 / 摄影)
    staffRole: text("staff_role"),

    // 谁添加的 (主理人 / 会务; 受邀者互相邀请走 salon_guest 表)
    invitedByUserId: bigint("invited_by_user_id", { mode: "bigint" }),

    status: salonInvitationStatusEnum("status").notNull().default("pending"),

    // ★ 带约: 受邀者自己填「预计能邀约到的人数」(主人 2026-09-18 拍: 简单版)
    expectedGuestCount: integer("expected_guest_count").notNull().default(0),
    // 实际带约人数 (主理人事后核对补录, null = 未核对)
    actualGuestCount: integer("actual_guest_count"),

    respondedAt: timestamp("responded_at", { withTimezone: true }),
    // 受邀者留言 / 备注 (敏感: 加密)
    notesEncrypted: text("notes_encrypted"),
    // 报名表单填写值 (按 salon.registration_form_schema 的 key)
    registrationData: jsonb("registration_data").$type<Record<string, unknown>>(),

    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    salonIdx: index("idx_salon_invitation_salon").on(table.salonId),
    inviteeUserIdx: index("idx_salon_invitation_invitee").on(table.inviteeUserId),
    phoneHashIdx: index("idx_salon_invitation_phone_hash").on(table.inviteePhoneHash),
    // 同一沙龙内同一手机号只能有一条邀请 (防重复邀请 / 重复计数)
    salonPhoneUnique: uniqueIndex("idx_salon_invitation_salon_phone").on(
      table.salonId,
      table.inviteePhoneHash
    ),
  })
);

export type SalonInvitation = typeof salonInvitation.$inferSelect;
export type NewSalonInvitation = typeof salonInvitation.$inferInsert;

// ---------- 带约任务 (主理人 → 受邀者) ----------

export const salonQuota = pgTable(
  "salon_quota",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    salonId: bigint("salon_id", { mode: "bigint" }).notNull(),
    assignedToUserId: bigint("assigned_to_user_id", { mode: "bigint" }).notNull(),

    quotaValue: integer("quota_value").notNull(), // 需带约人数
    deadlineAt: timestamp("deadline_at", { withTimezone: true }),
    note: text("note"),

    isActive: boolean("is_active").notNull().default(true),
    createdByUserId: bigint("created_by_user_id", { mode: "bigint" }).notNull(),

    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    salonIdx: index("idx_salon_quota_salon").on(table.salonId),
    assignedIdx: index("idx_salon_quota_assigned").on(table.assignedToUserId),
    // 每人每沙龙同时只有 1 条 active 任务 (取消后可再分配)
    activeUnique: uniqueIndex("idx_salon_quota_active_unique")
      .on(table.salonId, table.assignedToUserId)
      .where(sql`is_active = true`),
  })
);

export type SalonQuota = typeof salonQuota.$inferSelect;
export type NewSalonQuota = typeof salonQuota.$inferInsert;

// ---------- 二级客人 (受邀者/主理人带来的非 app 用户) ----------

export const salonGuest = pgTable(
  "salon_guest",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    salonId: bigint("salon_id", { mode: "bigint" }).notNull(),

    // 谁带来的 (app 用户: 主理人 / 会务 / 受邀者)
    broughtByUserId: bigint("brought_by_user_id", { mode: "bigint" }).notNull(),

    name: text("name").notNull(),
    phoneEncrypted: text("phone_encrypted").notNull(),
    phoneHash: text("phone_hash").notNull(),

    // 与带约人的关系 (client / friend / family / colleague / other; zod 校验)
    relation: text("relation"),

    status: salonGuestStatusEnum("status").notNull().default("pending"),
    actualAttended: boolean("actual_attended").notNull().default(false),
    notesEncrypted: text("notes_encrypted"),

    createdBy: bigint("created_by", { mode: "bigint" }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    salonIdx: index("idx_salon_guest_salon").on(table.salonId),
    broughtByIdx: index("idx_salon_guest_brought_by").on(table.broughtByUserId),
    // 同一沙龙内同一手机号只登记一次 (防重复带约 / 重复计数)
    salonPhoneUnique: uniqueIndex("idx_salon_guest_salon_phone").on(
      table.salonId,
      table.phoneHash
    ),
  })
);

export type SalonGuest = typeof salonGuest.$inferSelect;
export type NewSalonGuest = typeof salonGuest.$inferInsert;

// ---------- 沙龙动态 (公告 / 留言 / 提问 / 系统消息) ----------

export const salonActivity = pgTable(
  "salon_activity",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    salonId: bigint("salon_id", { mode: "bigint" }).notNull(),
    authorUserId: bigint("author_user_id", { mode: "bigint" }).notNull(),

    type: salonActivityTypeEnum("type").notNull().default("comment"),
    content: text("content").notNull(),
    // 系统消息放结构化数据 (例: { event: 'rsvp', status: 'accepted', name: '张三' })
    metadata: jsonb("metadata").$type<Record<string, unknown>>(),

    visibility: salonVisibilityEnum("visibility").notNull().default("all"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    salonIdx: index("idx_salon_activity_salon").on(table.salonId, table.createdAt.desc()),
  })
);

export type SalonActivity = typeof salonActivity.$inferSelect;
export type NewSalonActivity = typeof salonActivity.$inferInsert;

// ---------- 沙龙资料 (物料 / 图文, 走 /api/photos 产出的 URL) ----------

export const salonAttachment = pgTable(
  "salon_attachment",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    salonId: bigint("salon_id", { mode: "bigint" }).notNull(),

    name: text("name").notNull(),
    fileUrl: text("file_url").notNull(),
    fileType: text("file_type").notNull().default("image"), // image / file (zod 校验)
    visibility: salonVisibilityEnum("visibility").notNull().default("all"),

    uploadedByUserId: bigint("uploaded_by_user_id", { mode: "bigint" }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    salonIdx: index("idx_salon_attachment_salon").on(table.salonId),
  })
);

export type SalonAttachment = typeof salonAttachment.$inferSelect;
export type NewSalonAttachment = typeof salonAttachment.$inferInsert;

// ============================================
// 会员付费 (S0: 会员骨架 + 推荐码; 支付表 S1 再加)
// ============================================
// ADR-0012 + docs/membership-billing-draft.md v0.2
//
// 隔离红线 (与 ADR-0006 一致, 任何 PR 违反 = 驳回):
//   1. billing_* / membership* / referral_* 表**不得**有外键指向 franchisee / customer
//      (唯一允许的交叉: membership.user_id → user.id)
//   2. 推荐奖励只能是**服务权益 (天数)**, 不可提现/转让/折现; 无二级推荐
//   3. 付费状态不得影响加盟身份/上下级/图谱/客户数据所有权
//
// 金额约定 (S1 起): 一律 integer **分**, 禁用 float/double

export const plan = pgTable(
  "plan",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    code: text("code").notNull(), // free / monthly / monthly_auto / yearly
    version: integer("version").notNull().default(1), // 价格表不可变 → 改价=新版本
    name: text("name").notNull(),
    priceCents: integer("price_cents").notNull().default(0), // 6900 / 4900
    intervalDays: integer("interval_days").notNull().default(30),
    autoRenew: boolean("auto_renew").notNull().default(false),

    /// 该档包含的 feature key 列表 (见 src/lib/billing/features.ts)
    features: jsonb("features").$type<string[]>().notNull().default([]),

    effectiveFrom: timestamp("effective_from", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    retiredAt: timestamp("retired_at", { withTimezone: true }), // 下架≠删除 (老订阅继续跑)
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    codeVersionUnique: uniqueIndex("idx_plan_code_version").on(
      table.code,
      table.version
    ),
  })
);

export type Plan = typeof plan.$inferSelect;
export type NewPlan = typeof plan.$inferInsert;

/// 会员状态 (每用户一行)
/// 设计: **不存冗余状态字段** —— 是不是会员由 member_until 派生 (`> now()`),
///       避免"状态字段与到期时间打架"这类经典 bug
export const membership = pgTable(
  "membership",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    userId: bigint("user_id", { mode: "bigint" }).notNull(),

    /// 当前生效套餐 (free 用户为 null; 到期降级 = 置 null + 保留 member_until 历史)
    planId: bigint("plan_id", { mode: "bigint" }),

    /// 权益截止时间 = **会员判定的唯一真相**
    ///   叠加规则 (顺延): member_until = max(now, member_until) + N 天
    memberUntil: timestamp("member_until", { withTimezone: true }),

    /// 自动续费签约状态 (S2; S0/S1 恒 none)
    autoRenewState: text("auto_renew_state", {
      enum: ["none", "signed", "charging", "failed", "canceled"],
    })
      .notNull()
      .default("none"),

    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    userUnique: uniqueIndex("idx_membership_user").on(table.userId),
    untilIdx: index("idx_membership_until").on(table.memberUntil),
  })
);

export type Membership = typeof membership.$inferSelect;
export type NewMembership = typeof membership.$inferInsert;

/// 权益发放流水 (送天数: 推荐 / 赠送 / 补偿 / 手工)
/// ⚠️ 不写金额 —— 避免"权益 = 现金价值"的联想 (钱的账本 S1 才建 billing_ledger)
export const entitlementGrant = pgTable(
  "entitlement_grant",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    userId: bigint("user_id", { mode: "bigint" }).notNull(),
    days: integer("days").notNull(),

    reason: text("reason", {
      enum: [
        "referral_referee", // 被推荐人: 填码得 15 天
        "referral_referrer", // 推荐人: 被推荐人成为加盟者后得 15 天
        "gift",
        "compensation",
        "manual", // 管理员手工开通/延期
      ],
    }).notNull(),

    /// 幂等键 (如 referral:12->34 / manual:admin1:20260919)
    ///   重复触发同一次发放不会重复送天数 —— 奖励发放必须有幂等, 否则回调/重试就送两次
    idempotencyKey: text("idempotency_key").notNull(),

    grantedByUserId: bigint("granted_by_user_id", { mode: "bigint" }),
    note: text("note"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    idemUnique: uniqueIndex("idx_grant_idempotency").on(table.idempotencyKey),
    userIdx: index("idx_grant_user").on(table.userId, table.createdAt.desc()),
  })
);

export type EntitlementGrant = typeof entitlementGrant.$inferSelect;
export type NewEntitlementGrant = typeof entitlementGrant.$inferInsert;

/// 推荐码 (每人固定 6 位; 注册时可选填)
/// 字符集去掉了 0/O/1/I/L 易混字符, 见 src/lib/billing/referral.ts
export const referralCode = pgTable(
  "referral_code",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    userId: bigint("user_id", { mode: "bigint" }).notNull(),
    code: text("code").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    userUnique: uniqueIndex("idx_referral_code_user").on(table.userId),
    codeUnique: uniqueIndex("idx_referral_code_code").on(table.code),
  })
);

export type ReferralCode = typeof referralCode.$inferSelect;
export type NewReferralCode = typeof referralCode.$inferInsert;

/// 推荐关系 + 发奖状态
///   反作弊: (referrer, referee) 唯一 → 一个被推荐人一生只能被推荐一次
///   D23: 推荐人侧奖励在"被推荐人成为加盟者"后才 rewarded (之前是 pending)
export const referralReward = pgTable(
  "referral_reward",
  {
    id: bigserial("id", { mode: "bigint" }).primaryKey(),
    referrerUserId: bigint("referrer_user_id", { mode: "bigint" }).notNull(),
    refereeUserId: bigint("referee_user_id", { mode: "bigint" }).notNull(),
    code: text("code").notNull(),

    status: text("status", {
      enum: ["pending", "rewarded", "rejected"],
    })
      .notNull()
      .default("pending"),
    rejectReason: text("reject_reason"),

    /// 被推荐人注册时的手机号 hash / 设备指纹 / IP —— 只用于事后反作弊审计, 不外发
    refereePhoneHash: text("referee_phone_hash"),
    refereeSignupIp: text("referee_signup_ip"),

    rewardedAt: timestamp("rewarded_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    pairUnique: uniqueIndex("idx_referral_pair").on(
      table.referrerUserId,
      table.refereeUserId
    ),
    referrerIdx: index("idx_referral_referrer").on(
      table.referrerUserId,
      table.createdAt.desc()
    ),
    statusIdx: index("idx_referral_status").on(table.status),
  })
);

export type ReferralReward = typeof referralReward.$inferSelect;
export type NewReferralReward = typeof referralReward.$inferInsert;
