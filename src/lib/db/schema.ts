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

// W5 RBAC: ≤3 层硬约束 CHECK (ADR-0006 合规边界 / 《禁止传销条例》)
export const franchiseeMaxDepthCheck = sql`
  ALTER TABLE franchisee ADD CONSTRAINT franchisee_max_depth_3
  CHECK (placement_depth <= 3)
`;

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
    role: userRoleEnum("role").notNull().default("sales"),
    isActive: boolean("is_active").notNull().default(true),
    // F1: 1:1 绑 franchisee (nullable, 应用层强制非空)
    franchiseeId: bigint("franchisee_id", { mode: "bigint" }),
    // W5 RBAC: 默认门店 (sales 角色专用, manager 看本店)
    defaultStoreId: bigint("default_store_id", { mode: "bigint" }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .default(sql`NOW()`),
  },
  (table) => ({
    phoneHashUnique: uniqueIndex("idx_user_phone_hash").on(table.phoneHash),
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

    phoneEncrypted: text("phone_encrypted").notNull(),
    phoneHash: text("phone_hash").notNull(),

    healthTagsEncrypted: text("health_tags_encrypted"),
    diseaseHistoryEncrypted: text("disease_history_encrypted"),
    notesEncrypted: text("notes_encrypted"),

    // W5 RBAC: store_id (CHARTER §3.6 行级过滤)
    storeId: bigint("store_id", { mode: "bigint" }),

    // 客户图谱: 客户推荐人 (老带新关系, 客户页图谱视图数据源)
    // nullable: 存量客户 / 首次到店客户无推荐人, 显示为根/孤儿节点
    // 边界: 不能跟 customer 形成环 (DB 层无 FK self-ref 是为简化;
    //   应用层 + service 层校验避免 referrerId == id 闭环, see customer service)
    referrerId: bigint("referrer_id", { mode: "bigint" }),

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
    categoryIdx: uniqueIndex("idx_knowledge_category").on(table.category),
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