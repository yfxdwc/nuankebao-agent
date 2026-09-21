# ADR-0014: 多根加盟树 (root_id) + 向上认领上级 (kind=promote)

> **状态**: ✅ Accepted (主人 2026-09-21 拍板)
> **日期**: 2026-09-21
> **影响范围**: `franchisee` 结构 (新增 `root_id`) · 子树可见性查询 · 落位状态机 (新增 `kind='promote'`) ·
> 图谱/客户「加盟」判定 · 管理员用户图谱
> **相关**: [ADR-0006 加盟边界](./0006-franchise-boundary.md) ·
> [ADR-0011 层级不限 + 懒加载](./0011-unlimited-franchise-depth.md) ·
> [ADR-0013 账号 = 客户](./0013-account-customer-binding.md) ·
> [落位三方确认设计](../placement-confirmation-design.md) · AGENTS §6.5 / §6.6

---

## 1. 背景 (主人原话)

> 「**要支持多根**。」
>
> 「在使用暖客宝 app 之前, 用户 (比如碧波庭公司的加盟系统) 公司系统**已经存在固有的加盟体系
> (节点树)** 了; 也就是暖客宝 app 在**兼容已有加盟树**的同时也同时长出新枝, 但新枝 (节点) 在 app 里
> 之所以能被提升为加盟节点, 前提是**在现实的客户公司业务系统里已经成为了加盟商**, app 里只是把
> 现公司的加盟树**同步**到 app 中。」
>
> 「当一个新的团队的初始用户 (admin 指定为加盟节点) **大概率只是公司加盟系统中的中间层**, 当前 app
> 内新增加盟节点三方确认方案**仅支持加盟树向更高层生长** (例如初始用户在公司系统中是在第 10 层,
> 那么他能把自己这一枝的加盟商都提升到节点树中), 但他**无法把其前面的 (位于 9 层) 的加盟商引荐到
> app 加盟树中来**。原来的三方确认往上生长的方案不变, **需要增加往根部发展用户的方案**。」

两个诉求:

1. **多根**: 一个 app 里可以并存多棵互不相干的加盟树 (不同加盟系统 / 同一系统上暂未上溯到共同上层的不同枝)
2. **往根部发展**: 从"已有的一枝"往上接 —— 把现实里的**直接上级**拉进 app

---

## 2. 问题 1: 多根

### 2.1 根因 (代码事实)

`franchisee.placement_path` 是**相对自己那棵根**的路径, 根节点 `path = ''`:

| id | name | referrer_id | placement_path |
|---|---|---|---|
| 75 | 杨望 (根 1) | null | `''` |
| 142 | 预览受邀者 (根 2) | null | `''` |
| 76 | SeedTest-李建国 | 75 | `L.` |

于是**一切"从根往下找子树"的写法都跨根串味**:

| 位置 | 旧写法 | 多根后果 |
|---|---|---|
| `admin-users.ts::listAdminNodes` | `p.placement_path = left(f.placement_path, len-2)` | 实测节点行数翻倍 (33 → 35, `L.` 同时挂到两个根) |
| `franchisee.ts::getPlacementTree` | 根 → `path <> ''` 取全部非根节点 | 根用户的图谱把**别的树**当自己的子树 |
| `franchisee.ts::getFranchiseeTree` | 同上 | 同上 (子树/上下级判定错) |
| `customer.ts::myDownlineFranchiseeSql` | `me.path='' AND f.path<>''` | 根用户按"我的加盟子树"筛客户 → **把别的树的客户算成自己的下线** |
| `rbac.ts::franchiseeRbacFilter` | `path LIKE myPath%` | 同上 (越权可见) |

根因: schema **没存"这个节点属于哪棵树"**。`placement_path` 只在根内唯一,
`referrer_id` 是**推荐人**(≠ 点位父节点, 任意点位落位时两者不同), 两个都推不出树归属。

### 2.2 决策: 加 additive 列 `franchisee.root_id`

- 值 = **该节点所在那棵树的根 `franchisee.id`**; 根节点自己 `root_id = 自己的 id` (自指)
- `nullable` (兼容 ADR-0004: 老 APK INSERT 不带此列不炸); 新代码**一律显式写**
- 回填 (migration `0017` 内, 一次性): 沿 `referrer_id` 递归爬到**没有上级的最高祖先**
  (递归 CTE + `steps` 取最后一行), 不爬进已软删父节点
- 维护点 (所有 `INSERT franchisee` 路径):
  `createRootForUser` (自指) · `executeRequest` (跟落位父节点) · `createFranchisee` (跟落位父节点) · `promote` (新根自指)
- 查询口径: 子树判定 = **同 `root_id` + path 前缀** (两条件缺一不可)

### 2.3 候选评估

| # | 方案 | 结论 |
|---|---|---|
| **A** | 加 `root_id` 列 | ✅ **采纳** — 不动 path 语义, `WHERE root_id = $1` 一把梭, 符合 ADR-0004 |
| B | `placement_path` 带根前缀 (`#75.L.R.`) | ❌ 要迁移全部历史 path, 且 path 语义变 (风险高) |
| C | 暂不支持多根 | ❌ 与主人刚拍板的"多棵树"冲突 |

### 2.4 「我的加盟网络」对根用户显示哪棵 (拍板)

**只看自己那棵** (`root_id = 我的根`)。别的树归**管理员图谱**看 —— 也就是
「系统管理员在我的页进入的不是我的加盟网络, 而是整个后台的全部用户/加盟商」。

---

## 3. 问题 2: 往根部发展 (向上认领上级)

### 3.1 为什么老方案物理上做不到

