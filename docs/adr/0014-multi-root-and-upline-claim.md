# ADR-0014: 多根加盟树 (root_id) + 向上认领上级 (kind=promote)

> **状态**: ✅ Accepted (主人 2026-09-21 拍板)
> **日期**: 2026-09-21
> **影响范围**: `franchisee` 结构 (新增 `root_id`) · 子树可见性查询 · 落位状态机 (新增 `kind='promote'`) ·
> 图谱/客户「加盟」判定 · 管理员用户图谱 · `franchise_placement_request.upline_fid` (认领已有节点) ·
> 客户图谱「上层点位」那一格
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

### 3.2 决策: 新增 `kind='promote'` (向上认领) —— 两种情形统一成「把我这棵树挂到 U 的一个空位」

```
现根 A 发起「认领上级」: 只填 U 的姓名+手机号 (⚠ 不选线, 见 §3.6 拍板 ④)
   ↓ 双方确认: A (发起人, 自动 1 票) + U 本人 (注册登录后在「加盟落位确认」点同意;
              她同意时**顺便挑一条自己的空位线**)
执行 (事务内):
   0. 解析 U:
      ① upline_fid = null → U 不在 app 里 → INSERT U (path='', depth=0,
         referrer_id = A 原推荐人, root_id 稍后自指)
      ② upline_fid = U.id → U **已在 app 里** (可能属于别的树/别的枝) → **复用他现有节点**,
         不新建副本 (migration 0018 加的列)
   1. uplineRootId = U.root_id ?? U.id;  newBasePath = U.path + ('L.'|'R.')
      depthShift   = U.depth + 1
   2. UPDATE 我的树: placement_path = newBasePath || path,
                    placement_depth = depthShift + depth,
                    root_id = uplineRootId      WHERE root_id = 我的旧根
   3. A.placement_side = 上级挑的那条线      (⚠ 不动 A.referrer_id: 推荐关系不变, 与 Q5 一致)
   4. **只有情形 ① 才** U.root_id = U.id (自指) + 发推荐奖励 (复用旧节点不算新增加盟商)
   5. linkAccountAndCustomer(U) 补绑账号 + 客户档案 (情形 ② 也要补: 老 seed 节点常常没绑)
```

结果:

| 情形 | 结果 |
|---|---|
| ① U 不在 app 里 | **U 成为新根, A 整棵子树整体下降一层** |
| ② U 已在 app 里 | **两棵树在这里合并** (A 那棵挂到 U 的空位, 以 U 所在那棵为宗) |

两种情形可以反复执行 → 一层层往上同步公司现有体系。

### 3.2.1 为什么要支持「认领一个已在 app 里的节点」(拍板 ③ 落实)

主人: 「一个人**已经在别的树里是节点, 可以被认领为我的上级**, 前提是这个人的一层 2 个点位必需有空位。」
同一家公司的加盟体系被同步进 app 时, U 很可能**已经被别人 (她的另一条下线) 拉进来了** ——
这时再"新建一个 U 的副本"就会出现两个 U 节点 (同一现实人两处存在), 点位关系全乱。
所以: 查到手机号已有节点 → 复用, 只做"两棵树合并"。

### 3.3 为什么确认方是「双方」而不是三方

promote 里 A 就是 U 在 app 内**唯一的邻接已加盟节点** —— 正是老规则
「父节点 == 设置者 → 双方」的那条豁免 (promote 的 `target_parent_fid` 存的就是锚点 A,
于是 `requiredRoles(A, A)` 自然给出 `['initiator','new_franchisee']`, **代码零特例**)。

**老的三方确认 (往下生长) 完全不变**: 本次只**新增** kind, 没动 `create` / `unjoin`。

### 3.4 边界 (硬校验)

- 只有**树根**能发起 (`placementPath === ''`) —— 等价于「**我的上层点位空着**」;
  中间节点上面已有 app 内上级 (她的那格画着人), 没有权限再拉一个
