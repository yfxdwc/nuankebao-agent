# 客户标识体系 v1 — 暖客宝「一个人 = 多个面」在 UI 上的统一口径

> **状态**: v1.3 — 2026-09-25 主人拍 D3-D9; R-12 系列 IDOR P0 已修 (follow-up-analysis + follow-ups + interactions/wellness-records); 2 轮 reviewer 复审 P0/P1 已消化 (b1/b2 NULL 守卫 · (c) 跨枝防护 · migration 编号修正 · S6/S7 · ownership 第 6 态)
> **定位**: 销售员每天看的「客户列表 / 客户详情 / 加盟图谱 / 新建客户表单」四屏必须使用同一套标识口径。本文件是这一套口径的**定稿**,代码改动前必读。
> **配套**: 术语消歧见 [`docs/adr/0015-subject-model.md`](./adr/0015-subject-model.md) ·
> 身份锚点见 [`docs/adr/0016-identity-anchor.md`](./adr/0016-identity-anchor.md) ·
> 视觉密度 / 容器规则见 [`docs/ui-principles.md`](./ui-principles.md) ·
> 操作层协作见 `AGENTS.md` §6.6 / §6.6.1 / §6.7 / §6.8
>
> **本文不重复治理哲学**: 模型口径以 ADR-0015 为准;UI 棘轮以 ui-principles.md 为准;本文件只负责**把它们映射成一组可见的标识 + 一组可执行的判定函数 + 一组分阶段验收 + 一套上级推送机制**。

---

## §0 背景与范围

**一句话**: 统一「客户/加盟者」在列表、档案、图谱、表单上的标识口径,让销售一眼分清"**谁的人**、**什么身份**、**该不该跟**、**从哪来**"。

**问题 (2026-09-22 复盘)**: 同一行客户上,图谱画的是"我的直推"(读 `franchisee.referrer_id`),客户列表筛的是"我的子树"(读 `placement_parent_id`),档案里又写"上级加盟人"(读 `placement_parent_id`)。三种口径同屏打架,销售员看到的是 **三个不同的"她是谁"**。

**范围**:

- ✅ **6 维标识** 口径 (加盟/细分/会员/注册/归属/来源)
- ✅ **视觉语法 5 层** 在 Flutter 列表 / 详情 / 表单 / 图谱、Web admin 列表/详情/表单 的映射
- ✅ **数据模型 additive** 改动 (1 个 migration + 1 个 customer_share 表)
- ✅ **"选择直推者"** 最小改动清单 (落位申请的 referrer 入参)
- ✅ **「上级推送」机制** (`customer_share` 表, Phase D 实施)
- ❌ AI 跟进话术 / 报表 — 单独路线, 不在本文范围
- ❌ 跨端类型代码改造 — 见 §8 Phase A 边界
- ❌ RBAC 扩围 + 上级推送的具体落地 — 需独立 RBAC/隐私评审, 见 §8 Phase D

---

## §1 六维标识体系

> **原则 (原则 5: 颜色是信号)**: 每个维度**只用一个真相源**;每个标识**色 + 文字双编码**;优先级 = **L1 身份 → L2 归属 → L3 行动 → L4 来源 → L5 树内关系** (从"她是谁"到"她在图里",从静态到动态)。

| # | 维度 | 取值 | 唯一真相源 (file:line) | 存储 / 派生 | 展示条件 |
|---|---|---|---|---|---|
| **1** | 加盟身份 | 加盟 / 未加盟 | `franchisee` 表存在活动节点 | 派生 (`franchisee.deleted_at IS NULL`) | 头像环 (`customer_row.dart:258` TypedUserAvatar) |
| **2** | 加盟细分 | 直推 / 非直推 | `franchisee.referrer_id` 指向 viewer 自身 | 派生 (参见 §2 拍板, supersede 现 placement 口径) | 与加盟同处: 列表/详情头像环区分 (§4 L1), 详情类型卡文案 `加盟·直推` / `加盟·非直推`; 图谱另用 `直推` / `下级引荐` / `上级引荐` (同一真相源) |
| **3** | 会员 | 会员 / 免费 | `src/lib/billing/member-flag.ts:30` `memberFlagOf` / `:55` `memberExistsSql` | 派生 (`role='admin'` 或 `member_until > NOW()`) | 头像金环 + 👑 (`customer_row.dart:267`) |
| **4** | 注册 | 已注册 / 未注册 | `src/lib/db/queries/customer-scope.ts:56` `hasAccountSql` | 派生 (`EXISTS user WHERE customer_id = customer.id`) | "已注册" 标 (`customer_row.dart:310`) |
| **5** | 归属 | 我的客户 / 下级的客户 / 上级推送的客户 / 他人客户 / 无归属 | `customer.owner_id` + 树关系 + `customer_share` (`schema.ts:450 owner_id`, ADR-0015 Q11 + §6.5) | **混合** (owner_id 列 + `placement_path` 派生层级 + `customer_share` 推送表) | 归属卡 (`AppBadge` tone=info/neutral,§4 L2) |
| **6** | 来源 (新增) | 亲友 / 转介绍 / 陌生拜访 / 地推 / 未填写 | 新增列 `customer.acquire_source` (待 migration 0026) | **显式** (表单勾选 / 转介绍展开介绍人必填) | 来源短词 badge (仅非空,§4 L4) |

**行动维 (维持现状,单独列)**: 跟进紧急度 `p0`-`p4` 由 `src/lib/follow-up/urgency.ts:17` `UrgencyLevel` + `:68` `CONTACT_GAPS` 单一计算;推荐标签由 `:357` `pickFollowUpTags` 挑最多 2 个 (1 动作 + 1 日历)。详见 §4 L3。

**派生边界 (硬规则)**:

- 维度 1/3/4/5 都是派生,**不落库布尔** — 改判定规则时同步改 SQL 与 JS 两版 (`member-flag.ts:13` 注释明示)。
- 维度 5 (归属) 派生所需**两个真相源**:
  - `customer.owner_id` 列 (本人/下级 — §3.4 可见集合 a+b)
  - `customer_share` 推送表 (上级推送 — §3.4 可见集合 c, 见 §6.5)
  - 「下级的客户」与图谱可见性同源 (`getUplineAncestors(fid, 3)` + 同一枝的 `placement_path` 后代),便于将来收窄为「仅直接下级」时**只动 `customer-scope.ts` 一处**。
- 维度 6 是**显式落列** — 来源是用户输入,不是事实推导;不来自任何派生列。
- 客户类型从"加盟 / 种子 / 普通"三态简化为「**加盟 / 未加盟**」二态 — 种子类型轴**退出**(D3),代码层彻底移除,DB 列暂不 DROP,处置见 §5.4。

---

## §2 直推语义 (核心 supersede)

### 2.1 拍板 (2026-09-25)

> **直推 = `franchisee.referrer_id = 我的 fid`**,即"谁把她带进加盟的人"。
>
> **本口径 supersede 2026-09-22「列表加盟 = 点位父 = 我」** 的旧拍板。

**为什么 supersede** (核心矛盾):

`src/lib/db/queries/customer.ts:522-526` 当前实现的口径是:

```text
// 客户类型筛选 (胶囊按键, 主人 2026-09-18 拍) — 跟 resolveCustomerType 严格对齐:
//   加盟 = 我的**直推**加盟商 (点位父 = 我; 主人 2026-09-22 拍, 不再算整个子树);
```

但图谱 (`src/lib/db/queries/franchisee.ts:450` `classifyRelation`) 区分 `direct` 时用的是 `referrer_id === ctx.rootId`:

```typescript
function classifyRelation(
  nodeId: string, referrerId: string | null, ctx: BuildCtx
): TreeNodeRelation {
  if (nodeId === ctx.rootId) return "root";
  if (referrerId == null) return "upline";
  if (referrerId === ctx.rootId) return "direct";   // ← 直推 = referrer 口径
  return ctx.subtreeIds.has(referrerId) ? "downline" : "upline";
}
```

**后果**: 一位"推荐人是 A、点位父是 B" (BFS 顺延) 的节点,**图谱说直推、列表说非直推**,同屏矛盾。 supersede 后两处统一读 `referrer_id`。

### 2.2 三条不变量 (拍板后永不变)

| # | 规则 | 含义 |
|---|---|---|
| **I-1** | 直推者必然是她的上级 | 落位后直推者一定是 `placement_path` 祖先链上的人 (来自 AGENTS §6.8 拆栏) |
| **I-2** | 直推者 ≠ 点位父 (允许) | 推荐人那侧满了 → BFS 顺延, `referrer_id` 与 `placement_parent_id` 不同 (`franchisee.ts:188-190` 注释 + `audit-placement-integrity.ts:103` 已报) |
| **I-3** | 默认直推者 = 发起人 (落位申请) | `franchisee-placement.ts:1186` `referrerId: raw.initiatorFid` 写死 — 落位执行时直推者默认是发起人;**唯一可改点 = 落位申请时显式选择** (见 §6) |

### 2.3 影响范围 (代码改动列表)

