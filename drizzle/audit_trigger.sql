-- ============================================
-- 暖客宝 审计触发器 (挂到敏感表上, 自动写 audit_log)
-- 详见 docs/security-compliance.md §5
--
-- ⚠️ 函数 audit_trigger() 定义已拆到 drizzle/audit_function.sql:
--    它必须先于 up migration 创建 (0010 会引用), 由 src/lib/db/migrate.ts 控制顺序。
--    手工执行本文件前, 先执行 audit_function.sql。
-- ============================================

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

-- 会员/推荐 (ADR-0012): 钱与权益相关的写必须留痕
DROP TRIGGER IF EXISTS membership_audit ON membership;
CREATE TRIGGER membership_audit
  AFTER INSERT OR UPDATE OR DELETE ON membership
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS entitlement_grant_audit ON entitlement_grant;
CREATE TRIGGER entitlement_grant_audit
  AFTER INSERT OR UPDATE OR DELETE ON entitlement_grant
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS referral_code_audit ON referral_code;
CREATE TRIGGER referral_code_audit
  AFTER INSERT OR UPDATE OR DELETE ON referral_code
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS referral_reward_audit ON referral_reward;
CREATE TRIGGER referral_reward_audit
  AFTER INSERT OR UPDATE OR DELETE ON referral_reward
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS plan_audit ON plan;
CREATE TRIGGER plan_audit
  AFTER INSERT OR UPDATE OR DELETE ON plan
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
