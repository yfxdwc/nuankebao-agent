-- ============================================
-- 0007_customer_avatar: 客户头像 (详情页头像右下角相机图标可设)
-- 背景: 主人 2026-09-18 拍「客户头像右下角增加一个相机图标, 点击可设置客户头像
--       (增加几个候选头像供不希望用真人头像的用户选择) 或自拍照或相册上传」
-- 取值约定 (跟 user.avatar_url 完全一致, 白名单在 src/lib/avatar.ts):
--   null             → 默认: 姓名首字
--   'preset:<id>'    → 内置候选头像 (前端本地画, 不占存储)
--   '/uploads/x.jpg' → 上传的照片 (POST /api/photos 产物)
-- 依据: CHARTER §3.5 + ADR-0004
-- 兼容性 (红线自检):
--   - ADD COLUMN nullable text → ✅ 老 APK INSERT 不带该列也能跑
--   - 不 DROP / 不 RENAME / 不 ALTER TYPE / 无 SET NOT NULL 无 DEFAULT
-- 配套:
--   - drizzle/down/0007_customer_avatar.down.sql (反向操作, CHARTER §3.5 红线)
-- ============================================

ALTER TABLE "customer" ADD COLUMN "avatar" text;--> statement-breakpoint
