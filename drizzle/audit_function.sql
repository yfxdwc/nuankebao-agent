-- ============================================
-- 暖客宝 审计触发器函数 (audit_trigger)
--
-- 为什么单独一个文件 (2026-09-19 P1, 新库首部署暴露):
--   migration drizzle/0010_placement_confirm.sql 会直接
--   `CREATE TRIGGER ... EXECUTE FUNCTION audit_trigger()`,
--   但函数原先只在 up migration **全部跑完之后**才由 audit_trigger.sql 创建
--   → 全新库跑到 0010 必报 `function audit_trigger() does not exist`
--     (dev 库因历史增量迁移一直有函数, 掩盖了这个问题)。
--
-- 修法: 本文件只放函数定义, 由 src/lib/db/migrate.ts 在 up migration **之前**执行;
--       drizzle/audit_trigger.sql 只挂触发器, 在 migration 之后执行。
-- 注意: 函数体引用 audit_log 表, 但 plpgsql 不校验对象存在性, 可先建函数。
-- ============================================

CREATE OR REPLACE FUNCTION audit_trigger() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (
    table_name,
    record_id,
    operation,
    user_id,
    changed_fields,
    ip_address
  )
  VALUES (
    TG_TABLE_NAME,
    -- ⚠️ 不能用 NEW.id/OLD.id: 键值型表 (如 billing_config, PK 是 key) 没有 id 列,
    --    plpgsql 运行时会直接报 `record "new" has no field "id"` → 该表所有写入失败。
    --    用 jsonb 取值不挑列, 没有 id 的表退化成 0 (audit_log.record_id 是 not null)。
    --    (2026-09-19 人工收款通道落地时发现)
    COALESCE(NULLIF(to_jsonb(COALESCE(NEW, OLD)) ->> 'id', '')::BIGINT, 0),
    TG_OP,
    NULLIF(current_setting('app.current_user_id', true), '')::BIGINT,
    CASE TG_OP
      WHEN 'INSERT' THEN to_jsonb(NEW)
      WHEN 'UPDATE' THEN (
        SELECT jsonb_object_agg(key, value)
        FROM jsonb_each(to_jsonb(NEW))
        WHERE to_jsonb(NEW) -> key IS DISTINCT FROM to_jsonb(OLD) -> key
      )
      WHEN 'DELETE' THEN to_jsonb(OLD)
    END,
    NULLIF(current_setting('app.client_ip', true), '')::INET
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