- 管理员**不能**代发起 (管理员无加盟节点, promote 的锚点必须是自己)
- 不能把自己认领为自己的上级
- 被认领的 U **已在同一棵树里** → 拒 (会成环)
- 被认领的 U **已是加盟节点但没有可登录账号** → 拒:
  「还没有可登录的账号 —— 认领必须他本人在「加盟落位确认」里点同意, 请先让他注册登录」
  (手机号匹配 `user.phone_hash` + `is_active`; 空账号的历史/脚本节点点不了同意)
- 被认领的 U **一层两个点位都有人** → 拒 (「这位加盟商下面的两个点位都已经有人了」)
- 同一个根同时只能有 **1 张** pending 认领单; 同一个上级同时也只能有 **1 张** (避免两个枝抢同一个空位)
- ⚠ **上层一旦有人就不能撤换** (主人拍板 ②): 全仓**没有任何**「换上层」入口 ——
  `referrer_id` 不动、`placement_side` 不动、promote 单是 **pending 期专属**;
  真要调整只能**联系系统管理员协商处理** (运营层人工处理, 不落成 app 功能)
- 预占唯一索引 `idx_placement_pending_slot` 收紧为 `WHERE status='pending' AND kind='create'`
  (unjoin 本就不占新位; promote 的 `target_parent_fid` 是"锚点"而非空位, 不该占用锚点子位)

### 3.5 候选评估

| # | 方案 | 结论 |
|---|---|---|
| **A** | 新增 `kind='promote'`, 原树整体下降一层, 新根上移 | ✅ **采纳** — 结构真实反映公司体系 (U 是 A 的上级), 老流程零改动, 可反复上溯 |
| B | U 自己成为**另一棵独立的根** (多根并存) | ❌ 丢了 U→A 的父子关系, 与"同步公司现有加盟树"的目标相悖 (只适合"完全不同的加盟系统") |
| C | 只允许 admin 建新根 + 手工搬树 | ❌ app 里没人能点, 还是"读不到现实里的上级" |

---

### 3.6 追加拍板 (2026-09-21 同日第二轮, 主人原话)

> ①「**『上层』= 点位父, 不一定是推荐码提供人。**」
>
> ②「**上层一旦有人不能撤换, 除非联系系统管理员协商处理。**」
>
> ③「**一个人已经在别的树里是节点, 可以被认领为我的上级, 前提是这个人的一层 2 个点位必需有空位。**」
>
> ④「**认领时『我在上级的 A线/B线』不在我的考虑范围, 我在我的上级是处于 a线还是 b线由我的上级自己决定。**」
>
> ⑤ (关于"根用户看到别的节点") 「**这应该不是问题吧; 如果位于第 10 层的 x 将位于第 9 层的 y 拉入
> 自己的下线 …… y 的隶属关系图谱上自然会显示所有属于 x 的节点 (包括 x 本身); 这根本不是问题, 而是理当如此。**」

落地:

| 拍板 | 落点 |
|---|---|
| ①「上层 = 点位父」 | `getPlacementUpline(fid)` 按 `placement_path 去尾段 + 同 root_id` 找, **不用 `referrer_id`**; 图谱「上层」格显示的就是它 |
| ② 不可撤换 | 用户侧**无**换上层入口 (见 §3.4 末条); 图谱上层格点开只读 (标题栏明写"确需调整请联系系统管理员"); **管理员有唯一的人工例外通道** → 见 §3.8 |
| ③ 可认领已有节点 | `upline_fid` 列 (migration 0018) + 两棵树合并 (见 §3.2.1) |
| ④ 线别由上级定 | 发起时**免传 side**; `decidePlacementRequest(id, actor, decision, ctx, side?)` 新增第 5 参; 上级两条都空时必须给 side, 只剩一条空位则自动落那一条 |
| ⑤「理当如此」 | `root_id` 的用途只有一条: **互不相干的两棵树之间不串**; 同一棵树内根用户看到自己枝上的全部节点 (含被拉进来的上级) 是**正确行为, 不是 bug** |

