# 数据模型详细文档

> 与 [ADR-0002](./adr/0002-data-model.md) 配套,本文档展示完整的 Drizzle schema 草案 + 字段加密示例。

## 设计原则 (复述)

1. **结构化优先于文本** — 养生记录必须分字段,AI 才能用
2. **字段级加密敏感数据** — 健康状态 / 疾病史 / 联系方式 走 pgcrypto
3. **多门店预留** — store / staff 表从 Day 1 存在,即使单店
5. **审计日志** — 任何敏感表写操作都要记录

## 完整实体列表

### 核心实体

| 表 | 说明 | Phase |
|---|---|---|
| `customer` | 客户主表 | 1 |
| `wellness_record` | 养生记录(核心) | 1 |
| `wellness_record_body_part` | 记录-部位中间表 | 1 |
| `wellness_record_product` | 记录-耗材中间表 | 1 |
| `interaction` | 联系记录 | 1 |
| `follow_up_task` | 跟进任务 | 1 |
| `user` / `session` | 用户与登录 | 1 |
| `audit_log` | 审计日志(触发器维护) | 1 |

### 字典表

| 表 | 说明 | Phase |
|---|---|---|
| `body_part` | 身体部位字典(肩颈 / 腰部 / 膝盖 等) | 1 |
| `service_item` | 服务项目字典(肩颈经络 / 艾灸 / 拔罐 等) | 1 |
| `product` | 耗材字典(精油 / 热敷包 / 艾条 等) | 1 |
| `store` | 门店(单店也建,预留) | 2 |
| `staff` | 员工 / 技师 | 1(但 store Phase 2 启用) |

## Drizzle Schema 草案

> 完整代码将在 W2 实施时写在 `src/lib/db/schema.ts`

