-- ============================================
-- 暖客宝 审计触发器
-- 在敏感表上挂触发器, 自动写 audit_log
-- 详见 docs/security-compliance.md §5
-- ============================================

-- 触发器函数
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
    COALESCE(NEW.id, OLD.id)::BIGINT,
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

-- 删除已有触发器 (重入安全)
DROP TRIGGER IF EXISTS customer_audit ON customer;
DROP TRIGGER IF EXISTS wellness_record_audit ON wellness_record;
DROP TRIGGER IF EXISTS interaction_audit ON interaction;
DROP TRIGGER IF EXISTS follow_up_task_audit ON follow_up_task;
DROP TRIGGER IF EXISTS user_audit ON "user";

-- 挂触发器
CREATE TRIGGER customer_audit
  AFTER INSERT OR UPDATE OR DELETE ON customer
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER wellness_record_audit
  AFTER INSERT OR UPDATE OR DELETE ON wellness_record
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER interaction_audit
  AFTER INSERT OR UPDATE OR DELETE ON interaction
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER follow_up_task_audit
  AFTER INSERT OR UPDATE OR DELETE ON follow_up_task
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER user_audit
  AFTER INSERT OR UPDATE OR DELETE ON "user"
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
-- wellness_knowledge 触发器
DROP TRIGGER IF EXISTS wellness_knowledge_audit ON wellness_knowledge;
CREATE TRIGGER wellness_knowledge_audit
  AFTER INSERT OR UPDATE OR DELETE ON wellness_knowledge
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