#### 3.6.1 上层点位与「谁有权去拉一个上级」的完整分支 (主人原话收敛)

| 用户的来路 | 上层点位 | 能不能去认领上级 |
|---|---|---|
| 管理员**建根**拉起的点位 | **虚位以待** | ✅ 可以, 且**仅可以**拉一位 |
| 被其他加盟用户经三方确认拉进来的 | 加入时就有明确上级 (确认里含父节点) | ❌ 没有权限 (她上面有人) |
| 被**自己的下线**认领进来的 (y 被 x 认领) | 加入时**虚位以待** (x 的锚点在她上面, 她自己的上层还空着) | ✅ 可以 |
| 被认领进来后又有人认领她 | 已有人 | ❌ (不可撤换) |

落到代码就是一条判断: **`placement_path === ''` ⟺ 上层点位空 ⟺ 是树根 ⟺ 可认领**。

---

### 3.7 追加拍板 (同日晚些, 主人原话)

> 「**无账号节点为什么要存在? 不能禁止/消除无账号节点吗, 要成为节点首先必需有账号。**」

#### 3.7.1 为什么会有"无账号节点"

历史包袱, 不是设计:

| 来源 | 情形 |
|---|---|
| 早期 `scripts/seed-test-data.ts` | 直接 `POST /api/franchisees`, 那时**没有**账号门槛 → 31 个节点只有 2 个账号 |
| 老 web admin / 手工 SQL | 直接 `INSERT franchisee` 绕过一切 |
| 三方确认落位 | ✅ 这条**本来就**要求"本人用该手机号登录过", 不会有孤儿 |

#### 3.7.2 决策: 三道闸, 从"没人管"到"物理上不可能"

| 闸 | 落点 | 语义 |
|---|---|---|
| ① **新建硬门槛** | `requireAccountForNode(exec, phoneHash)` —— `franchisee.ts::createFranchisee` + `franchisee-placement.ts` 的 `create` / `promote` 两条路径 | 目标手机号没有 active 账号 → 直接抛人话错误, 事务回滚 (`assertNodeHasAccount` 建完再自检一次) |
| ② **注册自愈** | `adoptOrphanNodeForNewAccount()` (由 `registration.ts` 在建号事务内调用) | 老孤儿节点遇上同手机号的新注册 → **自动绑上**, 不新建重复节点。她本来就是树里的人 |
| ③ **巡检 / 处理** | `npx tsx scripts/audit-orphan-nodes.ts [--bind] [--prune]` | 只报清单 (默认) / 补账号 (`--bind`, 走正规建号入口) / 软删**没有下线**的 (`--prune`)。有下线的必须人工处理 |
| ④ **不可被搬** | `franchisee-reparent.ts` 两方都查账号 | 没账号的节点既当不了上层, 也搬不了 —— 逼着先解决账号 |

**存量处置 (dev 库, 2026-09-21)**: 29 个 `SeedTest-*` 无账号节点 → `--bind --password=dev123456`
全部补齐 (29/29 认领成功), 现 `audit-orphan-nodes.ts` 输出「✅ 没有无账号节点」。
根因也修了: `seed-test-data.ts` 现在**每个节点先建账号再建节点** (账号手机号 = 节点手机号)。

参 `scripts/audit-orphan-nodes.ts` 头部注释 + AGENTS §6.6 (建号不变量) / §6.7 (本节沉淀)。

### 3.8 追加拍板: 管理员「协商处理后强改上层」

> 「**给管理员一个『协商处理后强改上层』的后台功能。**」(承接 §3.6 拍板 ②)

#### 3.8.1 为什么必须单独开一个口子

用户侧的正规改上层路径只有两条, 都盖不住真实运营需要:

| 现有路径 | 覆盖范围 | 盖不住的 |
|---|---|---|
| 三方确认 (落位时定) | **入树那一刻**定位置, 之后不动 | 上层后来填错 / 现实里换了上级 |
| 认领上级 (promote) | 只对**树根**开放 (上层虚位以待) | 上层位子已经有人 → 正是拍板 ② 说的"不能撤换" |

**为什么不塞进 `franchise_placement_request`**: 三方确认的价值 = 三方都点头; 而本功能的前提就是
**三方谈不拢**。塞进同一状态机会给"单方即执行"开一条分支 —— 后续改动最容易在这里被滥用
(同 `createRootForUser` 为什么不塞进去的理由)。

#### 3.8.2 设计

| 维度 | 决策 |
|---|---|
| 契约 | `POST /api/admin/nodes/[fid]/reparent` `{ newParentFid, side, reason }` |
| 鉴权 | `role=admin`, **服务端每次查库** (客户端藏按钮只是体验) |
| 留痕 | `reason` **必填 2-200 字** → 追加到她的加密备注 (`[日期 管理员改上层] 从 X → Y 的A线: 原因`) + `audit_log` (本次同时给 `franchisee` 表补上了审计触发器 —— 之前这张表**一行审计都没有**) |
| 动什么 | 整棵子树: `placement_path` / `placement_depth` / `root_id`; 顶层节点再加 `referrer_id` + `placement_side` |
| 硬拒 | 成环 (新上层在她自己下线里) / 那条线有人 / 她本来就在那 / 任一方没账号 / root_id 缺失 / 原因太短 |
| 副作用 | **`mergedTrees=true` = 两棵树在这里合并** (把孤立的那棵挂到主树上), 返回值带合并后的树数量 |

**path 变换的坑 (踩过)**: 不能简单 `新基路径 || 老路径` —— 换线 (A↔B) 时顶层节点自己那段要丢掉,
只有后代保留相对后缀。正解 = `新基路径 || substring(path from len(旧顶层path)+1)`;
树根搬迁时旧 path 为空 → 后缀 = 全部 → 整棵树按原结构下降一层 (与 promote 同效)。
另: SQL 里这个起始位必须显式 `::int`, 否则 PG 会挑中 `substring(text from text)` (正则版) → 匹配不上直接给 `NULL`。

#### 3.8.3 已知取舍 (待主人拍)

`franchisee.referrer_id` 在现 schema 里**同时**是「推荐人」和「点位父」(§5 第 1 条遗留):
`placeNewFranchisee` 的槽位判定用它, Flutter 详情页把它显示成「推荐人」。
强改上层时**只能一起改**, 否则新上层那条线会出现"看着空、其实有人"→ 新节点 path 撞车。
要「只改点位父、不动推荐人」必须拆列 (`placement_parent_id`), 属 schema 变更 → 已记 backlog。
原值不丢: `audit_log.changed_fields` 里有改前的 full row。

---

## 4. 影响

- **migration**: `drizzle/0017_multi_root_promote.sql` + `drizzle/0018_placement_upline_fid.sql` (+ `down/`)
- **schema**: `franchisee.root_id` + `idx_franchisee_root`; `franchise_placement_request.kind` 扩到
  `create|unjoin|promote`; `franchise_placement_request.upline_fid` + `idx_placement_upline_fid`
- **查询**: 5 处子树/归属判定加同树限定 (见 §2.1 表); 新增 `getPlacementUpline` / `getMyPendingPromoteRequest` /
  `freeSidesOf` / `roleFor(uplineFid)`
- **API**:
  - `POST /api/franchisees/placement-requests` 接受 `kind='promote'` (**`targetParentId` 与 `side` 都免传**)
  - `POST .../placement-requests/:id/decide` 接受可选 `side` (仅 promote 单的上级本人用; 见拍板 ④)
  - `GET /api/franchisees/me/tree?mode=placement` 顶层新增 `upline` (我的点位父, null = 虚位以待) +
    `uplineRequest` (我发起的 pending 认领单); `PlacementRequestView` 新增 `uplineFid` / `uplineName` /
    `availableSides`