```typescript
// src/lib/db/schema.ts (草案)

import {
  pgTable, bigserial, text, integer, timestamp, boolean,
  jsonb, date, numeric, inet, pgEnum, primaryKey, index, unique
} from 'drizzle-orm/pg-core';
import { pgTable } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

// ========== Enums ==========
export const genderEnum = pgEnum('gender', ['M', 'F', 'U']);
export const interactionTypeEnum = pgEnum('interaction_type', [
  'phone', 'wechat', 'visit', 'holiday_greeting', 'other'
]);
export const taskStatusEnum = pgEnum('task_status', ['pending', 'done', 'cancelled']);
export const userRoleEnum = pgEnum('user_role', ['admin', 'manager', 'sales']);

// ========== Customer ==========
export const customer = pgTable('customer', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),

  name: text('name').notNull(),
  phoneEncrypted: text('phone_encrypted').notNull(),   // pgp_sym_encrypt 后的 base64
  phoneHash: text('phone_hash').notNull().unique(),    // md5(plaintext) 用于查询

  gender: genderEnum('gender'),
  birthYear: integer('birth_year'),

  healthTagsEncrypted: text('health_tags_encrypted'),        // 加密 JSONB
  diseaseHistoryEncrypted: text('disease_history_encrypted'),// 加密文本
  notesEncrypted: text('notes_encrypted'),                   // 加密文本

  createdBy: bigserial('created_by', { mode: 'bigint' })
    .references(() => user.id)
    .notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
}, (t) => ({
  phoneHashIdx: index('idx_customer_phone_hash').on(t.phoneHash),
  deletedAtIdx: index('idx_customer_deleted_at').on(t.deletedAt),
}));

// ========== Wellness Record ==========
export const wellnessRecord = pgTable('wellness_record', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  customerId: bigserial('customer_id', { mode: 'bigint' })
    .references(() => customer.id)
    .notNull(),

  serviceDate: date('service_date').notNull(),
  storeId: bigserial('store_id', { mode: 'bigint' }).references(() => store.id),
  staffId: bigserial('staff_id', { mode: 'bigint' }).references(() => staff.id),
  serviceItemId: bigserial('service_item_id', { mode: 'bigint' })
    .references(() => serviceItem.id)
    .notNull(),

  preConditionEncrypted: text('pre_condition_encrypted').notNull(),   // JSONB 加密
  postConditionEncrypted: text('post_condition_encrypted').notNull(),// JSONB 加密
  processNoteEncrypted: text('process_note_encrypted'),              // 文本加密
  customerFeedbackEncrypted: text('customer_feedback_encrypted'),   // 文本加密

  photos: jsonb('photos').$type<string[]>().default([]),              // 图片路径列表
  nextAdviceDate: date('next_advice_date'),                          // AI / 人工建议

  createdBy: bigserial('created_by', { mode: 'bigint' })
    .references(() => user.id)
    .notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  customerDateIdx: index('idx_wellness_customer').on(t.customerId, t.serviceDate.desc()),
  serviceDateIdx: index('idx_wellness_service_date').on(t.serviceDate),
  staffDateIdx: index('idx_wellness_staff').on(t.staffId, t.serviceDate),
}));

// ========== Body Part ==========
export const bodyPart = pgTable('body_part', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  name: text('name').notNull().unique(),        // 肩颈 / 腰部 / 膝盖 ...
  description: text('description'),
});

// ========== Wellness Record - Body Part (中间表) ==========
export const wellnessRecordBodyPart = pgTable('wellness_record_body_part', {
  wellnessRecordId: bigserial('wellness_record_id', { mode: 'bigint' })
    .references(() => wellnessRecord.id, { onDelete: 'cascade' })
    .notNull(),
  bodyPartId: bigserial('body_part_id', { mode: 'bigint' })
    .references(() => bodyPart.id)
    .notNull(),
}, (t) => ({
  pk: primaryKey({ columns: [t.wellnessRecordId, t.bodyPartId] }),
}));

// ========== Service Item ==========
export const serviceItem = pgTable('service_item', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  name: text('name').notNull().unique(),         // 肩颈经络 / 艾灸 / 拔罐 ...
  durationMinutes: integer('duration_minutes'),
  defaultPriceCents: integer('default_price_cents'),
  description: text('description'),
});

// ========== Product ==========
export const product = pgTable('product', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  name: text('name').notNull().unique(),         // 艾草精油 / 热敷包 / 艾条 ...
  unit: text('unit'),                            // ml / 个 / 根
  description: text('description'),
});

// ========== Wellness Record - Product (中间表) ==========
export const wellnessRecordProduct = pgTable('wellness_record_product', {
  wellnessRecordId: bigserial('wellness_record_id', { mode: 'bigint' })
    .references(() => wellnessRecord.id, { onDelete: 'cascade' })
    .notNull(),
  productId: bigserial('product_id', { mode: 'bigint' })
    .references(() => product.id)
    .notNull(),
  quantity: numeric('quantity', { precision: 10, scale: 2 }),
}, (t) => ({
  pk: primaryKey({ columns: [t.wellnessRecordId, t.productId] }),
}));

// ========== Interaction ==========
export const interaction = pgTable('interaction', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  customerId: bigserial('customer_id', { mode: 'bigint' })
    .references(() => customer.id)
    .notNull(),
  type: interactionTypeEnum('type').notNull(),
  summaryEncrypted: text('summary_encrypted'),
  followUpAt: timestamp('follow_up_at', { withTimezone: true }),

  createdBy: bigserial('created_by', { mode: 'bigint' })
    .references(() => user.id)
    .notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  customerIdx: index('idx_interaction_customer').on(t.customerId, t.createdAt.desc()),
}));

// ========== Follow-up Task ==========
export const followUpTask = pgTable('follow_up_task', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  customerId: bigserial('customer_id', { mode: 'bigint' })
    .references(() => customer.id)
    .notNull(),
  dueAt: timestamp('due_at', { withTimezone: true }).notNull(),
  reason: text('reason').notNull(),
  aiSuggestionEncrypted: text('ai_suggestion_encrypted'),

  status: taskStatusEnum('status').notNull().default('pending'),
  completedAt: timestamp('completed_at', { withTimezone: true }),
  completedNotesEncrypted: text('completed_notes_encrypted'),

  assignedTo: bigserial('assigned_to', { mode: 'bigint' })
    .references(() => user.id),
  createdBy: bigserial('created_by', { mode: 'bigint' })
    .references(() => user.id),

  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  dueIdx: index('idx_followup_due').on(t.dueAt).where(sql`status = 'pending'`),
  assignedIdx: index('idx_followup_assigned').on(t.assignedTo, t.status),
}));

// ========== Store (Phase 2 启用,但 Day 1 建表) ==========
export const store = pgTable('store', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  name: text('name').notNull(),
  address: text('address'),
  phoneEncrypted: text('phone_encrypted'),
  isActive: boolean('is_active').default(true),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
});

// ========== Staff ==========
export const staff = pgTable('staff', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  userId: bigserial('user_id', { mode: 'bigint' })
    .references(() => user.id)
    .unique(),
  displayName: text('display_name').notNull(),
  storeId: bigserial('store_id', { mode: 'bigint' })
    .references(() => store.id),
  specialties: jsonb('specialties').$type<string[]>().default([]),  // 擅长项目
  isActive: boolean('is_active').default(true),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
});

// ========== User ==========
export const user = pgTable('user', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  name: text('name').notNull(),
  phoneEncrypted: text('phone_encrypted').notNull(),
  phoneHash: text('phone_hash').notNull().unique(),
  role: userRoleEnum('role').notNull().default('sales'),
  isActive: boolean('is_active').default(true),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
});

// ========== Audit Log ==========
export const auditLog = pgTable('audit_log', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  tableName: text('table_name').notNull(),
  recordId: bigserial('record_id', { mode: 'bigint' }).notNull(),
  operation: text('operation').notNull(),
  userId: bigserial('user_id', { mode: 'bigint' })
    .references(() => user.id),
  changedFields: jsonb('changed_fields'),
  ipAddress: inet('ip_address'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  tableRecordIdx: index('idx_audit_table_record').on(t.tableName, t.recordId),
  userIdx: index('idx_audit_user').on(t.userId, t.createdAt.desc()),
}));
```