| 位置 | 旧 | 新 | 备注 |
|---|---|---|---|
| `customer.ts:535-540` 类型筛选 | `placement_parent_id = viewerFranchiseeId` | `EXISTS franchisee WHERE deleted_at IS NULL AND referrer_id = viewerFranchiseeId AND u.customer_id = customer.id` | supersede 拍板的核心改动 |
| `customer.ts:159-165` `resolveCustomerType` | 接受 `isMyDirectDownlineFranchisee` | 同函数签名,内部口径变 | 无 API 变化 |
| `customer-scope.ts:27-49` `directDownlineFranchiseeSql` | `placement_parent_id = myFid` | `referrer_id = myFid` (且 deleted_at IS NULL) | **单一真相源,多处共用** |
| `franchisee.ts:407` `TreeNodeRelation` | 不变 | 不变 | 本来就读 `referrer_id`,无需改 |

---

## §3 判定口径 (唯一真相源 — 拟 `src/lib/customer/identity.ts`)

### 3.1 函数契约

```typescript
// src/lib/customer/identity.ts (拟 — Phase A 落地)
export interface CustomerIdentity {
  affiliation: "none" | "direct" | "nondirect";  // 维度 1+2 合并
  ownership: "mine" | "subordinate" | "upline" | "other" | "none";  // 维度 5
  member: boolean;    // 维度 3
  registered: boolean; // 维度 4
  source: { kind: AcquireSource; referrerName: string | null };  // 维度 6
}

export async function resolveCustomerIdentity(
  customerId: bigint,
  viewer: ViewerContext
): Promise<CustomerIdentity>;
```

### 3.2 SQL 伪码 (与现 `customer-scope.ts` 一致风格)

| 判定 | SQL 表达式 | 唯一真相源 |
|---|---|---|
| **加盟直推** | `EXISTS (SELECT 1 FROM franchisee f JOIN "user" u ON u.franchisee_id = f.id WHERE f.deleted_at IS NULL AND u.customer_id = ${customer.id} AND f.referrer_id = ${viewerFid})` | supersede 后口径 (§2) |
| **加盟非直推** | 加盟 ∧ ¬直推 (落在可见树内: viewer 子树 `root_id` 同 + `placement_path` LIKE) | derived from 直推 + 可见性 |
| **会员** | `role='admin' OR membership.member_until > NOW()` | `member-flag.ts:55` `memberExistsSql` |
| **已注册** | `EXISTS (SELECT 1 FROM "user" u WHERE u.customer_id = ${customer.id})` | `customer-scope.ts:56` `hasAccountSql` |
| **归属** | `customer.owner_id = ${viewerUserId}` | `customer-scope.ts:73` `ownedByUserSql` |
| **来源** | `customer.acquire_source` (待 migration) | 新增列 |

### 3.3 边界规则 (硬约束)

| # | 规则 | 错误案例 |
|---|---|---|
| **B1** | 所有 identity SQL 必须 `franchisee.deleted_at IS NULL` | 软删节点仍被判"加盟直推" = 离岗销售看到死人 (已有 `customer-scope.ts:44` 防护) |
| **B2** | viewer 无加盟节点 (`franchiseeId = null`) → `affiliation` = `none`,`ownership` 只可能 `none` / `mine`,禁止 `null` | 返回 `null` = 调用方必须 nullable 处理 = bug 温床 (与 `customer-scope.ts:18` 现有规则一致) |
| **B3** | "**直推**" 一词**只允许表示 `referrer_id` 口径**;禁止再用 "点位父 = 我" 叫直推 (该口径已 supersede, §2)。档案/列表写 `加盟·直推` / `加盟·非直推`,图谱写 `直推` / `下级引荐` / `上级引荐` —— 两者是**同一真相源的两种视图**,不是两套判定 | 两处各用一套口径 = "图谱说直推、档案说非直推"同屏矛盾 (§2.1 旧实现实证) |
| **B4** | 手机号 mask 以 **§3.4 分级表为唯一真相源**: `ownership ∈ {subordinate, other, none}` 一律走 `maskPhone` (`utils.ts:24`); **明文例外两类** = `mine` / `direct_downline`; `upline_shared` 按 D8 (2026-09-25) = 明文 | "他人客户" 显示完整手机号 = 隐私泄漏 + 违反 AGENTS §3 红线 |

### 3.4 列表可见集合 RBAC (维度 5 归属 → 可见性口径)

> **v1.2 修订 (2026-09-25, reviewer 评审后)**: 本节 v1.1 的 (b) 子句有 **2 处阻断级错误** —— ① SQL 前缀拼接错 (`me.placement_path || sub.id`) 导致永不匹配 (placement_path 是 `'L.R.'` 形式的字母路径, 不含节点 id; 正确模式见 `src/lib/auth/rbac.ts:196`); ② 语义错 (写的是「下层的**本人档案**」, 而 D4 要的是「下层**归属的客户**」)。本版拆成 (b1) 保留 + (b2) 新增。
>
> **本节 supersede `myCustomerScopeSql` (src/lib/db/queries/customer-scope.ts 的两段式) 现有口径** — 在 Phase D 实施前不要动现有函数, 本文只做口径定义 + Phase D 接入点指定。

**口径定义** (D4 + §6.5 上级推送落地后, 列表/详情/概览/行级过滤**四处同一真相源**):

```
listVisibleFor(viewer) =            -- me = viewer 的 franchisee 行
  -- ★ v1.3 前置硬守卫 (reviewer P0): viewer.franchisee_id IS NULL → 只允许 (a)
  --   否则 `f.placement_parent_id = NULL` 会命中所有根节点 → 未加盟 viewer 看到全部根节点档案
  viewer.franchisee_id IS NOT NULL ? (
  (a)  customer.owner_id = viewer.user_id                     — 我的客户
  ∨ (b1) EXISTS (                                             — 我的下层加盟节点本人档案 [结构口径, 保留]
        SELECT 1 FROM franchisee f
        JOIN "user" u ON u.franchisee_id = f.id
        WHERE f.deleted_at IS NULL AND f.placement_parent_id = viewer.franchisee_id
          AND u.customer_id = customer.id)
  ∨ (b2) customer.owner_id IN (                               — 我的下层归属的客户 [新增]
        SELECT u.id FROM "user" u
        JOIN franchisee sub ON sub.id = u.franchisee_id
        WHERE sub.deleted_at IS NULL
          AND sub.id <> viewer.franchisee_id                  -- 排除自己
          AND sub.root_id IS NOT DISTINCT FROM me.root_id     -- 同树 (多根防护)
          AND (me.placement_path = '' AND sub.placement_path <> ''
               OR me.placement_path <> '' AND sub.placement_path LIKE me.placement_path || '%'))
  ∨ (c)  EXISTS (SELECT 1 FROM customer_share cs              — 上级推送的客户
                 WHERE cs.customer_id = customer.id
                   AND cs.to_user_id  = viewer.user_id
                   AND cs.revoked_at IS NULL
                   AND EXISTS (SELECT 1 FROM "user" r WHERE r.id = cs.to_user_id AND r.is_active = true)
                   -- ★ 推送人停用 → 推送失效 (与 §6.5.3 「双方都必须对应活账号」文字对齐)
                   AND EXISTS (SELECT 1 FROM "user" f WHERE f.id = cs.from_user_id AND f.is_active = true)
                   -- ★ P0-B (reviewer 第二轮): 推送人必须与我在同一棵树
                   --    否则我在被 admin 强改上层搬走后, 旧推送仍会命中 (跨枝隐私泄漏)
                   AND ( NOT EXISTS (SELECT 1 FROM "user" f
                                     WHERE f.id = cs.from_user_id AND f.franchisee_id IS NOT NULL)
                         OR EXISTS (SELECT 1 FROM "user" f
                                    JOIN franchisee ff ON ff.id = f.franchisee_id
                                    WHERE f.id = cs.from_user_id AND ff.deleted_at IS NULL
                                      AND ff.root_id IS NOT DISTINCT FROM me.root_id) ))
  ) : ( (a) )
```

> **(b1) 为什么不能叫“直推加盟商”** (reviewer P1): (b1) 读的是 `placement_parent_id` = **结构口径**，而 §2.1 已拍「直推 = `referrer_id`」。为避免与 §9.1 INV-2 矛盾，全文统一称 **(b1) = 我的下层加盟节点本人档案**。

> **(c) 的四个隐含条件** (评审补): ① 接收人账号必须 active (停用即失效, 与 §6.5 SHARE-4 一致); ② **推送人必须与我在同一棵树** (P0-B: 不加这条, 我被 admin 强改上层搬走后旧推送仍可见 = 跨枝泄漏; admin 无节点时豁免); ③ 推送人节点软删 (`ff.deleted_at IS NOT NULL`) 时推送失效; ④ **推送人账号停用**时推送失效 (与 §6.5.3 文字一致)。四条都要进巡检。

**集中点**:`src/lib/db/queries/customer-scope.ts` 一处 —— Phase D 落地时在该模块顶部加注释明示"`viewerCustomerScopeSql()` 走 a+b1+b2+c 四段" (现该函数尚未存在, 属 Phase D 新增)。将来要收窄为「仅直接下级」时,**只动 (b2) 子句**, 调用方 (列表 / 胶囊计数 / `/api/me` 概览 / 行级过滤) 零改动。

**三段语义** (与图谱可见性同源 — `src/lib/db/queries/franchisee.ts` `getUplineAncestors(fid, 3)` + 同一枝 `placement_path` 后代):