- **Flutter**:
  - 客户图谱: 「我」正上方永远留一格**上层点位** (有人画人 + 连线; 空着画虚线「＋ 上层 · 虚位以待」;
    已发起认领画虚线「待她确认」) → 点它 = 认领/查看; 初始相机改为**对齐上层格** (`_focusRootMatrix(capCenter:)`),
    否则那一格会被顶出屏幕; 「我是加盟商但还没下线」不再被空状态拦住 (要能看到这一格)
  - 图谱底部保留「认领上级」按钮 (仅树根可见); 认领对话框**去掉 A线/B线 选择器**
  - 「加盟落位确认」页: 上级本人同意 promote 单时先挑线 (`needsSidePick` → 底部弹层)
  - 管理员用户管理: 节点弹层 + 已加盟用户弹层各加「**协商处理: 改上层**」→
    `flutter_app/lib/screens/admin_reparent_sheet.dart` (搜人 → 挑 A线/B线 (有人那条禁用并标出占位者)
    → 填原因 → 提交); `AdminNode` 新增 `path` / `rootFid` (选候选上层时算子树与空位)
- **冒烟**: `scripts/smoke-upline-promote.ts` (**36 项全过**) — 含"另一棵树没被动过"+"图谱不跨树"+
  "无重复行"+"认领无账号节点被拒"+"上级挑线"+"两棵树合并后 = 4 节点"
- **冒烟**: `scripts/smoke-admin-reparent.ts` (**35 项全过**) — 9 条拒绝路径 + 非根换上层 (子树整体跟着走,
  原线释放) + 树根挂到别的树 (两棵树合并, 树数量 -1, **无关的第三棵树一点没动**, 图谱无重复行) + 备注/审计留痕
- **数据脚本**: `scripts/audit-orphan-nodes.ts` (巡检 / `--bind` 补账号 / `--prune` 软删无下线孤儿)
- **DDL (非 migration)**: `drizzle/audit_trigger.sql` 补 `franchisee_audit` (幂等, 由 `pnpm db:migrate` 应用)

## 5. 风险 / 遗留

- `referrer_id` **双重语义** (推荐人 vs 点位父节点) 依然存在 —— `admin-users` 图谱改用
  `path 去尾段 + root_id` 后**不再依赖** `referrer_id` 当父节点, 但 `placeNewFranchisee` /
  `getFranchiseeTree`(推荐树口径) 仍按 `referrer_id` 连。彻底拆字段属后续独立课题
  (⚠ 已升级为**必须做**: 见 §3.8.3 —— 否则管理员改上层会连带改写"谁推荐了她"这句话)。
- **审计覆盖不全**: 本次只补了 `franchisee` 一张表的触发器; 库里还有若干表没有 `*_audit`
  (如 `customer` 有, 但字典/服务项等没有)。属独立课题。
- promote **不做上限校验** (ADR-0011 层级不限); 极端"公司体系 30 层"会反复挪 path ——
  子树规模 << 全库规模, 实测 3 节点子树一次 `UPDATE` 即可。
- 上级 U 若长期不注册, 单子 72h 自动失效 (与既有 `PLACEMENT_TIMEOUT_HOURS` 一致)。

## 6. 关联文档

- 需求原文 + 拍板: `docs/backlog.md` ①(建根) / ⑤(多根) · `CHANGELOG.md`
- 落位状态机: `docs/placement-confirmation-design.md`
- 元宪法: [CHARTER §4 域划分](../CHARTER.md) · AGENTS §6.5 (管理员账号) / §6.6 (建号不变量)

## 7. 元数据

- 拍板人: 主人 (2026-09-21; 同日第二轮补充 5 条 —— 见 §3.6)
- 实施: 2026-09-21 (migration 0017/0018 + 5 处查询 + promote 状态机 + 图谱上层格 + 35 项冒烟)
