# 加盟落位「三方确认」+ 任意点位落位 + 节点移动 — 方案 (草案 v0.1)

> 状态: **已拍板 + P0/P1 已实施** (2026-09-18)
> 拍板 (ask_user 7ef4548b): Q1/Q2 = App 内确认 (本人/上级都要账号, 各自在自己「加盟落位确认」里点同意)
>   / Q3 = 72h 超时 / Q4 = 预占 (画虚位) / Q5 = 三方不含原父节点 + 推荐人不变 / Q6 = 历史节点补录 / Q7 = 只能操作自己子树内点位
> 实施: drizzle/0010_placement_confirm.sql + src/lib/db/queries/franchisee-placement.ts +
>   /api/franchisees/placement-requests(/[id]/decide|cancel) + Flutter「加盟落位确认」页 + 图谱「加下线到此点位」
> 冒烟: scripts/smoke-placement-confirm.ts (三方确认全流程) ✓; 历史回填: scripts/backfill-placement-confirms.ts (32 条已补) ✓
> 未做: 移动节点 UI (后端 kind=move 已通) + 图谱「待确认虚位」渲染 (API 已返回 pendingPlacements)
> 关联: ADR-0006 (加盟体系) / ADR-0011 (层级不限 + 懒加载) / `docs/data-model.md`
> 触发: 主人 2026-09-18 需求 (原文见 §0)

## 0. 需求原文 (主人 2026-09-18)

> 「所有用户在后台需要有一个完整的关系图谱数据集。例如：用户 y 是用户 X 的直推加盟客户（即 Y 是 x 的下线），
> x 可以把 y 放在自己当前加盟商图谱中任何一个点位的下级点位上，当 y 有了自己的加盟客户甚至更多的加盟
> 客户形成了图谱树，x 的图谱中自动显示所有 y 的图谱，也就是对于 x 来说，y 就是其图谱树上的一个枝，
> 这枝无论怎样长都是属于 x 这棵树的一部分；同样的 x 也有上线（假设 x 的上线是 r，x 是 r 的直推加盟客户），
> 那么 x 的图谱就属于 r 的图谱中的一个枝。设置加盟节点时，必需三方确认才能设置成功（设置者本人、
> 新加盟商本人，新加盟商上一个节点加盟商，如果上一个节点加盟商就是设置者本人节点则仅需要双方确认即可）；
> 改加盟商节点位置也是一样，需要先经过三方确认才能解除原加盟节点位置，然后重新设置新的加盟点位」

拆成 4 件事：
1. **子树归属**：y 的整棵树自动是 x 的枝，x 的树是 r 的枝（层层向上，一人一套完整数据视图）
2. **任意点位落位**：x 可以指定「自己图谱里任意节点」的下级空位（左/右）放新加盟商
3. **三方确认**：设置者本人 + 新加盟商本人 + 新位置的上一个节点加盟商（父节点 == 设置者时 → 双方）
4. **改位置**：同样三方确认；确认通过后 = 先解除原位置 + 再落新位置（整棵子树跟着搬）

## 1. 现状盘点 (2026-09-18 recon)

| 能力 | 现状 |
|---|---|
| 二叉树结构 | ✅ `franchisee.referrer_id / placement_side / placement_path / placement_depth`（物化路径） |
| 子树归属 | ✅ 天然成立：查子树按 `placement_path LIKE 我的 path \|\| '%'` → 自动含整棵子树 |
| 落位算法 | ⚠️ `placeNewFranchisee(referrerId, sideHint)` **只能落在推荐人自己的空位/BFS 更深** → **不能指定任意父节点** |
| 移动节点 | ❌ 无（改位置 = 目前只能软删重新加） |
| 审批/确认工作流 | ❌ 无（`follow_up_task` 只有 pending/done，跟落位无关） |
| 通知 | ❌ 无站内信/推送；短信只在 auth 配置里提到（dev 登录码硬编码 123456） |
| 权限 | ⚠️ 有 RBAC admin/manager/sales（sales 只看自己），**但没有「落位必须在我子树内」的校验，也没有三方身份校验** |
| 多用户 | ✅ user.franchiseeId 一人一条，可开多个账号（dev 造数据方便） |

## 2. 方案骨架

### A. 数据模型 (新增 2 张表)

```
franchise_placement_request   -- 落位申请单
  id              bigserial
  kind            'create' | 'move'        -- 新设 / 改位置
  status          'pending' | 'approved' | 'executed' | 'rejected' | 'expired' | 'cancelled'
  initiator_fid   bigint   -- 设置者 (franchisee.id)
  -- create 用: 新加盟商资料 (pass 后才真正 insert franchisee)
  new_name / new_phone / new_notes
  -- move 用: 被移动节点
  move_fid        bigint null
  -- 新点位
  target_parent_fid bigint
  target_side       'left' | 'right'
  -- 超时
  expires_at      timestamptz
  audit (created_at / updated_at / created_by_user_id)

franchise_placement_confirm   -- 每一方的确认
  request_id      bigint
  confirmer_role  'initiator' | 'new_franchisee' | 'target_parent'
  confirmer_user_id bigint null      -- 有账号的
  decision        'approve' | 'reject'
  verified_by     'in_app' | 'sms_code' | 'proxy'   -- 确认方式 (看 Q1/Q2 拍板)
  decided_at      timestamptz
  UNIQUE(request_id, confirmer_role)
```