| 段 | 名字 | 真相源 | 取值 |
|---|---|---|---|
| (a) | 我的客户 | `customer.owner_id` (列) | 单值等式,O(log n) 索引 |
| (b1) | 我的下层加盟节点**本人档案** | `franchisee.placement_parent_id = 我` + `user.customer_id` | **现状保留** (结构口径; §6.6.1 Q2 原文); ⚠ 已要求前置 NULL 守卫 |
| (b2) | 我的下层**归属的客户** | `customer.owner_id IN (下层 user.id)` | **新增**;同树 + 排除自己 + `placement_path` 前缀 |
| (c) | 上级推送的客户 | `customer_share` 表 (`to_user_id` + `revoked_at IS NULL` + 接收人 active) | 推送存在性;`owner_id` 不变 |

**手机号分级** (与 B4 一致, 集中声明):

| 归属取值 | 手机号展示 |
|---|---|
| `mine` 我的客户 (a) | **明文** (viewer 是归属人, 自己看自己客户 = 默认知情) |
| `direct_downline` 我的直推加盟商本人 (b1) | **明文** (她是我的直推下线, 日常要能直接联系) |
| `subordinate` 我的下层归属的客户 (b2) | **maskPhone** (`src/lib/utils.ts:24`, 输出永不等于输入 — 回归测试锁住) |
| `upline_shared` 上级推送给我的客户 (c) | **明文** (D8 已拍, 2026-09-25: 推送即授权跟进; 若打码则「推来跟进」名不副实) |
| `other` 他人客户 | **maskPhone** (理论上不出现在列表中, 若出现 = scope 漏检告警) |
| `none` 无归属 | **maskPhone** (兜底: 无归属 ≠ 全可见) |

> ⚠ **E1 的落实是调用方义务** (reviewer P1): 本节四段 SQL **不重复写** `customer.deleted_at IS NULL` —— 由可见性封装函数 `viewerCustomerScopeSql` 在外层统一加，调用方禁止裸拼。同理 `customer_share` **不挂 `deleted_at`**，撤销只走 `revoked_at`。

> ⚠ **ownership 需补第 6 态** (reviewer P1): `(b1)` 命中的行，其 `owner_id` 可能既不是我也不是下层 (例: 归属被 transfer 过)，会被误标成 `other` 并触发「scope 漏检告警」。Phase D 需在 `identity.ts` 的 ownership 枚举里加 **`direct_downline`** (命中 (b1) 时强制覆写)，UI 文案「我的下层加盟节点 · X」。

> ⚠ **Phase D 开工前必查**: `franchisee.root_id IS NULL` 的老存量节点会被 `(b2)` 的 `IS NOT DISTINCT FROM` 排除 → 先跑 `npx tsx scripts/audit-placement-integrity.ts --strict` 看 NULL root_id 数量，多则先补 backfill (reviewer 无法确认存量规模)。

**三条边界** (与 §3.3 B1/B2 一脉相承, 不重复):

- **E1** 所有判定 SQL 必加 `customer.deleted_at IS NULL` (软删客户不出现在任何人的列表)
- **E2** viewer 无加盟节点 (`franchiseeId = null`) → 列表可见集合仅可能 = `(a)` 或空集;**禁止返回 NULL 列表**
- **E3** 任何调用方 (`/api/customers` / `/api/me` / 胶囊计数 / 行级过滤) **禁止自写可见性 SQL**; 一律 `import` `customer-scope.ts` 的 `viewerCustomerScopeSql(viewer)` (Phase D 落地命名)

**口径实施阶段**:
- 当前 (Phase A/B/C): `myCustomerScopeSql` 两段式 (a+b**旧版** placement_parent_id) 维持现状, **不**扩围 (b) 子句到子树
- **Phase D 开工前 (阻塞条件)**: ① 本节 (v1.3) 经 reviewer **第三轮复审通过** (前两轮: 第一轮 P0 SQL 错 + 第二轮 P0 编号撞车/(c) 跨枝/文案不一致均已修); ② D8 + D9 — **2026-09-25 ✅ 已拍**; ③ `toView` mask 分级落地 + 回归测试; ④ R-12 系列 IDOR 已修 (2026-09-25)
- Phase D 落地: (b) 子句 supersede 为 placement_path LIKE + 加 (c) `customer_share` 段 + 统一命名为 `viewerCustomerScopeSql(viewer)`, 接入 `/api/customers` 列表 / `/api/me` 概览 / 胶囊计数 / 行级过滤

---

## §4 视觉语法五层 + 展示位映射

> **原则 4: 容器越少,内容越强** — 每层只用一个组件;**新增徽章 = 必须先过 §1 表中"展示条件"**,不为"看起来差个卡片"加 Card (`AGENTS §5「顺手加个卡片」`反模式)。

### 4.1 五层定义

| 层 | 内容 | 组件 (B 档) | 颜色 tone | 展示位置 |
|---|---|---|---|---|
| **L1 身份** | 加盟·直推 = 实紫环 / 加盟·非直推 = 浅紫环 / 未加盟 = 无环 / 会员 = 金环 + 👑 | `TypedUserAvatar` (`customer_row.dart:258`) | brand (实/浅) / gold / 无 | 头像 (44pt,行首);详情类型卡出全称 `加盟·直推` / `加盟·非直推` |
| **L2 归属** | "我的客户" / "无归属" / "下级的客户 · X" / "上级推送 · X" / "他人客户" | `AppBadge` (B0a,`tone ∈ {neutral, info, brand}`) | brand / neutral / info | 客户详情「归属卡」+ 列表行**仅无归属 / 下级的客户 / 上级推送 显形**(自己的客户静默, 避免同色铺满) |
| **L3 行动** | 左色条 (`p0-p4` 仅会员) + 推荐标签 ≤2 + 🎂 生日 | `Stack` 套色条 + `_FollowUpTagChip` + 🎂 Container | danger / accent / primary | 列表行 (主文尾部 / 第二行 / 头像左侧) |
| **L4 来源** | "亲友" / "转介绍" / "陌生拜访" / "地推" 短词 badge | `AppBadge` `tone=neutral` | neutral (浅灰底) | **仅客户详情「管理 Tab 的档案卡」**; 列表行 + 详情其它区块**不显示** (D6) |
| **L5 树内关系** | "直推" / "下级引荐" / "上级引荐" (B3 硬约束: 与 L1 细分同源, 只是图谱视角) | `TreeNode.relation` 字段 (`franchisee.ts:407`) | brand (直推) / neutral (其他) | **仅图谱画节点标注**;列表/详情不出这三个词 (用 L1 的 `加盟·直推` 文案) |

### 4.2 展示位映射表 (Flutter + Web admin)

| 屏幕 | L1 身份 | L2 归属 | L3 行动 | L4 来源 | L5 树内关系 |
|---|---|---|---|---|---|
| **Flutter 列表行** (`customer_row.dart`) | 头像环 | **5 态**: `mine` 静默 / `subordinate` 显示「下级的客户 · X」/ `upline_shared` 显示「上级推送 · X」/ `none` 显示「无归属」/ `other` 兜底文案 (scope 漏检告警) | 主文 tail (≤2 tag + 🎂,横向滚动兜底 `:159-176`) | **不显示** (D6) | ❌ 不显示 |
| **Flutter 详情** | 头像 | 归属卡 5 态, 与列表同口径 (B4 手机号分级) | "下次跟进: p0 今日" | **仅管理 Tab 的「档案卡」**显示来源行 (短词 + 转介绍展开介绍人); 详情其它位置**不显示** (D6) | ❌ 不显示 |
| **Flutter 新建/编辑表单** | ❌ 录入时无节点 | ❌ 录入时无归属 | ❌ | **插入位置**: 姓名/性别/手机 与 生日 之间; 选填; **选"转介绍"展开介绍人必填** (D5) | ❌ |
| **Flutter 图谱** | 头像 | ❌ 不显示 (图谱本身) | ❌ | ❌ | ✅ 节点侧标 ("直推" / "下级引荐" / "上级引荐") |
| **Web admin 列表** | 头像列 | "归属" 列 5 态 (无归属 / 下级的客户 / 上级推送 高亮; `mine` 静默; `other` 兜底文案) | 待跟进 / p 级 | **来源列删除** (D6) | ❌ |
| **Web admin 详情** | 头 | "归属" 卡 (与 Flutter 详情同口径) | 紧急度卡 | **管理 / 档案区**显示来源 (转介绍展开介绍人); 其它位置**不显示** (D6) | ❌ |
| **Web admin 表单** | — | — | — | **位置同 Flutter** (姓名/性别/手机 与 生日 之间, 选填, 转介绍展开介绍人必填) | — |

### 4.3 棘轮 (B4: 不因新徽章破基线)

- ✅ `bash tools/check-ui-tokens.sh` — `flutter.cardWidget` / `web.paletteClass` 棘轮不破 (新增 badge 走 `AppBadge` tone,不走 `Card` 容器)
- ✅ `bash tools/check-ui-density.sh` — `framed ≤ 基线` / `visibleRows ≥ 11` 不破 (L2 归属 5 态增加「下级的客户·X」「上级推送·X」两个 badge tone 走 `info`/`neutral`,**不**涨行高,同列宽内滚动)
- ✅ `bash tools/check-auto-snapshot-extension.sh` — 不动 `.pi/extensions/`

---

## §5 数据模型改动 (最小 additive)

### 5.1 migration 0026 (拟)

