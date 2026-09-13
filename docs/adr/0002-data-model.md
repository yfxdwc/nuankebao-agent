# ADR-0002: 数据模型设计

**日期**: 2026-09-03
**状态**: 已采纳
**影响范围**: 核心 schema
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §3.1 数据安全红线 + §4 域划分

## 上下文

本决策对应元宪法:
- [`CHARTER.md`](../CHARTER.md) **§2 治理原则 4** (结构化 > 自由文本) — 养生记录必须 JSONB 分字段,不准大文本
- [`CHARTER.md`](../CHARTER.md) **§3.1 数据安全红线**:
  - 敏感字段必须加密 → 7 个 `_encrypted` 列 (CHARTER §3.1 第 2 行)
  - 任何 DB 写必须审计 → `audit_log` 表 + 触发器 (CHARTER §3.1 第 3 行)
  - 后端二次校验 → 应用层 `lib/crypto/` 封装 (CHARTER §3.1 第 4 行)
- [`CHARTER.md`](../CHARTER.md) **§3.2 技术栈红线** (pgcrypto + pgvector) — 选 PostgreSQL 16 + 扩展
- [`CHARTER.md`](../CHARTER.md) **§4 域划分** — customer/wellness_record/interaction/follow_up_task 对应客户域/养生域/跟进域 4 大业务实体
- [`CHARTER.md`](../CHARTER.md) **§5.2 必须 ask_user** (DB schema 大改) — 本决策由主人 2026-09-03 拍板

---

养生行业销售人员的 CRM,核心需求:

1. **客户管理** — 客户基本档案 + 联系记录
2. **养生记录** — 结构化记录理疗(部位 / 状态 / 用料 / 效果)
3. **AI 客户维护**(Phase 2) — 客户画像 + 跟进话术

主人决策:
- **高敏感健康数据**:必须字段级加密
- **只做 CRM 不做 ERP**:不预留库存 / 财务表

## 设计原则

### 1. 结构化优先于文本

养生记录**绝不能**存成大文本框。必须分字段:

- 理疗前状态 → JSONB `{ pain_level: 8, sleep_quality: 5 }`
- 身体部位 → 多对多关联 `body_parts` 表
- 使用耗材 → 多对多关联 `products_used` 表
- 理疗后效果 → JSONB 同 pre_condition

**理由**:只有结构化,AI 才能做效果分析 / 复购预测 / 个性化话术。

### 2. 字段级加密敏感数据

走 Postgres pgcrypto 扩展,加密列:

- `customer.health_tags` (JSONB 加密)
- `customer.disease_history` (TEXT 加密)
- `customer.phone` (TEXT 加密,即使"自用"也要加密)
- `wellness_record.pre_condition` (JSONB 加密)
- `wellness_record.post_condition` (JSONB 加密)
- `wellness_record.process_note` (TEXT 加密)
- `wellness_record.customer_feedback` (TEXT 加密)

**不加密** (查询性能要求):
- `customer.id`, `customer.name` (姓名)
- `customer.gender`, `customer.birth_year`
- `wellness_record.service_date`
- `wellness_record.store_id`, `wellness_record.staff_id`

### 3. 多门店 / 多技师预留

即使现在是单门店,schema 也预留:

- `store` 表(Phase 2 启用)
- `staff` 表
- `wellness_record.store_id`, `wellness_record.staff_id` 已存在

### 4. 审计日志

任何 `INSERT / UPDATE / DELETE` 在敏感表都要写 `audit_log`:

```sql
CREATE TABLE audit_log (
  id BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  record_id BIGINT NOT NULL,
  operation TEXT NOT NULL,  -- INSERT / UPDATE / DELETE / SELECT
  user_id BIGINT,
  changed_fields JSONB,
  ip_address INET,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

## 实体关系图

```
┌─────────────┐
│   store     │ (Phase 2 启用)
└──────┬──────┘
       │