老的三方确认 = **设置者 + 新加盟商本人 + 新位置的上一个节点加盟商(父节点)**,
且 `createPlacementRequest` **强制 `targetParentFid` 必须已存在于 app**。

「第 10 层的人想把第 9 层拉进来」时: 新节点是第 9 层, 它的父(第 8 层)在 app 里**根本不存在**
→ 老三方的第三方**物理不存在**; 而且方向是"往上", 不是"往自己的子树里加一个空位"。

### 3.2 决策: 新增 `kind='promote'` (向上认领)

```
现根 A 发起「认领上级」: 填 U 的姓名+手机号 + 我在 U 的哪条线 (A线/B线)
   ↓ 双方确认: A (发起人, 自动 1 票) + U 本人 (手机号匹配, 注册登录后在「加盟落位确认」点同意)
执行 (事务内):
   1. INSERT U   (path='', depth=0, referrer_id = A 原推荐人, root_id 稍后自指)
   2. UPDATE 原树: placement_path = 'L.'/'R.' || placement_path, placement_depth += 1,
                   root_id = U.id     WHERE root_id = A.root_id
   3. A.placement_side = 选的那条线      (⚠ 不动 A.referrer_id: 推荐关系不变, 与 Q5 一致)
   4. U.root_id = U.id (自指)
   5. U 若有账号 → 绑 user.franchisee_id + 落客户档案 (与 create 同一条路径)
```

结果: **U 成为新根, A 整棵子树整体下降一层** (可反复执行 → 一层层往上同步公司现有体系)。

### 3.3 为什么确认方是「双方」而不是三方

promote 里 A 就是 U 在 app 内**唯一的邻接已加盟节点** —— 正是老规则
「父节点 == 设置者 → 双方」的那条豁免 (promote 的 `target_parent_fid` 存的就是锚点 A,
于是 `requiredRoles(A, A)` 自然给出 `['initiator','new_franchisee']`, **代码零特例**)。

**老的三方确认 (往下生长) 完全不变**: 本次只**新增** kind, 没动 `create` / `unjoin`。

### 3.4 边界 (硬校验)

- 只有**树根**能发起 (`placementPath === ''`) —— 往上发展只能从根往上接, 中间节点上面已有 app 内上级
- 管理员**不能**代发起 (管理员无加盟节点, promote 的锚点必须是自己)
- 不能把自己认领为自己的上级; 上级手机号若已是加盟商 → 拒 (不复制树上已有节点)
- 同一个根同时只能有 **1 张** pending 认领单
- 预占唯一索引 `idx_placement_pending_slot` 收紧为 `WHERE status='pending' AND kind='create'`
  (unjoin 本就不占新位; promote 的 `target_parent_fid` 是"锚点"而非空位, 不该占用锚点子位)

### 3.5 候选评估

| # | 方案 | 结论 |
|---|---|---|
| **A** | 新增 `kind='promote'`, 原树整体下降一层, 新根上移 | ✅ **采纳** — 结构真实反映公司体系 (U 是 A 的上级), 老流程零改动, 可反复上溯 |
| B | U 自己成为**另一棵独立的根** (多根并存) | ❌ 丢了 U→A 的父子关系, 与"同步公司现有加盟树"的目标相悖 (只适合"完全不同的加盟系统") |
| C | 只允许 admin 建新根 + 手工搬树 | ❌ app 里没人能点, 还是"读不到现实里的上级" |

---

## 4. 影响

- **migration**: `drizzle/0017_multi_root_promote.sql` (+ `down/`); `pnpm db:compat` 通过 (0 error/0 warning)
- **schema**: `franchisee.root_id` + `idx_franchisee_root`; `franchise_placement_request.kind` 扩到 `create|unjoin|promote`
- **查询**: 5 处子树/归属判定加同树限定 (见 §2.1 表)
- **API**: `POST /api/franchisees/placement-requests` 接受 `kind='promote'` (`targetParentId` 免传)
- **Flutter**: 客户图谱底部「**认领上级**」按钮 (**仅树根可见**) → 填上级姓名/手机 + A线/B线;
  「加盟落位确认」页 `summary` 增加 promote 文案; `PlacementRequest.resultFid` 透出执行结果
- **冒烟**: `scripts/smoke-upline-promote.ts` (26 项全过) — 含"另一棵树没被动过"+"图谱不跨树"+"节点无重复行"

## 5. 风险 / 遗留

- `referrer_id` **双重语义** (推荐人 vs 点位父节点) 依然存在 —— `admin-users` 图谱改用
  `path 去尾段 + root_id` 后**不再依赖** `referrer_id` 当父节点, 但 `placeNewFranchisee` /
  `getFranchiseeTree`(推荐树口径) 仍按 `referrer_id` 连。彻底拆字段属后续独立课题。
- promote **不做上限校验** (ADR-0011 层级不限); 极端"公司体系 30 层"会反复挪 path ——
  子树规模 << 全库规模, 实测 3 节点子树一次 `UPDATE` 即可。
- 上级 U 若长期不注册, 单子 72h 自动失效 (与既有 `PLACEMENT_TIMEOUT_HOURS` 一致)。

## 6. 关联文档

- 需求原文 + 拍板: `docs/backlog.md` ①(建根) / ⑤(多根) · `CHANGELOG.md`
- 落位状态机: `docs/placement-confirmation-design.md`
- 元宪法: [CHARTER §4 域划分](../CHARTER.md) · AGENTS §6.5 (管理员账号) / §6.6 (建号不变量)

## 7. 元数据

- 拍板人: 主人 (2026-09-21)
- 实施: 2026-09-21 (migration 0017 + 5 处查询 + promote 状态机 + Flutter 入口 + 26 项冒烟)