```sql
-- drizzle/migrations/0026_customer_acquire_source.sql
ALTER TABLE customer ADD COLUMN acquire_source text;          -- 'friend'|'referral'|'cold_visit'|'ground_promo'|NULL
ALTER TABLE customer ADD COLUMN source_referrer_name text;    -- 转介绍时必填 (应用层 zod refine)

-- ⚠ 不加 DB CHECK: 与项目既有 text+enum 约定一致 (DB 无约束, 应用层校验, 见 M3)
```

配套 `drizzle/down/0026_customer_acquire_source.down.sql` 必带 (AGENTS §3「删破坏性 migration 不写 down.sql」红线)。

### 5.2 规则 (硬约束)

| # | 规则 | 出处 |
|---|---|---|
| **M1** | 不加 `NOT NULL`,不加 `DEFAULT` | 老 APK INSERT 兼容 (`ALTER TABLE ... ADD COLUMN <nullable>` 不需 DEFAULT, 老 client INSERT 不带该列也能跑; `AGENTS §5「migration NOT NULL 列不加 DEFAULT」`) |
| **M2** | 命名 `acquire_source` 而非 `source` | `referral_reward.source` 已存在 (`schema.ts:1321`, enum `['admin', 'self_signup']`),**同名不同义**必须规避 — 同名会让 ORM 推断错列 |
| **M3** | 转介绍必填介绍人走**应用层 zod refine**,**不加 DB CHECK** | DB CHECK 跨国迁移时易踩 `tools/check-migration-compat.sh` 阻断 (CHARTER §3.5 + ADR-0004) |
| **M4** | 改完必跑 `pnpm db:compat` | AGENTS §3「改 / 加 migration 后必跑巡检 + `--strict`」 |
| **M5** | 索引: `idx_customer_acquire_source` (低基数,只加速"按来源筛选"用) | 与 `schema.ts:467 ownerIdx` 同模式 |

### 5.3 Drizzle 映射 (`schema.ts:369` 客户表附近)

```typescript
// src/lib/db/schema.ts (拟改动,Phase A)
acquireSource: text("acquire_source", {
  enum: ["friend", "referral", "cold_visit", "ground_promo"],
}),
sourceReferrerName: text("source_referrer_name"),
```

### 5.4 种子退场与 is_seed 列处置 (D3)

> **拍板** (2026-09-25): 种子从客户类型轴退出 — 客户类型三态 (`franchisee` / `seed` / `normal`) 简化为**二态** (`franchisee` / `unaffiliated`),种子身份不再在 UI 出现; `customer.is_seed` 列**代码层不再读写**,DB 列**暂不 DROP**。

**代码层立刻移除 (Phase C 与其它 UI 改动同步落地)**:

| 位置 | 改什么 |
|---|---|
| `src/lib/db/queries/customer.ts:159-165` `resolveCustomerType` | 删除 `row.isSeed` 参数 + `seed` 分支; 返回类型从 `"franchisee" \| "seed" \| "normal"` 改为 `"franchisee" \| "unaffiliated"` |
| `src/lib/db/queries/customer.ts:159-165` 调用方 (4 处) | 类型胶囊只剩 `all` + `franchisee` + `unaffiliated` (前两个为原有, `normal` → `unaffiliated`, `seed` 直接删除) |
| `src/lib/db/queries/customer.ts:72-74` `CustomerView.isSeed` 字段 | zod schema 移除 `isSeed`; API 响应不再返回 |
| `src/lib/db/queries/customer.ts:229, 248` `CreateCustomerInput.isSeed?` / `UpdateCustomerInput.isSeed?` | 入口删除 |
| `src/lib/db/queries/customer.ts:614` `seedInputSeed` 默认值 | 删除 |
| `src/lib/db/queries/customer.ts:653-654` `customerTypeCounts` `seed` / `normal` 分类 | 改为 `unaffiliated` 单项 |
| Flutter 表单 (`customer_row.dart` / `customer_detail_page.dart` 等) | 删除种子勾选控件 + 🌱 标识; 客户类型筛选 UI 简化为 `all` + `加盟` + `未加盟` |
| Flutter 列表行 | 删除任何 `isSeed` 渲染 |

**DB 列暂不 DROP 的理由** (是「主人要求立刻移除」与「红线要求延迟删列」的折中):

1. `AGENTS §5` 红线 + `CHARTER §3.5` 红线 + ADR-0004: `DROP COLUMN` = 破坏性 migration, 必须走 `tools/check-migration-compat.sh` + CI `db-compat` job 阻断
2. 灰度期老 APK 仍会发 `isSeed` (老 client INSERT 路径),**DROP 后老 APK INSERT 仍可走** (因为迁移只 DROP 列不破坏其它列),但**老 APK 写 `isSeed` 字段会**直接失败** (列不存在) → 客户端读到 `isSeed: true` 的代码路径会报 `column does not exist`
3. 主人原话: 「`is_seed` 列、详情页都不需要保留」 → 重点在「用户不再看到」与「代码不再依赖」, **不**强求「数据库立刻下架」

**DROP 计划** (主人同意「灰度期后清理」):

| 触发 | 动作 |
|---|---|
| **代码层立刻** (Phase C) | zod 不再接受 `isSeed` + API 不再返回 + Flutter 表单与详情删除种子控件 + 类型筛选只剩 `all` + `加盟` + `未加盟` |
| **上线满 30 天** + 全量用户已升新 APK + 无老 APK 写 `isSeed` 路径残留 | 单独一条 drop migration (`drizzle/0030_drop_customer_is_seed.sql`; 编号 0026=来源 / 0027=referrer / 0028=customer_share / 0029=列表索引 已占) + `drizzle/down/0030_drop_customer_is_seed.down.sql` 必带 + 过 `pnpm db:compat` + `DROP COLUMN IF EXISTS customer.is_seed` |
| **DROP 前 assert** | `bash scripts/audit-customer-is-seed.ts` 查 `is_seed = true` 的客户数, 主人拍「同意丢掉这些行的语义」后才能 DROP (默认 0 行, 因灰度期 API 已不接 `isSeed: true`) |

**若主人要求立即 DROP** (不走 30 天灰度期): 必须主人**显式拍板**, 且：
- (1) 走 `tools/check-migration-compat.sh` 例外白名单 (`AGENTS §5「migration 不向后兼容」` 例外条款), commit message 加 `[drop-is-seed-immediate]`
- (2) 验证全量 APK 版本分布 (老 APK 写 `isSeed` 路径必然炸 → 需拍「接受老 APK 崩」)
- (3) 写 `docs/postmortem/drop-is-seed-immediate-<date>.md`

---

## §6 「选择直推者」最小改动清单

> **背景**: 现 `franchisee-placement.ts:1186` 落位执行时 `referrerId: raw.initiatorFid` 写死 = 发起人。本节把"落位时显式选直推者"做出来。

### 6.1 后端改动

| 文件 | 改什么 | 量级 |
|---|---|---|
| `src/lib/db/queries/franchisee-placement.ts:339-372` `CreatePlacementRequestInput` | 入参加 `referrerFid?: bigint` (null = 默认发起人) | ~5 行 |
| `src/lib/db/queries/franchisee-placement.ts` `createPlacementRequest` 主体 | 校验 `referrerFid` ∈ **落位后她的祖先链** = `targetParentFid` + 其上层直系 (与 `getUplineAncestors(fid, 3)` 同口径), 不在链上 → 400 | ~15 行 |
| 同上 · 默认值 (E1) | 未传 `referrerFid` → 默认 = 发起人 `initiatorFid`;admin 发起 (`initiatorFid = null`, 现回退 `targetParentFid`) → 默认 = 目标点位父 | ~3 行 |
| `src/lib/db/queries/franchisee-placement.ts:1186` (执行段) | 改 `referrerId: raw.initiatorFid` → `referrerId: raw.referrerFid ?? raw.initiatorFid` | 1 行 |
| `src/app/api/franchisees/placement-requests/route.ts:51-104` POST body | 加 `referrerFid?: string` 字段,正则校验 + BigInt 转换 | ~5 行 |

### 6.2 Flutter 改动

| 文件 | 改什么 | 量级 |
|---|---|---|
| `flutter_app/lib/core/widgets/placement_target_sheet.dart:41` `PlacementTargetSheetState` | 加「选择直推者」二级 picker: 候选 = 当前所选点位父的祖先链 (调 `getUplineAncestors(fid, 3)`),默认 = 自己 (发起人) | ~25 行 |
| `flutter_app/lib/core/services/api.dart:589` `createPlacementRequest` | 加 `String? referrerFid` 形参 + POST body 字段 | ~3 行 |
| `flutter_app/lib/modules/customer/screens/customer_list_page.dart:1350` 调用点 | 透传 `referrerFid` 来自 sheet 选择 | ~2 行 |
| `flutter_app/lib/modules/customer/screens/customer_detail_page.dart:1424` 调用点 | 同上 | ~2 行 |
| (不动) `flutter_app/lib/modules/relation/screens/franchisee_detail_page.dart:376` | 该调用点由落位「移动」场景,使用同接口,**同改造** | ~2 行 |

### 6.3 测试 + 巡检

