-- ============================================
-- 0029 客户列表索引补齐: 加速 R-9 列表膨胀优化
-- 文档: docs/r9-r10-optimization.md §2 索引补齐
--
-- 主人 2026-09-25 挂起 → 2026-09-26 解禁做深度优化, 本次拍板「补齐缺失索引」
-- (R-9 三连击之一)。
--
-- 三个新增索引 (覆盖现有 sort='new' / sort='name' + 复合 owner 排序):
--   1) customer(created_at DESC)
--        - 命中 sort='new' (默认排序, 老 .orderBy(desc(customer.createdAt)))
--        - 命中首页 SSR + 客户创建审计 (与 admin/customer-form 排序一致)
--        - 当前 customer 表无此索引 → 全表顺序扫 + sort, 候选集大时退化
--   2) customer(name)
--        - 命中 sort='name' (姓名 A→Z, 老 .orderBy(customer.name))
--        - 拼音 / 汉字 collate 走 PG default (--lc-collate=en_US.UTF-8);
--          索引按列值原序, 排序无需临时表
--   3) customer(owner_id, last_interaction_at DESC NULLS LAST)
--        - 命中 R-9 列表膨胀后「我的客户」+ 「最近联系」组合查询
--          (W5 RBAC 行级 owner_id 过滤 + 跟进时间排序)
--        - 既有 idx_customer_owner + idx_customer_last_interaction 各自只走单列,
--          owner=我 时 PG planner 仍会先扫 owner 索引拿 ID, 再回表按时间重排
--          (大 owner_id (枝深的下层 user) = 数千行, 回表 sort 是 O(N log N))
--        - 复合索引直接按 (owner_id, last_interaction_at) 排好, scan + slice
--          即可拿到第一页, 不需要回表 sort
--
-- 纯 additive (ADR-0004 / CHARTER §3.5):
--   - 仅 CREATE INDEX IF NOT EXISTS, 不动现有列
--   - 不写 CREATE INDEX CONCURRENTLY (migration 同步执行; 大表可后续
--     用 ALTER INDEX ... RENAME / REINDEX 重建, 不在本次范围)
--   - 不挂审计触发器 (索引不写业务变更)
--   - 老 APK / 老 query 不受影响
-- ============================================

-- 索引 1: created_at DESC (默认排序 + 客户创建时间审计)
CREATE INDEX IF NOT EXISTS "idx_customer_created_at_desc"
  ON "customer" ("created_at" DESC);
--> statement-breakpoint

-- 索引 2: name (姓名排序; 老 sort='name' 全表 sort 退化的兜底)
CREATE INDEX IF NOT EXISTS "idx_customer_name"
  ON "customer" ("name");
--> statement-breakpoint

-- 索引 3: 复合 (owner_id, last_interaction_at DESC NULLS LAST)
--   命中 R-9 「我的客户 ∪ 直推加盟 ∪ 上级推送」扩围后, owner_id 行的「最近联系」排序
--   NULLS LAST = 与既有 sort='recent' 走 lastInteractionAt DESC NULLS LAST 一致
--   (老从没联系 = last, 新联系 = 前)
CREATE INDEX IF NOT EXISTS "idx_customer_owner_last_interaction"
  ON "customer" ("owner_id", "last_interaction_at" DESC NULLS LAST);
--> statement-breakpoint

COMMENT ON INDEX "idx_customer_created_at_desc" IS
  'R-9 索引补齐 #1: 命中 sort=new (默认排序) + 客户创建时间审计; created_at DESC 单列';
COMMENT ON INDEX "idx_customer_name" IS
  'R-9 索引补齐 #2: 命中 sort=name; name 单列, PG default collate';
COMMENT ON INDEX "idx_customer_owner_last_interaction" IS
  'R-9 索引补齐 #3: 命中「我的客户」owner_id 过滤 + 最近联系排序 (W5 RBAC 行级过滤复合键); NULLS LAST 与 sort=recent 同口径';