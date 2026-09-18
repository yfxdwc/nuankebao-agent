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

-- ============================================
-- 沙龙模块触发器 (v0.1.5 Phase 7)
-- salon / salon_invitation / salon_guest / salon_quota
-- (动态/资料表不挂: 系统消息会产生大量噪声, 价值低)
-- ============================================

DROP TRIGGER IF EXISTS salon_audit ON salon;
CREATE TRIGGER salon_audit
  AFTER INSERT OR UPDATE OR DELETE ON salon
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS salon_invitation_audit ON salon_invitation;
CREATE TRIGGER salon_invitation_audit
  AFTER INSERT OR UPDATE OR DELETE ON salon_invitation
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS salon_guest_audit ON salon_guest;
CREATE TRIGGER salon_guest_audit
  AFTER INSERT OR UPDATE OR DELETE ON salon_guest
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS salon_quota_audit ON salon_quota;
CREATE TRIGGER salon_quota_audit
  AFTER INSERT OR UPDATE OR DELETE ON salon_quota
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