> 是否需要 `franchisee.pending_request_id`（待确认就占位）= 见 Q4。

### B. 落位算法改造

```ts
// 现在: placeNewFranchisee(referrerId, sideHint) → 只能在推荐人自己子树里 BFS 找空位
// 改成: placeAt(parentFid, side) → 直接指定「父节点 + 方向」
//   - 校验 1: parentFid 空位 (该侧没子节点)
//   - 校验 2: parentFid 在发起人的 placement 子树里 (path LIKE 发起人 path)
//     (admin 例外；如主人要「上线可操作下线子树」见 Q7)
//   - newPath = parent.placementPath + ('L.' | 'R.')
//   - newDepth = parent.placementDepth + 1
```

**移动节点**（整棵子树搬迁）= 事务内：
1. 校验目标空位 + 不在被移动子树内（防自嵌套成环）
2. 更新被移动节点：`placement_path/depth/side` + `referrer_id`（改位置是否改推荐人见 Q5）
3. **子树 path 前缀替换**：`UPDATE franchisee SET placement_path = replace(...) WHERE placement_path LIKE 老前缀 || '%'` + 同步 depth
4. 释放原位置（原父节点该侧空出来）
5. 审计 + 通知

### C. 工作流 (状态机)

```
发起 (设置者填资料 + 选点位)
   ↓  生成 request(pending) + 三条邀请 (initiator 自动 approve)
三方确认 (各自在自己 App 的「待我确认」里 approve/reject)
   ├─ 全部 approve → 事务执行落位 → status=executed → 通知三方
   ├─ 任一 reject   → status=rejected (不落位) → 通知发起人
   └─ 超时          → status=expired (Q3) → 点位释放
```

### D. Flutter UI (APK 域)

1. **图谱页**：点节点 → 底部 sheet「在此点位加下线」→ 选左/右 → 填新加盟商(姓名/手机) → 提交 → 提示「已提交，等待三方确认 (1/3)」
2. **待我确认**：客户页顶部/我的 tab 加入口 + 红点；列表项显示「谁想把谁放在哪」+ 同意/拒绝
3. **图谱节点状态**：待确认的落位在画布上画成**虚线虚位**（不确定是否要做，见 Q4），已发起未完成的在信息条显示状态
4. **我发起的**：可撤回（cancelled）

### E. 测试 / 迁移

- 历史 31 个节点（含 SeedTest-*）：**不回填确认记录**（豁免，见 Q6）
- dev 造 3 个测试账号（sales 角色）演练三方确认
- 单测：状态机（全部 approve / 任一 reject / 超时）+ 移动子树 path 重算 + 越权校验

## 3. 工作量 (粗估)

| 阶段 | 内容 | 估时 |
|---|---|---|
| P0 | 2 张表 + `placeAt()` 任意点位 + 越权校验 + 三方确认状态机 (后端) | 1.5 天 |
| P1 | Flutter：发起落位 + 待我确认列表 + 状态展示 | 1.5 天 |
| P2 | 移动节点（含子树搬迁 + 释放原位置 + 防环） | 1 天 |
| P3 | 通知/红点 + 超时清理任务 + 审计补齐 | 0.5 天 |

## 4. 待主人拍板 (Q1-Q7)

| # | 问题 | 选项 |
|---|---|---|
| Q1 | **新加盟商本人（可能还没账号）怎么确认？** | ① 短信验证码（要接阿里云短信，dev 固定 123456） ② 先注册登录 → 在「待我确认」里点确认 ③ 设置者代勾 + 留痕（伪三方） |
| Q2 | **目标父节点加盟商不是系统用户（没账号）怎么确认？** | ① 设置者/上线代确认（留痕） ② 暂不允许放他下面 ③ 电话确认后设置者勾选（同上） |
| Q3 | 确认超时 | ① 24h ② 72h ③ 不超时（手动撤回） |
| Q4 | 待确认期间**点位预占**？ | ① 预占（别人抢不到，画虚位） ② 不预占（落位时再校验，可能失败） |
| Q5 | 移动节点时三方 = 设置者 + 该节点本人 + **新**父节点；**原**父节点要不要也确认（=四方）？改位置是否同时改「推荐人」？ | ① 原父节点不确认 / 推荐人不变 ② 原父节点也要确认 / 推荐人不变 ③ 原父节点确认 + 推荐人改成新父节点 |
| Q6 | 历史节点（已存在的 31 个） | ① 豁免确认（不回填） ② 补录「已确认」记录（谁作为三方？） |
| Q7 | 谁能发起落位/移动？ | ① 仅「该点位所属的上线本人」（父节点在我子树内） ② 我的子树内任意点位 + 我上线也能操作我的子树（层层可管） ③ admin 全网任意 |