| 文件 | 改什么 | 量级 |
|---|---|---|
| `scripts/audit-placement-integrity.ts:103` 例外报告 | 新增「referrer 不在祖先链」例外报告 (允许老节点白名单) | ~10 行 |
| `tests/placement-referrer.test.ts` (新) | 覆盖: 落位时显式选直推者;默认 = 发起人;候选 = 祖先链;搬树后 referrer 不在链 = 巡检报告但不级联改 | ~40 行, 4-6 例 |
| (不动) `placeNewFranchisee` | 只算 placement,不动 referrer (AGENTS §6.8 拆栏) | 0 |
| (不动) `adminReparentNode` | 显式不动 referrer_id (返回 `referrerTouched: false`) | 0 |
| (不动) `promote` / `unjoin` 执行段 | 同 §6.1 落位执行段,只把 1186 行写值改成 `referrerFid ?? initiatorFid` | 0 (复用同一行) |
| (不动) 三方确认角色枚举 | E3 决策:不新增角色 (见 §7) | 0 |

### 6.4 合计

| 项 | 量 |
|---|---|
| 改动文件数 | 4-6 个 |
| 总行数 | 60-80 行 + 2 测试 |
| 风险点 | (1) Flutter sheet 加选择控件影响点击路径 → 必须 `tools/check-ui-density.sh` 兜底;(2) 巡检加 referrer 校验会暴露老数据 → **白名单 + 例外报告,不级联改** (I-2 不变量) |

### 6.5 上级推送机制 (`customer_share` 表, D4 配套能力)

> **背景** (D4): 「下级的客户」与「上级推送的客户」在列表里要**与自己的客户做视觉区分**。下级的客户用 §3.4 (b) 判定;上级的客户不能默认可见 — 必须**归属人显式推送**才进列表。本节定义推送的**唯一真相源**与方向规则。
>
> **拍板定位**: Phase D 实施 (与 §3.4 RBAC 扩围同步, 需独立 RBAC/隐私评审)。

#### 6.5.1 表结构 (migration 0028 拟, Phase D)

```sql
-- drizzle/migrations/0028_customer_share.sql
CREATE TABLE customer_share (
  id           bigserial PRIMARY KEY,
  customer_id  bigint NOT NULL REFERENCES customer(id) ON DELETE CASCADE,
  from_user_id bigint NOT NULL REFERENCES "user"(id),     -- 推送人 = 当时该客户的归属人 (拍下时快照)
  to_user_id   bigint NOT NULL REFERENCES "user"(id),     -- 接收人 = 推送者所在枝的下层用户
  note         text,                                       -- 推送说明 ("主理人转介, 请协助跟进")
  created_at   timestamptz NOT NULL DEFAULT NOW(),
  revoked_at   timestamptz,                                -- 撤销时间 (NULL = 有效)
  revoked_by   bigint REFERENCES "user"(id)               -- 撤销人 (推送人 / 接收人 / admin)
);
-- 索引
CREATE INDEX idx_customer_share_to_active
  ON customer_share (to_user_id, revoked_at);
-- 部分唯一索引: 同一 (customer, to_user) 仅一条 active 推送
CREATE UNIQUE INDEX uniq_customer_share_active
  ON customer_share (customer_id, to_user_id)
  WHERE revoked_at IS NULL;
```

配套 `drizzle/down/0028_customer_share.down.sql` 必带 (CHARTER §3.5 + ADR-0004)。挂审计触发器 `customer_share_audit` (参照 `drizzle/audit_trigger.sql` 的 `franchisee_audit` 模式, 行 41-44 — 推送 / 撤销都要留痕, 事后能查「谁把谁推给谁」与「什么时候撤销」)。

#### 6.5.2 方向规则 (硬约束, Phase D 实施前不变)

| # | 规则 | 出处 |
|---|---|---|
| **S1** | **只有该客户的归属人** (`customer.owner_id`) **或 `role='admin'`** 能推送 | 推送 = 归属人授予可见性, 不是「随便谁都能推」 |
| **S2** | 接收人 `to_user_id` **必须是推送者所在枝的下层用户** (与 §3.4 (b) 同口径: 同 `root_id` + `placement_path` 前缀 + 后代) | 防止「跨枝推送」造成隐私泄漏; admin 不受此限 (admin 全森林) |
| **S3** | 推送 ≠ 转移归属 (`customer.owner_id` **不变**); 「先到先得」归属规则**不受推送影响** | 推送只授可见性, 不授归属; 客户详情 / 概览 / 跟进口径以 `owner_id` 为准 |
| **S4** | 同 (customer, to_user) **仅一条 active 推送** (部分唯一索引); 重复推送 → 409 `ALREADY_SHARED` | 幂等 + 业务语义清晰 |
| **S5** | 接收人可撤销自己收到的推送 (`revoked_at = NOW()`, `revoked_by = to_user_id`); 推送人可撤销自己发出的推送; **当前归属人 `customer.owner_id` 也可撤销** (归属 transfer 后旧 from_user_id 代表不了新 owner, reviewer P1); admin 全权撤销 | 四方都能撤回, 不锁死 |
| **S6** | **扩散上限** (reviewer P1 + D8 明文风险): 同一客户 active 推送数 ≤ 5 (可配); 同一接收人每日收到 ≤ 100 条; 超限 → 400 `SHARE_LIMIT_EXCEEDED` | D8 拍「推送给我的客户 = 明文」→ 不限扩散 = 手机号无限扩散 |
| **S7** | **禁止二次转发**: 被推送人不能把收到的客户再推给她的下层 (避免控制链稀释 + 明文扩散) | 审计链清晰; 若实际需要 (大区经理代推) 由主人再拍 |

#### 6.5.3 与其它口径的关系

| 机制 | 关系 |
|---|---|
| **§3.4 (c) 可见集合** | `customer_share` 是 §3.4 (c) 的唯一真相源 (`to_user_id = viewer` ∧ `revoked_at IS NULL`) |
| **§6.5.2 S3** | 推送不写 `owner_id`; 紧急度算法 (`src/lib/follow-up/urgency.ts`) 读 `owner_id`, **不受推送影响** |
| **AGENTS §6.7 节点 ⇒ 账号** | 推送的 `from_user_id` / `to_user_id` 都必须对应活账号 (`is_active = true`); 接收人停用 → 推送**自动失效** (列表 query 加 `EXISTS user active` 子查询) |
| **AGENTS §6.6 §6.6.1** | 推送是「上级推给自己枝的下级」, 不跨树; 与「推荐码不写 referrer」不冲突 (推荐码职责 = 身份识别, 与推送职责 = 可见性授予) |

#### 6.5.4 API (命名标拟, Phase D 实施)

| 方法 | 路径 | 入参 / 返回 |
|---|---|---|
| `POST` | `/api/customers/[id]/share` | `{ toUserId: string, note?: string }` → `{ id, customerId, fromUserId, toUserId, note, createdAt }` (S1+S2 校验失败 → 403/400) |
| `DELETE` | `/api/customers/[id]/share/[userId]` | `{ revokedBy: string, reason?: string }` → 200; 不存在 / 已撤销 → 404 (幂等: 重复撤销返 200) |
| `GET` | `/api/customers/shares/received` | 返回当前 user 收到的所有 active 推送 (列表角标用) |

**zod refine**: `note` ≤ 200 字; `reason` (撤销原因) 必填, 写审计; S1 校验 `from_user_id` = 当前 user OR `role='admin'`。

#### 6.5.5 UI 入口与展示 (Phase D 实施)

| 屏幕 | 元素 |
|---|---|
| **客户详情 · 管理 Tab · 归属卡** | 归属卡旁加「**推送给下级**」按钮 (仅归属人 / admin 可见) → 弹出 picker 选枝内下层用户 + 填写 `note` ≤ 200 字 |
| **客户详情 · 任何归属卡** | 归属卡下追加「上级推送 · 张XX」列表 (推送给我的人),**仅当存在 active 推送时显示**, `revoked` 推送不显示 |
| **客户列表行** (L2 归属) | `upline_shared` 态 badge「上级推送 · X」 (X = 推送人姓名缩写, 与 §4.2 表一致) |
| **客户列表角标** | 顶部 chip 显示「上级推送 · N 条」 (N = 当前 user 收到的 active 推送数),点击进 `/api/customers/shares/received` |

#### 6.5.6 不变量 (拍板后永不变)

| # | 不变量 |
|---|---|
| **SHARE-1** | 推送不写 `customer.owner_id` (S3) |
| **SHARE-2** | 推送不改变紧急度算法结果 (S3 + §3.3) |
| **SHARE-3** | 被推送人看到的是**同一份客户档案**, 不是副本 (无 `customer_copy` 表) |
| **SHARE-4** | 推送**双方**账号 (`from_user_id` / `to_user_id`) **任一停用** → 列表不可见 (§3.4 (c) 的两个 `EXISTS user active` 子句对称) |
| **SHARE-5** | `customer_share` 表必挂审计触发器 (`customer_share_audit`), 与 `franchisee_audit` 同模式 |
| **SHARE-6** | `customer.owner_id` 被 transfer 后, 该客户的 active 推送**保留** (推送是独立可见性授权, 与归属无关); 新 owner 可撤销 (S5 已含) |
| **SHARE-7** | `(b1)` 命中的客户其 ownership 必须是 `direct_downline` (不得落 `other`), 否则误报 scope 漏检 |

---

## §7 决策记录

### 7.1 ✅ 已拍板 (2026-09-25 主人拍)

