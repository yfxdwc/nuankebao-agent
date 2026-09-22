-- ============================================
-- 0020 客户归属列: customer.owner_id (谁会在这条客户档案的"客户列表"里看到她)
-- 主人 2026-09-22 拍「全按建议」(ADR-0015 Q11/Q12):
--   「建档」与「归属」分家 —— created_by 原先一列干两份活:
--     ① 谁创建了这条档案 (审计)  ② 她在谁的客户列表里 (业务判定)
--   拆后: owner_id = 归属 (唯一真相源); created_by = 建档人 (审计)
--
-- 为什么要拆 (主人模型):
--   把其他用户加为自己的客户有两条显式路径 (推荐码识别 / 我推荐的人页),
--   "加"的对象往往是**已存在的档案** (建号即建档, §6.6) —— 单列 created_by 表达不了
--   "这条档案不是我建的, 但我加了她"。
--   同时: 建号**不再**自动把归属给推荐人 (推荐码 ≠ 关系, Q3 禁令/Q12) → 新建行 owner_id = NULL。
--
-- 纯 additive (向后兼容 ADR-0004): 加 1 列 + 1 索引 + 回填
--   回填口径: 迁移前 created_by 就是事实上的归属 → owner_id = created_by (语义不变, 无缝切换)
--   列可空: 建号路径建档 = NULL (等显式添加), 老 APK INSERT 不带此列也不炸
-- ============================================

ALTER TABLE "customer" ADD COLUMN IF NOT EXISTS "owner_id" BIGINT;--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_customer_owner" ON "customer" USING btree ("owner_id");--> statement-breakpoint

-- 回填: 存量行归属 = 原 created_by (迁移前两件事共用一列 → 等价迁移)
UPDATE customer SET owner_id = created_by WHERE owner_id IS NULL;--> statement-breakpoint

-- 回填后自检 (断了就 abort, 不许半吊子上线):
--   原语义下不可能出现 created_by 为空 → 回填后不该还有 owner_id 为空的历史行
DO $$
DECLARE orphan_count INTEGER;
BEGIN
  SELECT count(*) INTO orphan_count
  FROM customer
  WHERE owner_id IS NULL AND created_at < NOW() - INTERVAL '1 minute';
  IF orphan_count > 0 THEN
    RAISE EXCEPTION '0020 回填失败: 还有 % 条历史客户档案没有归属人, 需人工处理', orphan_count;
  END IF;
END $$;