┌──────┴──────┐         ┌──────────────────┐
│   staff     │─────────│ wellness_record  │
└──────┬──────┘         └────────┬─────────┘
       │                         │
       │                         │ 1:N
       │                         ▼
       │                  ┌──────────────┐
       │                  │ body_part    │ (多选)
       │                  └──────────────┘
       │
┌──────┴──────┐         ┌──────────────────┐
│  customer   │─────────│  interaction     │
└──────┬──────┘         └──────────────────┘
       │                  ┌──────────────────┐
       └──────────────────│  follow_up_task  │
                          └──────────────────┘

┌─────────────────┐
│  service_item   │ (字典表: 肩颈经络/艾灸/拔罐 等)
└─────────────────┘

┌─────────────────┐
│   product       │ (字典表: 精油/热敷包/艾条 等)
└─────────────────┘
```

## 关键表 schema (草案)

### customer (客户)

```sql
CREATE TABLE customer (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  phone_encrypted BYTEA NOT NULL,        -- 手机号
  phone_hash TEXT UNIQUE NOT NULL,        -- 用于查询(phone_hash = md5(plaintext))
  gender TEXT CHECK (gender IN ('M', 'F', 'U')),
  birth_year INTEGER,
  health_tags_encrypted BYTEA,            -- ["肩颈", "睡眠差", "体寒"]
  disease_history_encrypted BYTEA,        -- 既往病史
  notes_encrypted BYTEA,
  created_by BIGINT NOT NULL REFERENCES "user"(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ                   -- 软删除
);

CREATE INDEX idx_customer_phone_hash ON customer(phone_hash);
CREATE INDEX idx_customer_deleted_at ON customer(deleted_at);
```

### wellness_record (养生记录) - 核心表

```sql
CREATE TABLE wellness_record (
  id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customer(id),

  service_date DATE NOT NULL,
  store_id BIGINT REFERENCES store(id),
  staff_id BIGINT REFERENCES staff(id),
  service_item_id BIGINT NOT NULL REFERENCES service_item(id),

  -- 身体部位(多选,通过中间表)
  -- process 见 wellness_record_body_part

  pre_condition_encrypted BYTEA NOT NULL, -- JSONB { pain_level, sleep_quality, ... }
  post_condition_encrypted BYTEA NOT NULL,-- JSONB 同上

  process_note_encrypted BYTEA,           -- 操作过程(可能含敏感描述)
  customer_feedback_encrypted BYTEA,

  photos TEXT[],                          -- 图片 URL 列表(图片本身存对象存储,这里存路径)

  next_advice_date DATE,                  -- AI / 人工建议的下次到店日期

  created_by BIGINT NOT NULL REFERENCES "user"(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_wellness_customer ON wellness_record(customer_id, service_date DESC);
CREATE INDEX idx_wellness_service_date ON wellness_record(service_date);
CREATE INDEX idx_wellness_staff ON wellness_record(staff_id, service_date);
```

### wellness_record_body_part (中间表)

```sql
CREATE TABLE wellness_record_body_part (
  wellness_record_id BIGINT REFERENCES wellness_record(id) ON DELETE CASCADE,
  body_part_id BIGINT REFERENCES body_part(id),
  PRIMARY KEY (wellness_record_id, body_part_id)
);
```

### wellness_record_product (中间表)

```sql
CREATE TABLE wellness_record_product (
  wellness_record_id BIGINT REFERENCES wellness_record(id) ON DELETE CASCADE,
  product_id BIGINT REFERENCES product(id),
  quantity NUMERIC(10,2),                 -- 用量
  PRIMARY KEY (wellness_record_id, product_id)
);
```

### interaction (联系记录)

```sql
CREATE TABLE interaction (
  id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customer(id),
  type TEXT NOT NULL CHECK (type IN ('phone', 'wechat', 'visit', 'holiday_greeting', 'other')),
  summary_encrypted BYTEA,                -- 联系内容(可能含敏感信息)
  follow_up_at TIMESTAMPTZ,               -- 下次跟进时间
  created_by BIGINT NOT NULL REFERENCES "user"(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_interaction_customer ON interaction(customer_id, created_at DESC);
```

### follow_up_task (跟进任务)

```sql
CREATE TABLE follow_up_task (
  id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customer(id),
  due_at TIMESTAMPTZ NOT NULL,
  reason TEXT NOT NULL,                   -- AI 建议 / 手动 / 复购周期
  ai_suggestion_encrypted BYTEA,          -- AI 建议话术(Phase 2)
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'cancelled')),
  completed_at TIMESTAMPTZ,
  completed_notes_encrypted BYTEA,
  assigned_to BIGINT REFERENCES "user"(id),
  created_by BIGINT REFERENCES "user"(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_followup_due ON follow_up_task(due_at) WHERE status = 'pending';
CREATE INDEX idx_followup_assigned ON follow_up_task(assigned_to, status);
```

### user / role (用户与权限)

```sql
CREATE TABLE "user" (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  phone_encrypted BYTEA NOT NULL,
  phone_hash TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL DEFAULT 'sales' CHECK (role IN ('admin', 'manager', 'sales')),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE session (
  -- Auth.js 自动管理
);
```

## 加密策略

### phone_hash 模式

phone 加密后无法直接 LIKE 查询,所以用 hash 索引:

```sql
-- 插入时
phone_encrypted = pgp_sym_encrypt(:plaintext, :key)
phone_hash = encode(digest(:plaintext, 'md5'), 'hex')

-- 查询时
WHERE phone_hash = encode(digest(:plaintext, 'md5'), 'hex')
```

**注意**:MD5 用于查找索引,不是为了安全(SHA-256 也行)。

### JSONB 加密

```sql
-- 存储
pre_condition_encrypted = pgp_sym_encrypt(:jsonb_text, :key)

-- 读取(应用层)
SELECT pgp_sym_decrypt(pre_condition_encrypted, :key) FROM wellness_record
```

### 密钥管理

- 密钥从环境变量读 `PGCRYPTO_KEY`
- 部署时通过 Docker secrets 注入,不进 git
- 密钥轮换:每年一次(运维 SOP)

## 审计触发器

```sql
CREATE OR REPLACE FUNCTION audit_trigger() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (table_name, record_id, operation, user_id, changed_fields)
  VALUES (
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    TG_OP,
    current_setting('app.current_user_id', true)::BIGINT,
    CASE TG_OP
      WHEN 'INSERT' THEN to_jsonb(NEW)
      WHEN 'UPDATE' THEN to_jsonb(NEW) - to_jsonb(OLD)
      WHEN 'DELETE' THEN to_jsonb(OLD)
    END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

为每个敏感表挂触发器:`customer`, `wellness_record`, `interaction`, `follow_up_task`。

## 向量检索准备 (Phase 2)

```sql
CREATE EXTENSION IF NOT EXISTS vector;

-- 客户画像 embedding(AI 生成,Phase 2)
ALTER TABLE customer ADD COLUMN profile_embedding vector(1536);

-- 养生知识库(给 AI 引用,Phase 2)
CREATE TABLE wellness_knowledge (
  id BIGSERIAL PRIMARY KEY,
  content TEXT NOT NULL,
  embedding vector(1536),
  source TEXT
);

CREATE INDEX idx_wellness_knowledge_embedding ON wellness_knowledge USING ivfflat (embedding vector_cosine_ops);
```

## 决策

采纳上述 schema。W2-W3 实施。

## 影响

- ✅ 敏感字段加密 = 数据泄露兜底
- ✅ 结构化养生记录 = AI 可用
- ✅ 审计日志 = 合规兜底
- ✅ 多门店预留 = 后期扩 SaaS 无 schema 迁移
- ⚠️ 加密字段查询性能比明文慢 2-3 倍(可接受,养生记录量不大)
- ⚠️ JSONB 加密后无法做 SQL 聚合,需应用层解密后聚合(可接受)

## 后续行动

- [ ] W2: 写 Drizzle schema + 迁移文件
- [ ] W2: 写加密 / 解密封装 `src/lib/crypto/`
- [ ] W2: 写审计触发器迁移
- [ ] W3: 写业务层 CRUD