-- ============================================
-- 0023 真实用户使用数据采集: usage_event
-- 主人 2026-09-22 拍: 「需要有对真实用户的完整全面的使用数据收集模块」
--   ① 同意模式 = 内部工具强制开启 ② 原始事件 180 天后删 ③ 4 片全做
--
-- 设计要点 (CHARTER §4.4.5 用量域红线):
--   - append-only 事件表, 不挂 audit 触发器 (它自身就是行为留痕, 挂上 = 双倍写入)
--   - 只存 ID / 枚举 / 计数 / 时长 (无姓名/手机号/健康内容; 服务端另有白名单清洗)
--   - event_id = 客户端事件 ID (幂等键, 批量重传去重)
--   - user_id 无 FK (与 audit_log 同口径; 账号停用后行为数据仍保留)
--
-- 纯 additive (ADR-0004): CREATE TABLE + 索引, 无破坏性变更
-- ============================================

CREATE TABLE IF NOT EXISTS "usage_event" (
  "id" BIGSERIAL PRIMARY KEY,
  "event_id" TEXT NOT NULL,
  "user_id" BIGINT,
  "device_id" TEXT,
  "session_id" TEXT,
  "event_name" TEXT NOT NULL,
  "category" TEXT,
  "screen" TEXT,
  "entity_type" TEXT,
  "entity_id" TEXT,
  "success" BOOLEAN,
  "error_code" TEXT,
  "duration_ms" INTEGER,
  "props" JSONB,
  "app_version" TEXT,
  "platform" TEXT,
  "os_version" TEXT,
  "device_model" TEXT,
  "client_ts" TIMESTAMPTZ,
  "server_ts" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);--> statement-breakpoint

CREATE UNIQUE INDEX IF NOT EXISTS "idx_usage_event_event_id" ON "usage_event" ("event_id");--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "idx_usage_event_user_ts" ON "usage_event" ("user_id", "server_ts");--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "idx_usage_event_name_ts" ON "usage_event" ("event_name", "server_ts");--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "idx_usage_event_session" ON "usage_event" ("session_id");--> statement-breakpoint

-- 保留期清理 (180 天) 用
CREATE INDEX IF NOT EXISTS "idx_usage_event_server_ts" ON "usage_event" ("server_ts");