| # | 决策 | 落地含义 |
|---|---|---|
| **P1** | **直推 = `referrer_id` 口径**（谁把她带进加盟的人）；与图谱 `classifyRelation` 同真相源 | supersede `customer.ts:522-526` 的 placement 旧口径; `franchisee.ts:450` 真相源统一; `customer-scope.ts:27-49` `directDownlineFranchiseeSql` supersede 为 `referrer_id = myFid` |
| **P2** | **加盟细分 = 直推 / 非直推**（非直推 = 在我的图谱树内且直推者不是我） | §1 维度 2 + §2; 与图谱「同一真相源两种视图」对齐 |
| **E1** | **直推者候选 = 落位后她的祖先链**（`targetParentFid` + 其上层直系）；默认 = 发起人，admin 发起（无 fid）默认 = 目标点位父 | §6.1; `franchisee-placement.ts:1186` 执行段改 `referrerFid ?? initiatorFid` |
| **E2** | 「直推者必是上级」**只做写入时校验 + 巡检例外报告**；搬树（admin 强改上层）**不级联改** `referrer_id`（保 AGENTS §6.8 拆栏） | `franchisee-reparent.ts` (`referrerTouched:false`) + `scripts/audit-placement-integrity.ts:103` 加 referrer 例外报告 + 老节点白名单 |
| **E3** | **三方确认角色不新增**（发起人 / 新加盟者 / 目标点位父 三方已够） | `franchisee-placement.ts:131-156` `requiredRoles` 保持; §6 不引入新角色枚举 |
| **D3** | **种子从客户类型轴退出** — 列表只剩「全部 / 加盟 / 未加盟」; `is_seed` 列、详情页都不需要保留 | `resolveCustomerType` (`customer.ts:159-165`) 返回类型三态 → 二态; `CustomerView.isSeed` zod 字段删; API 不再返回; Flutter 表单与详情删除种子控件 + 🌱 标识; 类型筛选 UI 简化为 `all` + `加盟` + `未加盟`; **DB 列暂不 DROP**, 处置详见 §5.4 (灰度 30 天后单独 drop migration) |
| **D4** | **「下级的客户」**在客户列表中显示 (与用户自己的客户做视觉区分); **「上级的客户」**需要上级推送给我才显示 (也在客户列表中与自己的客户做区分) | §3.4 RBAC 口径四段式 (a 我的客户 / b1 我的下层加盟节点本人 / b2 下层的客户 / c 上级推送的客户); §4.2 L2 归属 5 态; 实施需独立 RBAC/隐私评审 (§8 Phase D); 手机号按 §3.4 表分级 (**上级推送 upline_shared 按 D8 = 明文**; 下级 / 他人 / 无归属 走 `maskPhone`) |
| **D5** | **来源选填**; 仅转介绍 (`referral`) 时介绍人必填 | `acquire_source` 列 nullable + 应用层 zod refine (`referral` 分支展开 `source_referrer_name` 必填); 老 APK INSERT 兼容 (无 DEFAULT, §5 M1) |
| **D6** | **客户列表不显示客户来源**; 仅在客户详情页的**管理区块**中显示来源 | §4.2 展示位映射表: Flutter 列表行 L4 = 不显示; Flutter 详情 = 仅管理 Tab 的档案卡; Web admin 列表 = 来源列删除; Web admin 详情 = 来源放管理 / 档案区; 表单来源位置不变 (姓名/性别/手机 与 生日 之间) |
| **D7** | **来源列命名 `acquire_source`**; key = `friend` / `referral` / `cold_visit` / `ground_promo`; `NULL` = 未填写 | §5 M2 命名硬约束; enum 写入 `drizzle/0026_customer_acquire_source.sql`; Flutter + Web admin + API zod 双线同步; 落地字符串与设计稿字面一致 |

### 7.2 ✅ 已拍 (2026-09-25)

| # | 决策 | 落地含义 |
|---|---|---|
| **D8** | **手机号明文范围: 上级推送给我的客户 (c) 明文** (推送即授权跟进; 若打码则「推来跟进」名不副实) | §3.4 手机号分级表 `upline_shared` 行 = 明文 (不再「待拍 D8」); §9.1 INV-5 不变量表述追加 `upline_shared` 例外 |
| **D9** | **manager 角色在扩围后与 sales 同口径** (ADR-0015 Q8 已冻结门店维度, 现有 manager 分支实际无数据; 扩围后保持「我的客户」三段式 (a+b1+b2+c) 一致) | `src/lib/auth/rbac.ts` `customerRbacFilter` 现 `manager` 分支保留 (`managedStoreIds`); 扩围后不在 `manager` 上加额外门店过滤, 与 `sales` 共用 `viewerCustomerScopeSql` 入口 |

> 当前无待拍项。后续 Phase D 实施过程中如出现新议题, 在此节追加。

---

## §8 分期与验收

> **每阶段独立 task-snapshot** (`AGENTS §8.1` 强制 ≥3 文件 / 跨域)。**改完必跑**:`pnpm type-check` + `pnpm db:compat` + (UI 改)`tools/check-ui-density.sh` + `tools/check-ui-tokens.sh` + `tools/check-auto-snapshot-extension.sh`。
>
> **重排逻辑** (2026-09-25):
> - 原 §8.1 数据层 + §3 supersede + §5 migration 合并为 **Phase A** (数据与身份层)
> - 原 §8.2 「选择直推者」拆出为独立 **Phase B** (不与 UI 改动耦合)
> - Flutter UI 改动统一为 **Phase C** (含列表归属区分 / 详情管理区块 / 表单来源 / 种子移除)
> - RBAC 扩围 + 上级推送机制独立为 **Phase D** (需 RBAC/隐私评审后再实施)
> - Web admin 同步推迟到 **Phase E** (与 Phase C 解耦, 避免被 Flutter 进度拖)

### 8.1 Phase A — 数据与身份层 (1.5 天)

| 任务 | 验收 |
|---|---|
| `drizzle/0026_customer_acquire_source.sql` (`acquire_source` + `source_referrer_name`) + down.sql | `pnpm db:compat` 过; 老 APK INSERT 兼容 (无 `NOT NULL`/`DEFAULT`, M1) |
| `src/lib/customer/identity.ts` 新增 (`resolveCustomerIdentity`) | 单测覆盖 5 态 (我的 / 下级 / 上级 / 他人 / 无归属) + viewer 无加盟 + 软删 franchisee + D6「上级推送」待 Phase D 留空态 |
| `customer-scope.ts:27-49` `directDownlineFranchiseeSql` supersede (改 `referrer_id`) | 单测覆盖: 同 viewer 同时存在直推 + 子树, 直推计数稳定 |
| 客户列表 API `/api/customers` 接 `identity.ts` | `customerType === "franchisee"` 筛口径变 referrer, 与图谱同; **老字段 `customerType` 不动** |
| `customerTypeCounts` (`customer.ts:626`) supersede: `seed` / `normal` → `unaffiliated` 单项 (D3 落地) | 单测覆盖 |

### 8.2 Phase B — 「选择直推者」最小改动 (0.5-1 天)

> 仅含 §6.1-6.3 的 E1-E3; 与 UI 改动解耦, 可在 Phase C 之前独立交付。

| 任务 | 验收 |
|---|---|
| `franchisee-placement.ts:339-372` `CreatePlacementRequestInput` 加 `referrerFid?: bigint` | 入参 schema 校验 |
| `franchisee-placement.ts` `createPlacementRequest` 主体加祖先链校验 | 不在链上 → 400; admin 豁免 (admin 全森林) |
| `franchisee-placement.ts:1186` 执行段 `referrerId: raw.referrerFid ?? raw.initiatorFid` | 1 行改动; 默认值回退 |
| `franchisees/placement-requests/route.ts:51-104` POST body | 加 `referrerFid?: string` 字段 + 正则 + BigInt 转换 |
| `scripts/audit-placement-integrity.ts:103` 加「referrer 不在祖先链」例外报告 | `--strict` 通过 + 老节点白名单 (`whitelist: Map<fid, reason>`) |
| `tests/placement-referrer.test.ts` 新增 | 4-6 例: 显式选直推者 / 默认 = 发起人 / 候选 = 祖先链 / 搬树后 referrer 不在链 = 巡检报告但不级联改 |

### 8.3 Phase C — Flutter UI 改动 (1.5-2 天)

| 任务 | 验收 |
|---|---|
| **列表归属 5 态**: `customer_row.dart` L2 归属 badge 改 5 态 (`mine` 静默 / `subordinate`「下级的客户 · X」/ `upline_shared`「上级推送 · X」/ `none`「无归属」/ `other` 兜底文案) | 真机截图 (iPhone SE / 14 / Pro Max); `ownership = subordinate` 手机号走 `maskPhone` (`utils.ts:24`); `ownership = other` 触发 scope 漏检告警 |
| **列表 L4 来源不显示** (D6) | 真机截图; `pnpm test tests/customer-row-source.test.ts` (新增) 断言列表行不含来源短词 |
| **详情管理区块**: 归属卡 5 态 + 管理 Tab 的档案卡来源行 (短词 + 转介绍展开介绍人) | 真机截图; 详情其它区块**不**显示来源 |
| **新建/编辑表单**: 姓名/性别/手机 与 生日 之间插入来源字段 (D5); 选填; 选「转介绍」展开介绍人必填 | zod refine 校验; 老 APK INSERT 兼容 (无 DEFAULT, §5 M1) |
| **种子移除** (D3, §5.4 代码层): 表单删除种子勾选 + 详情删除 🌱 + 列表删除 isSeed 渲染; 类型筛选 `all` + `加盟` + `未加盟` | zod schema 不再接受 `isSeed`; API 不返回 `isSeed`; Flutter 类型枚举同步 |
| `tools/check-ui-density.sh` + `tools/check-ui-tokens.sh` + `tools/check-auto-snapshot-extension.sh` 三道棘轮 | 不破基线 (`flutter.cardWidget` / `web.paletteClass` / `visibleRows ≥ 11`) |
| 真机验收三屏 (列表 / 详情 / 表单) | iPhone 14 真机截图覆盖; 棘轮 + 单测全绿 |

