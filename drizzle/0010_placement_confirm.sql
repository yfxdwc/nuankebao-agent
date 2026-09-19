-- ============================================
-- 0010 加盟落位「三方确认」工作流 (主人 2026-09-18 拍)
-- 见 docs/placement-confirmation-design.md
--
-- 纯新增: 2 张表 + 5 个索引 + 2 个审计触发器
--   - franchise_placement_request  落位/移动申请单 (含预占用的部分唯一索引)
--   - franchise_placement_confirm  三方确认记录
-- 不动既有表/既有数据 → 向后兼容 (老 APK 不看这两张表)
-- 依赖: audit_trigger() 函数 (drizzle/audit_trigger.sql 已建)
-- ============================================

CREATE TABLE IF NOT EXISTS franchise_placement_request (
  id                  BIGSERIAL PRIMARY KEY,
  kind                TEXT NOT NULL,                       -- create | move
  status              TEXT NOT NULL DEFAULT 'pending',     -- pending|executed|rejected|expired|cancelled
  initiator_fid       BIGINT NOT NULL,                     -- 设置者 (franchisee.id)
  initiator_user_id   BIGINT NOT NULL,                     -- 设置者账号 (user.id)

  -- kind=create: 新加盟商资料 (三方确认通过后才真正 insert franchisee)
  new_name            TEXT,
  new_phone_encrypted TEXT,
  new_phone_hash      TEXT,
  new_notes_encrypted TEXT,

  -- kind=move: 被移动节点
  move_fid            BIGINT,

  -- 目标点位
  target_parent_fid   BIGINT NOT NULL,
  target_side         TEXT NOT NULL,                       -- left | right

  -- 执行结果
  result_fid          BIGINT,

  -- Q6 历史数据回填 (豁免真实三方, 只留痕)
  backfilled          BOOLEAN NOT NULL DEFAULT FALSE,

  -- Q3: 72h 超时
  expires_at          TIMESTAMPTZ NOT NULL,
  executed_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Q4 预占: 同一 (父节点, 左/右) 只允许一个 pending → DB 层防并发抢位
CREATE UNIQUE INDEX IF NOT EXISTS idx_placement_pending_slot
  ON franchise_placement_request (target_parent_fid, target_side)
  WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_placement_initiator
  ON franchise_placement_request (initiator_fid);
CREATE INDEX IF NOT EXISTS idx_placement_status
  ON franchise_placement_request (status, expires_at);
CREATE INDEX IF NOT EXISTS idx_placement_move_fid
  ON franchise_placement_request (move_fid);

CREATE TABLE IF NOT EXISTS franchise_placement_confirm (
  id                BIGSERIAL PRIMARY KEY,
  request_id        BIGINT NOT NULL,
  confirmer_role    TEXT NOT NULL,     -- initiator | new_franchisee | target_parent
  confirmer_fid     BIGINT,            -- 对应 franchisee.id (回填/无账号可空)
  confirmer_user_id BIGINT,            -- 实际点确认的账号
  decision          TEXT NOT NULL,     -- approve | reject
  verified_by       TEXT NOT NULL DEFAULT 'in_app',  -- in_app | backfill
  decided_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_placement_confirm_request_role
  ON franchise_placement_confirm (request_id, confirmer_role);

-- 审计 (AGENTS §3: 任何数据库写都要走 audit log)
DROP TRIGGER IF EXISTS franchise_placement_request_audit ON franchise_placement_request;
CREATE TRIGGER franchise_placement_request_audit
  AFTER INSERT OR UPDATE OR DELETE ON franchise_placement_request
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();

DROP TRIGGER IF EXISTS franchise_placement_confirm_audit ON franchise_placement_confirm;
CREATE TRIGGER franchise_placement_confirm_audit
  AFTER INSERT OR UPDATE OR DELETE ON franchise_placement_confirm
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
