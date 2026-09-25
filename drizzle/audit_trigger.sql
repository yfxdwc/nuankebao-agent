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
-- 加盟节点 (franchisee) —— 加盟树结构本身最需要留痕
--   (2026-09-21 补: 做「管理员协商处理后强改上级」时发现 franchisee 一行都没挂触发器,
--    而这张表存的是整棵加盟树的 path / depth / root_id / referrer —— 改一次动一整棵子树,
--    没有审计行 = 事后查不出"谁什么时候把谁挪到哪"。admin 改上层还必填原因, 原因要能落地。)
DROP TRIGGER IF EXISTS franchisee_audit ON franchisee;
CREATE TRIGGER franchisee_audit
  AFTER INSERT OR UPDATE OR DELETE ON franchisee
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

-- 人工收款 (内测): 申请与核销都要留痕 (钱相关)
DROP TRIGGER IF EXISTS manual_payment_request_audit ON manual_payment_request;
CREATE TRIGGER manual_payment_request_audit
  AFTER INSERT OR UPDATE OR DELETE ON manual_payment_request
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS billing_config_audit ON billing_config;
CREATE TRIGGER billing_config_audit
  AFTER INSERT OR UPDATE OR DELETE ON billing_config
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

-- P5 后续 (2026-09-23): 可调参数组覆盖层
--   为什么必须挂: 改评分阈值会影响**全店**客户的分数与行动指引,
--   必须能回答"这条分数是谁在什么时候把参数改成这样的"。
DROP TRIGGER IF EXISTS app_config_audit ON app_config;
CREATE TRIGGER app_config_audit
  AFTER INSERT OR UPDATE OR DELETE ON app_config
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

-- 主人待开发想法 / 备忘录 (v0.1.5, migration 0025)
--   为什么必须挂: 主人想看"什么时候改了哪个想法的标题/状态/描述",
--   跟其他表同口径, 跟 docs/CHARTER §3.1 一致 (敏感/私人信息写入留痕)。
DROP TRIGGER IF EXISTS idea_audit ON idea;
CREATE TRIGGER idea_audit
  AFTER INSERT OR UPDATE OR DELETE ON idea
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

-- 客户推送 (Phase D, migration 0028, ADR-0019 / 主文档 §6.5.6 SHARE-5)
--   为什么必须挂: 推送 = **数据可见性授权**, 推过 / 撤销过都要能查到
--   (谁的客户推给谁 / 谁撤销了 / 撤销时间), 事后权限纠纷时唯一真相是审计。
--   不挂 deleted_at → 撤销只写 revoked_at (主文档 §3.4 E1 注); 但 update on
--   revoked_at 字段的改写仍会被触发器抓到 (AFTER UPDATE 整行 NEW)。
DROP TRIGGER IF EXISTS customer_share_audit ON customer_share;
CREATE TRIGGER customer_share_audit
  AFTER INSERT OR UPDATE OR DELETE ON customer_share
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
