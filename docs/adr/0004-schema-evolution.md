# ADR-0004: Schema 演进章程 (DB migration 向后兼容)

**日期**: 2026-09-05
**状态**: 已采纳
**影响范围**: 所有 `drizzle/*.sql` migration + 客户端兼容 (Next.js / Flutter)
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §3.5 Schema 演进红线 + §3.6 RBAC 扩展预留

## 上下文

本决策对应元宪法:

- [`CHARTER.md`](../CHARTER.md) **§2 原则 7** (小步快跑 > 一次大跃) — 要求每步可回滚,migration 必须可逆
- [`CHARTER.md`](../CHARTER.md) **§2 原则 4** (结构化 > 自由文本) — schema 演进要保持结构化思维
- [`CHARTER.md`](../CHARTER.md) **§3.5 Schema 演进红线** — 本 ADR 是其依据
- [`CHARTER.md`](../CHARTER.md) **§3.6 RBAC 扩展预留** — W4 必须补 store_id 列 + 索引
- [`CHARTER.md`](../CHARTER.md) **§5.2 必须 ask_user** (DB schema 大改) — 加新表 / 删字段属于 L1,但**演进策略**本身是 L1 战略决策

---

## 问题

MVP 早期 (W2-W6) schema 频繁变更。当前没有章程,容易出现:

1. **加列不加默认值** → 老版本 Flutter APK INSERT 失败 (例: `ALTER TABLE customer ADD COLUMN avatar_url TEXT NOT NULL` 在旧版客户端 POST 没 avatar_url 时崩)
2. **删列** → 老版本客户端反序列化时 JSON 解析 OK 但其他字段引用 → 调试困难
3. **改类型** (`ALTER COLUMN ... TYPE`) → 隐式 cast 失败 / 老数据格式不兼容
4. **重命名** (RENAME COLUMN) → Flutter freezed 模型硬编码字段名,序列化 silent fail
5. **无 down migration** → migration 跑挂后只能手工回滚,主人忙时拖延
6. **大表锁表** (`ALTER TABLE` 不带 CONCURRENTLY) → 内测期销售停工

## 决策

### 1. 强制迁移模式 (CI 阻断)

[`tools/check-migration-compat.sh`](../tools/check-migration-compat.sh) 在 `pnpm db:migrate` 前自动跑,以下模式**阻断 merge**:

| 模式 | 替代方案 |
|---|---|
| `DROP COLUMN` | 软标记 (`deleted_at`) + 30 天后真删 |
| `DROP TABLE` | 主人拍板 + ADR + 至少保留备份 1 年 |
| `RENAME COLUMN` / `RENAME TABLE` | 不重命名,新增列 + 旧列留 NULL |
| `ALTER COLUMN ... TYPE` 无 `USING` | 加新列 + 双写 + 后切读 + 最后删旧列 |
| `ALTER COLUMN ... SET NOT NULL` 无 DEFAULT | 加 DEFAULT 或两步 |
| `DROP INDEX` 在核心表 | 加新索引 + 验证查询计划后 DROP |

警告 (不阻断, 主人 review):
- `ADD COLUMN` 无 DEFAULT
- 大表 `ALTER TABLE` 不带 `CONCURRENTLY`
- `CREATE INDEX` 不带 `CONCURRENTLY`

### 2. 回滚支持

- 破坏性 migration 必须配 `drizzle/down/<同名>.sql`
- 加表 / 加列 (纯加性) 不强求 down (rollback 风险高于价值)
- `pnpm db:migrate:down <idx>` 触发单步回滚

### 3. RBAC 预留 (W4 之前)

W5 销售内测时,店长 vs 销售员数据隔离。当前 schema 已经有部分 hook:

- ✅ `created_by` (NOT NULL) — 所有表都有
- ✅ `deleted_at` — customer 表有
- ✅ `user_role` enum — user 表有
- ⚠️ `store_id` — wellness_record 有, **customer 表缺**
- ⚠️ `store_id` 索引 — **缺**

W4 之前必须补:
1. `customer.store_id` 加列 (NULL) + 从 `created_by → staff → store_id` backfill
2. customer / interaction / follow_up_task 加 `store_id` 索引 (用于 W5 行级过滤)
3. user 表加 `default_store_id`

W5 middleware 实施细节另开 ADR-0005。

### 4. CI 集成

`.github/workflows/ci.yml` 加一步:

```yaml
- name: Check migration compatibility
  run: bash tools/check-migration-compat.sh
```

PR 自动跑, ❌ 阻断 merge。

### 5. 工具脚本设计原则

- **不替代数据库迁移**,只检测违反章程的模式
- **简单 grep + 正则**,不引入 AST 解析器 (避免 §3.2 引入新依赖)
- **CI 跑 + 本地跑** 两用 (`bash tools/check-migration-compat.sh`)

## 候选评估

### 候选 A: 不写章程, 靠 code review 人工审

- ✅ 灵活
- ❌ 主人忙时漏审 = 必爆雷
- ❌ 新人 agent 上手 = 重蹈覆辙

**结论**: ❌ 排除

### 候选 B: 用 Atlas / Skeema 等第三方 schema migration 工具

- ✅ 内置 compat check (Atlas deprecation API)
- ❌ 引入新依赖 (违反 §2 原则 4 简洁)
- ❌ 学习曲线陡,主人在意
- ❌ 替换 drizzle migrate = W1 工作作废

**结论**: ❌ 排除

### 候选 C: 自写 grep + 正则 (本决策)

- ✅ 零依赖 (CHARTER §2 原则 4 友好)
- ✅ 主人可读脚本,出错了人工 patch
- ⚠️ 误报风险 (例如 COMMENT 里的 DROP COLUMN 字样会被误报) — 接受,反馈到 §11

**结论**: ⭐⭐⭐⭐⭐ 采纳

## 影响

- ✅ W3 加列 = 安全 (强制加 DEFAULT)
- ✅ Flutter 老 APK = 不崩
- ✅ 主人 W6 改 schema = 有章程兜底
- ✅ Phase 2 AI 启动 = ai_runs 表加法 (CHARTER §3.1 + §2 原则 1)
- ⚠️ 真正删列要 2 步 (30 天周期),急删 = ADR 拍板

## 后续行动

- [x] 写 `tools/check-migration-compat.sh`
- [x] 加 `docs/CHARTER.md` §3.5 + §3.6
- [x] 改 `src/lib/db/migrate.ts` (加 compat check 调用 + down.sql 支持)
- [ ] W3 实战验证: 写一个新 migration 测试 (W2 末)
- [ ] W4 加 `customer.store_id` 列 + 索引
- [ ] CI 加 compat check step (.github/workflows/ci.yml)
- [ ] W5 触发 ADR-0005 (RBAC middleware 实施)