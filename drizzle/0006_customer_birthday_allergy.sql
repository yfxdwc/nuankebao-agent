-- ============================================
-- 0006_customer_birthday_allergy: 客户生日细化 (年月日 + 农历/阳历 + 提醒强度) + 过敏史
-- 背景: 主人 2026-09-18 拍「编辑客户页」需求:
--   - 出生年 → 支持年月日, 允许不知道 (留空) ; 支持农历/阳历
--   - 填了「月+日」= 开启生日提醒, 提醒强度可选 7 天前 / 3 天前 / 当天
--   - 新增「过敏史」(与既往病史分开: 过敏关系到能不能用某些药/精油)
-- 依据: CHARTER §3.5 + ADR-0004
-- 兼容性 (红线自检):
--   - ADD COLUMN nullable integer/text → ✅ 老 APK INSERT 不带这些列也能跑
--   - birth_calendar 带 DEFAULT 'solar' + NOT NULL → ✅ 存量行自动回填 'solar'
--   - 不 DROP / 不 RENAME / 不 ALTER TYPE / 无 SET NOT NULL 无 DEFAULT
-- 配套:
--   - drizzle/down/0006_customer_birthday_allergy.down.sql (反向操作, CHARTER §3.5 红线)
-- ============================================

ALTER TABLE "customer" ADD COLUMN "birth_month" integer;--> statement-breakpoint
ALTER TABLE "customer" ADD COLUMN "birth_day" integer;--> statement-breakpoint
ALTER TABLE "customer" ADD COLUMN "birth_calendar" text DEFAULT 'solar' NOT NULL;--> statement-breakpoint
ALTER TABLE "customer" ADD COLUMN "birthday_remind_days" integer;--> statement-breakpoint
ALTER TABLE "customer" ADD COLUMN "allergy_history_encrypted" text;--> statement-breakpoint