## 字段加密示例

### 加密 / 解密封装

```typescript
// src/lib/crypto/field.ts

import { sql } from 'drizzle-orm';
import { db } from '@/lib/db';
import crypto from 'node:crypto';

const ALGORITHM = 'aes-256-cbc';
const KEY = Buffer.from(process.env.PGCRYPTO_KEY!, 'hex');  // 32 bytes

export function encryptField(plaintext: string): string {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, KEY, iv);
  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  // iv + ciphertext (base64)
  return Buffer.concat([iv, encrypted]).toString('base64');
}

export function decryptField(ciphertext: string): string {
  const data = Buffer.from(ciphertext, 'base64');
  const iv = data.subarray(0, 16);
  const cipherText = data.subarray(16);
  const decipher = crypto.createDecipheriv(ALGORITHM, KEY, iv);
  return Buffer.concat([
    decipher.update(cipherText),
    decipher.final(),
  ]).toString('utf8');
}

export function hashForLookup(plaintext: string): string {
  return crypto.createHash('md5').update(plaintext).digest('hex');
}

// ========== 使用示例 ==========

// 写入
await db.insert(customer).values({
  name: '张女士',
  phoneEncrypted: encryptField('13800138000'),
  phoneHash: hashForLookup('13800138000'),
  healthTagsEncrypted: encryptField(JSON.stringify(['肩颈', '睡眠差'])),
  // ...
});

// 查询
const found = await db.query.customer.findFirst({
  where: (c, { eq }) => eq(c.phoneHash, hashForLookup('13800138000')),
});

// 读取时解密
if (found?.phoneEncrypted) {
  const phone = decryptField(found.phoneEncrypted);
}
```

### 为什么应用层加密而不是纯 SQL pgcrypto

- ✅ 应用层密钥不传到 DB,数据库管理员无法解密
- ✅ 应用层加密后,即使是 DBA 也看不到明文
- ✅ 备份文件加密,即使泄露也安全
- ⚠️ 缺点:无法用 SQL 直接做 LIKE/正则(所以有 phone_hash)

**对比 SQL pgcrypto** (`pgp_sym_encrypt`):
- 密钥传 DB,DB 实例泄露 = 数据泄露
- 优点:纯 SQL,JOIN / 聚合不增加应用层代码

**本项目选择**:应用层 AES-256-CBC + pgcrypto 只用作"额外一层"。

## 索引策略

```sql
-- 加密列无法直接 LIKE,只建 hash 索引
CREATE INDEX idx_customer_phone_hash ON customer(phone_hash);

-- 明文时间列建范围索引
CREATE INDEX idx_wellness_service_date ON wellness_record(service_date);
CREATE INDEX idx_followup_due ON follow_up_task(due_at) WHERE status = 'pending';
```

## 软删除 vs 硬删除

养生记录 / 客户都走**软删除**(`deleted_at`):

- 客户硬删除 = 关联的养生记录全部孤儿
- 软删除 = 保留历史数据,合规兜底
- 后续 GDPR / 个保法 "被遗忘权" → 走应用层清理(同时软删 + 清空 PII)

## 数据迁移

`drizzle-kit` 自动生成迁移文件:

```bash
pnpm db:generate    # 生成迁移
pnpm db:migrate     # 应用迁移
pnpm db:studio      # 打开 Drizzle Studio (Web GUI)
```

迁移流程:
1. 改 `schema.ts`
2. `pnpm db:generate` 自动生成 SQL
3. 主人 review SQL 文件
4. `pnpm db:migrate` 应用

## 字典数据 seed (W2 一次性导入)

```typescript
// src/lib/db/seed.ts
import { bodyPart, product, serviceItem } from './schema';

const initialBodyParts = [
  { name: '肩颈' }, { name: '腰部' }, { name: '膝盖' },
  { name: '头部' }, { name: '背部' }, { name: '腿部' },
  { name: '腹部' }, { name: '足部' }, { name: '手臂' },
];

const initialServices = [
  { name: '肩颈经络理疗', durationMinutes: 60 },
  { name: '艾灸调理', durationMinutes: 90 },
  { name: '拔罐', durationMinutes: 30 },
  { name: '推拿按摩', durationMinutes: 60 },
  { name: '足疗', durationMinutes: 45 },
  { name: '刮痧', durationMinutes: 45 },
];

const initialProducts = [
  { name: '艾草精油', unit: 'ml' },
  { name: '生姜精油', unit: 'ml' },
  { name: '热敷包', unit: '个' },
  { name: '艾条', unit: '根' },
  { name: '拔罐器', unit: '套' },
];
```

## 下一步

- W2: 实际写 Drizzle schema 文件
- W2: 写加密 / 解密封装
- W2: 写迁移 + seed 脚本
- W3: 写业务层 CRUD (使用 schema + 加密)