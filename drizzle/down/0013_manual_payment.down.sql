-- down: 0013_manual_payment (人工收款通道)
-- ⚠ 破坏性: 会删掉已提交/已核销的付款申请记录 (内测期的账)。回滚前先导出。
DROP TABLE IF EXISTS "manual_payment_request";
DROP TABLE IF EXISTS "billing_config";