### 8.4 Phase D — RBAC 扩围 + 上级推送机制 (1.5-2 天, 需独立 RBAC/隐私评审后再启动)

> **本阶段是隐私扩张点**, 开工前必走完:
> ① `docs/identity-privacy-review.md` 拍板 (参照 `AGENTS §3「数据敏感字段必须加密」+ §3「不要把客户健康数据放第三方公有云」`红线)
> ② 主人 ask_user 拍「同意扩围下级/上级推送可见性」
> ③ 评审通过才能合并 PR

| 任务 | 验收 |
|---|---|
| `drizzle/0028_customer_share.sql` (§6.5.1) + down.sql | `pnpm db:compat` 过; `idx_customer_share_to_active` + 部分唯一索引 `uniq_customer_share_active`; 审计触发器 `customer_share_audit` (参照 `audit_trigger.sql:41-44` `franchisee_audit` 模式) |
| `customer-scope.ts` 新增 `viewerCustomerScopeSql(viewer)` = 三段式 (§3.4 a+b+c), supersede `myCustomerScopeSql` | 单测覆盖 5 态 + 推送存在 / 撤销 / 跨枝拒绝 (S2); 手机号分级断言 (mine 明文 / 其他 `maskPhone`) |
| `customer-share.ts` 新模块 (S1-S5 校验): 推送人 = `owner_id` OR admin; 接收人 ∈ 同枝下层 (S2) | `tests/customer-share.test.ts` 覆盖 S1-S5 |
| API: `POST /api/customers/[id]/share` + `DELETE /api/customers/[id]/share/[userId]` + `GET /api/customers/shares/received` | zod refine (note ≤ 200; reason 必填); 权限中间件加 S1 校验 |
| `/api/customers` 列表接入 `viewerCustomerScopeSql(viewer)` | 集成测试: viewer A 推送 1 条给 B → B 列表新增 1 行; A 撤销 → B 列表立即减少 1 行 (无缓存) |
| `auth/rbac.ts` 行级过滤重审 | 评审通过 |
| 上线后 7 天观察期 | `scripts/audit-customer-share.ts` 跑推送异常检测 (跨枝 / 越权 / 重复) |

### 8.5 Phase E — Web admin 同步 (0.5-1 天)

> 与 Phase C 解耦: 等 Phase C Flutter 跑通真机验收再开工 (避免 web admin 被 Flutter 进度反向拖)。

| 任务 | 验收 |
|---|---|
| `/admin/customers` 列表: 归属列 5 态 + 来源列**删除** (D6) | 列表行 ≥ 11 (`visibleRows` 棘轮); Web admin 列表 ≠ Flutter 列表, 但归属 5 态文案一致 |
| `/admin/customers/[id]` 详情: 归属卡 + 管理/档案区来源 (D6) | 与 Flutter 详情同口径; 手机号分级与 Flutter 一致 |
| `/admin/customers/new` 表单: 姓名/性别/手机 与 生日 之间插入来源 (D5); 选「转介绍」展开介绍人必填 | zod refine 同 Flutter (`tests/admin-customer-form.test.ts` 覆盖) |
| Phase D 落地后接入 `viewerCustomerScopeSql` | Web admin 列表与 Flutter 列表**同一可见集合** (集中真相源 §3.4) |
| `pnpm type-check` | 必过 (AGENTS §3「双线同步」) |

---

## §9 风险与不变量

### 9.1 不变量 (拍板后永不变)

| # | 不变量 | 来源 |
|---|---|---|
| **INV-1** | 「我的客户」= `owner_id = 我 ∪ placement_parent_id = 我的 fid` (RBAC 行级过滤共用) | AGENTS §6.6 + ADR-0015 Q2 + `customer-scope.ts:78` |
| **INV-2** | "直推 / 下级引荐 / 上级引荐" 三词只允许出现在图谱 (B3) | §3.3 B3 |
| **INV-3** | viewer 无加盟节点 → `affiliation = none`,`ownership ∈ {none, mine}` (B2) | §3.3 B2 |
| **INV-4** | 所有 identity SQL 必须 `franchisee.deleted_at IS NULL` (B1) | §3.3 B1 |
| **INV-5** | 手机号 mask 以 §3.4 分级表为准: `subordinate` / `other` / `none` → `maskPhone`; **明文例外两类** = `direct_downline` (b1 我的下层加盟节点本人) + `upline_shared` (c, D8 2026-09-25 拍) | §3.3 B4 + §3.4 手机号分级表 + §7.2 D8 |
| **INV-6** | `placement_parent_id` ≠ `referrer_id` 是**允许**的 (I-2);`audit-placement-integrity.ts:103` 例外报告不报错 | AGENTS §6.8 拆栏 |

### 9.2 风险

| # | 风险 | 缓解 |
|---|---|---|
| **R-1** | **搬树后 referrer 可能不再是她的上级** (admin `reparent` 后,直推人掉到子树外) | **只写入时校验 + 巡检例外** (§7 E2),**不级联修正** — 否则破坏 AGENTS §6.8 拆栏 |
| **R-2** | **老数据 referrer = 发起人,手工改过的可能不在链上** | `audit-placement-integrity.ts` 加「referrer 不在祖先链」报告 + **老节点白名单** (`whitelist: Map<fid, reason>`),**不自动改** |
| **R-3** | **手机号 mask 漏一处 = 隐私事故** | B4 硬约束 + 集成测试覆盖 `ownership ∈ {subordinate, other, none}` 的所有 view 路径 (§3.4 分级表为唯一真相源) |
| **R-4** | **`acquire_source` 与 `referral_reward.source` 同名混淆** | §5 M2 命名硬约束 + ADR-0015 §3 术语表后续同步 |
| **R-5** | **UI 棘轮破基线** (新徽章引入 Card / 涨行高 / 多色) | §4.3 三条护栏 (`check-ui-tokens.sh` / `check-ui-density.sh` / `check-auto-snapshot-extension.sh`),CI 阻断 |
| **R-6** | **来源必填 = 老 APK 升级崩** (M1 反向) | §7 D5 已拍选填;转介绍介绍人走应用层 zod refine |
| **R-7** | **直推 supersede 影响 4 处类型筛选代码** | §2.3 改动列表 + Phase A 单测覆盖三类边界 (我的直推 / 我的非直推子树 / 软删) |
| **R-8** | **Flutter sheet 加选择控件影响点击路径** (密度棘轮) | Phase B 验收必跑 `check-ui-density.sh`;真机截图覆盖三个尺寸 (iPhone SE / 14 / Pro Max) |
| **R-9** ★ | **列表膨胀**: Phase D 扩围 (b) 下级的客户 + (c) 上级推送的客户 后, viewer 列表候选集从 `owner_id = 我` 单集合扩到 `owner_id = 我 ∪ 同枝下层 ∪ customer_share 推送给我`,枝深的销售员可见行数显著增长 (`subordinate` 子树可能含数千客户) | (1) 收窄开关**集中在 `customer-scope.ts` 一处** (`viewerCustomerScopeSql` 单一真相源);(2) 收窄策略默认 = (b) 全下层 (与图谱同源), 提供 config flag 后续可改为「仅直接下级」,只动 (b) 子句;(3) `bash tools/check-ui-density.sh` Phase D 上线前**必跑**全路由, 列表行 ≥ 11 棘轮不破;(4) `customerTypeCounts` 缓存 (按 (a/b/c) 三段分别计数, UI 角标可用) |
| **R-10** ★ | **推送撤销后立即不可见**: 用户期望「撤销推送 = 列表马上少一行」; 若后端 / 前端任何一层缓存 `customer_share` 结果, 撤销后用户仍能看到那行, 信任崩塌 | (1) `/api/customers` 不缓存可见集合结果 (Drizzle 直查 + revoke_at 索引);(2) 推送撤销响应立即触发客户端刷新 (Flutter `RefreshIndicator` / Web admin `router.refresh()`);(3) 集成测试断言: 推送 → 撤销 → 100ms 内列表 API 不再返回该客户;(4) `idx_customer_share_to_active` 索引 `(to_user_id, revoked_at)` 保证撤销即过滤 |
| **R-11** ★ | **is_seed 延迟 DROP 的回滚窗口** (D3 + §5.4): 灰度期 (上线满 30 天前) 老 APK 仍写 `is_seed`, DB 列保留; 风险点 = 30 天内「想反悔恢复种子类型轴」需重新启回 `is_seed` 列, 但代码层已删 (zod 不再接受 / API 不再返回), 回滚需代码 + migration 一起 revert | (1) 灰度期内 `is_seed` 列**只读不写** (DB trigger 或 service 层 guard, 任何 INSERT/UPDATE 写 `is_seed = true` 抛 warning 写 audit, 不阻止);(2) 30 天到期由 `scripts/audit-customer-is-seed.ts` 自动检查 `is_seed = true` 的行数 (主人拍「同意丢」才能 DROP);(3) 回滚 SOP: 单独一条 `drizzle/0031_restore_customer_is_seed.sql` (additive, 无破坏; 编号 0026/0027/0028/0029/0030 已占) + `customer.ts:159-165` `resolveCustomerType` 恢复三态, 写入 `git revert` 一次性 commit;(4) 若主人要求「立即 DROP」 → 走 §5.4 显式拍板条款 (commit message 加 `[drop-is-seed-immediate]` + 写 `docs/postmortem/drop-is-seed-immediate-<date>.md`) |

