-- down: 0010_placement_confirm (加盟落位三方确认工作流)
--
-- 纯新增迁移 → 回滚 = 删表 (含审计触发器 + 索引由表级联删除)
-- ⚠ 会丢「待确认/已确认」的全部申请记录; 已执行的落位结果 (franchisee 行) 不受影响
--   → 回滚前如需保留审计: SELECT * FROM franchise_placement_request; / _confirm;

DROP TRIGGER IF EXISTS franchise_placement_request_audit ON franchise_placement_request;
DROP TRIGGER IF EXISTS franchise_placement_confirm_audit ON franchise_placement_confirm;

DROP TABLE IF EXISTS franchise_placement_confirm;
DROP TABLE IF EXISTS franchise_placement_request;