> ✅ **已解决 (2026-09-25/26)**: **R-9 (列表膨胀)** 与 **R-10 (推送撤销立即生效)** 的深度优化已完成 ——
> 方案与实施见 [`docs/r9-r10-optimization.md`](./r9-r10-optimization.md): R-9 = 三索引 (migration 0029) + count 解耦 + Flutter 无限滚动;
> R-10 = L1 同端 invalidate / L2 `RouteObserver.didPopNext` 返回列表刷新 / L3 恢复前台刷新 + 全链路 `no-store`。
> 本文下面 R-9 / R-10 两行的「缓解」列 = 当时的最小兜底 (仍保留), 不再是唯一手段。

| # | 风险 | 缓解 |
|---|---|---|
| **R-12** ★★ | ✅ **已修 (2026-09-25)**: `GET /api/customers/[id]/follow-up-analysis` 加行级过滤, 走 `getCustomerById(id, { scope: customerRbacFilter(ctx) })` (与 `bind-account` 同口径), 命中不到即 404, 不泄漏存在性。回归测试 `tests/idor-follow-up-analysis.test.ts` 5 例全过 (200 / 404 / 401 / 400 / 双向对称)。**实施前**的 P0 IDOR 描述仅供历史归档参考;**当前已闭合** | —— |

### 9.3 验收自检清单 (各 Phase 完成时逐条对)

**Phase A (数据与身份层)**:
- [ ] `pnpm db:compat` 过 (migration 0026 additive)
- [ ] 老字段 `customerType` 行为不变 (新口径只在 `identity.ts` 输出,不破坏现有 capsule 筛)
- [ ] `identity.ts` 单测覆盖 5 态 (我的 / 下级 / 上级 / 他人 / 无归属) + viewer 无加盟 + 软删 franchisee
- [ ] `customer-scope.ts:27-49` supersede 后单测覆盖:同 viewer 同时存在直推 + 子树,直推计数稳定
- [ ] `customerTypeCounts` supersede (三态 → 二态) 单测覆盖

**Phase B (选择直推者)**:
- [ ] `audit-placement-integrity.ts --strict` 过 (加 referrer 例外报告 + 白名单)
- [ ] `tests/placement-referrer.test.ts` 4-6 例全过 (显式选直推者 / 默认 = 发起人 / 候选 = 祖先链 / 搬树后 referrer 不在链 = 巡检报告但不级联改)
- [ ] admin 发起 (无 fid) 默认 = 目标点位父, 真机验证

**Phase C (Flutter UI)**:
- [ ] 列表归属 5 态验证: 自己的客户 (静默) / 下级的客户 · X (badge) / 上级推送 · X (badge, Phase D 后才有数据) / 无归属 (badge) / 他人客户 (兜底文案)
- [ ] **下级的客户在列表可见且与自己的客户做视觉区分** (L2 badge 颜色 + 文案)
- [ ] 列表行**不**显示来源 (D6, 截图为证)
- [ ] 详情管理 Tab 的档案卡**显示**来源; 详情其它区块**不**显示来源 (D6)
- [ ] 来源选填; 选「转介绍」展开介绍人必填 (D5); 老 APK INSERT 兼容
- [ ] **种子移除** (D3): zod 不再接受 `isSeed` + API 不再返回 + Flutter 表单与详情无种子控件 + 类型筛选只剩 `all` + `加盟` + `未加盟`
- [ ] **mask 分级生效** (B4 + §3.4 分级表): `ownership ∈ {subordinate, other, none}` 的列表 / 详情 / 概览路径手机号走 `maskPhone` (`utils.ts:24`); 明文仅 `mine` / `direct_downline` (与 §3.4 表一致); 集成测试覆盖
- [ ] Flutter 列表行高 60 不变 (`AppSize.listRowHeight`)
- [ ] `bash tools/check-ui-density.sh` 全路由 visibleRows ≥ 11
- [ ] `bash tools/check-ui-tokens.sh` flutter.cardWidget / web.paletteClass 不破
- [ ] `bash tools/check-auto-snapshot-extension.sh` ✓
- [ ] 真机截图 (iPhone 14) 三屏: 列表 / 详情 / 表单 — 验证 §4.2 映射
- [ ] `pnpm test:run` 双线同步过 (Flutter + Web admin)

**Phase D (RBAC + 上级推送, 评审后开工)**:
- [ ] RBAC/隐私评审通过 (`docs/identity-privacy-review.md`)
- [ ] `pnpm db:compat` 过 (migration 0028 `customer_share` additive)
- [ ] `customer_share_audit` 触发器挂载成功 (参照 `audit_trigger.sql:41-44` `franchisee_audit` 模式)
- [ ] `viewerCustomerScopeSql(viewer)` 三段式单测覆盖 (a 我的 / b 下级的 / c 上级推送)
- [ ] **上级未推送时不可见** (D4 + S3 + R-10): 推送前 B 列表无 A 的客户; 推送后 B 列表立即出现; 撤销后 100ms 内 B 列表减少
- [ ] **mask 分级生效** (D8, 以 §3.4 分级表为准): `ownership = upline_shared` (c 命中行) 手机号**明文** (推送即授权跟进); `subordinate` / `other` / `none` 一律 `maskPhone`; **推送管理角标例外**: `/api/customers/shares/received` 返回的**列表元数据**里手机号一律 maskPhone (角标是元数据不是客户档案)
- [ ] 跨枝推送拒绝 (S2); 越权推送拒绝 (S1); 重复推送幂等 (S4, 部分唯一索引)
- [ ] `bash tools/check-ui-density.sh` Phase D 上线前**必跑**全路由, visibleRows ≥ 11 棘轮不破
- [ ] `scripts/audit-customer-share.ts` 上线后 7 天观察期推送异常检测 = 0 报错

**Phase E (Web admin 同步)**:
- [ ] `/admin/customers` 列表归属列 5 态; 来源列删除 (D6)
- [ ] `/admin/customers/[id]` 详情管理/档案区显示来源; 其它位置不显示
- [ ] `/admin/customers/new` 表单插入来源字段; zod refine 同 Flutter
- [ ] Phase D 落地后 Web admin 列表与 Flutter 列表**同一可见集合** (`viewerCustomerScopeSql` 单一真相源)
- [ ] `pnpm type-check` 必过 (AGENTS §3「双线同步」)

---

## §10 关联文档

| 文档 | 关系 |
|---|---|
| [`docs/adr/0015-subject-model.md`](./adr/0015-subject-model.md) §3 | 术语消歧 (一人三面、归属 vs 建档) |
| [`docs/adr/0016-identity-anchor.md`](./adr/0016-identity-anchor.md) §3 | ID 化连接 (本文件 §3 SQL 全走 `user.customer_id`,不走 `phone_hash`) |
| `AGENTS.md` §6.6 / §6.6.1 / §6.7 / §6.8 | 建号不变量 / 主体模型 / 节点 ⇒ 账号 / 加盟树结构改动 + 拆栏 (本文件 §3.4 / §6.5 引用) |
| [`docs/ui-principles.md`](./ui-principles.md) §1 / §2 / §5 | 五原则 / B 档规格 / 反模式 (本文件 §4 全引用) |
| [`docs/follow-up-list-plan.md`](./follow-up-list-plan.md) | 跟进紧急度方案 (本文件 §4 L3 引用其口径; §6.5 S3 推送不改变紧急度) |
| [`docs/graph-node-dimensions-design.md`](./graph-node-dimensions-design.md) | 图谱三维区分 (与本文 §3.3 B3 「同一真相源两种视图」对齐) |
| `drizzle/migrations/0020_customer_owner.sql` 等 | 数据层基线 (本文件 §5 增量基础) |
| `drizzle/audit_trigger.sql` (行 41-44 `franchisee_audit` 模式) | `customer_share_audit` 触发器参照模式 (本文件 §6.5.1) |
| `src/lib/billing/member-flag.ts` | 会员判定唯一真相源 (本文件 §3 引用) |
| `src/lib/follow-up/urgency.ts` | 紧急度 / 推荐标签 (本文件 §1 / §4 L3 引用) |
| `src/lib/utils.ts:24` `maskPhone` | 手机号打码 (本文件 §3 B4 / §3.4 手机号分级 / §9 R-3 引用) |

> **本文件是 v1 定稿**。后续若新增业务面 (门店 / 多租户 / AI 跟进),从这里重新评估 — 不要各写各的 (与 ADR-0015 §11 同根原则)。