# ADR-0019: RBAC 可见范围扩围 + 客户推送机制 (`customer_share`)

> **状态**: ✅ **Accepted (2026-09-25 主人拍板)** — 主人原话「全按建议 + R-9 接受最小兜底」;依赖 [`docs/customer-identity-system.md`](../customer-identity-system.md) §3.4 / §6.5 + [`docs/identity-privacy-review.md`](../identity-privacy-review.md) (2026-09-25 已签字);Phase D 实施闸门已开
> **关联 (上游已拍,本 ADR 不重述)**: [`customer-identity-system.md`](../customer-identity-system.md) §3.4 (四段式可见集合) · §6.5 (`customer_share` 表 + S1-S7 + SHARE-1..7) · §7.1 (D4 列表可见扩围) · §7.2 (D8 手机号明文 `upline_shared` / D9 manager 与 sales 同口径) · §8.4 (Phase D 验收清单) · §9.2 (R-9 / R-10 / R-11 风险与缓解)
> **关联 (平行 ADR)**: [ADR-0004](./0004-schema-evolution.md) (schema 演进红线) · [ADR-0015](./0015-subject-model.md) (主体模型 / 「我的客户」口径) · [ADR-0016](./0016-identity-anchor.md) (ID 化连接 / 手机号不是身份) · [ADR-0017](./0017-web-admin-unfreeze.md) (web admin 解冻后双线同步)
> **关联 (操作层)**: `AGENTS.md` §6.6.1 (主体模型不变量 / 「我的客户」口径) · §6.7 (节点 ⇒ 账号不变量 / 推送双方必须活账号) · §6.8 (拆栏 / 改上层绝不改 referrer)
> **本 ADR 的定位**: 上述主文档 / AGENTS 已写定**口径定义**;本 ADR 只做 **a) 改动决策的逻辑归档** · **b) 实施闸门** · **c) 改动文件清单** · **d) 风险与待决项的显眼标注** —— **不引入新决策**。凡主文档未定的,一律标「待主人拍」。

---

## 1. 上下文

### 1.1 为什么扩围 (D4 主人 2026-09-25 拍)

当前「我的客户」口径仅含两层:
- `(a) customer.owner_id = 我` (我的归属)
- `(b 旧版) 我的直推加盟 (placement_parent_id = 我)` — `customer-scope.ts::myCustomerScopeSql` 的两段式实现

两条之外的客户**完全不可见**。销售员长期反馈两类盲区:

1. **「我的下级 (加盟枝) 在跟进她自己的客户,但我不知道她们是谁」** — 下级 A 跟进了客户 X,但上级 B 的列表看不见 X,B 无法协助分配资源 / 协调冲突
2. **「我的上级有客户想让我协助跟进,但进不了我列表」** — 上级 C 有客户 Y 想让下级 B 代为跟进,缺乏明示通道

D4 主人 2026-09-25 拍:

> 「下级的客户要在列表显示且与自己的区分;上级的客户需上级推送才显示」

本 ADR 把这条业务诉求**翻译成可见性口径**,落地到 `customer-scope.ts` 单一真相源与新的 `customer_share` 表。

### 1.2 现状口径 (`myCustomerScopeSql` 两段式) 与历史教训

**现状** (`src/lib/db/queries/customer-scope.ts:110`):

```typescript
export function myCustomerScopeSql(input: {
  ownerUserId: bigint;
  franchiseeId: bigint | null;
}): SQL {
  return sql`(${ownedByUserSql(input.ownerUserId)} OR ${directDownlineFranchiseeSql(
    input.francheId
  )})`;
}
```

两段 = `(a 归属 = 我) ∪ (b 旧版 placement_parent_id = 我的直推)`,**不含下级归属的客户** + **不含上级推送的客户**。

**历史教训 —「图谱 vs 列表」口径打架**:

2026-09-25 拍 D4 当日,主文档 §2.1 已记一条 supersede 事件:

| 位置 | 旧口径 | 新口径 (D4 supersede) | 出处 |
|---|---|---|---|
| `customer.ts` 客户类型筛选 | `placement_parent_id = 我的 fid` | `EXISTS franchisee WHERE referrer_id = 我的 fid` (§2.1 拍) | §2.1 P1 |
| 图谱 `franchisee.ts:450` `classifyRelation` 的 `direct` 分支 | `referrer_id = rootId` | (无变化) | §2.1 |
| `customer-scope.ts:27-49` `directDownlineFranchiseeSql` | `placement_parent_id = myFid` | 维持 (可见性扩围用, 见 §3.4 表注) | §2.3 |

**反模式根因**: 同一行客户上,图谱画的是「我的直推」(读 `franchisee.referrer_id`),客户列表筛的是「我的子树」(读 `placement_parent_id`),档案里又写「上级加盟人」(读 `placement_parent_id`)—— **三种口径同屏打架**,销售员看到三个不同的「她是谁」。

**本 ADR 的护栏 (E-1)**: 扩围后**列表 / 详情 / 概览 / 行级过滤 / 胶囊计数 / 图谱可见性六处**仍走 `customer-scope.ts` 单一真相源,**禁止调用方自写可见性 SQL** (主文档 §3.4 「集中点」段)。任何「收窄策略」「灰度开关」只动 `customer-scope.ts` 一处。

### 1.3 「图谱可见性 ≠ 列表可见性」的明确边界

这是本 ADR 必须澄清的核心区分,也是扩围后**最容易越界**的地方:

| 维度 | 图谱可见性 (`franchisee.ts`) | 列表可见性 (`customer-scope.ts`) |
|---|---|---|
| 主体 | **加盟节点** (franchisee 行) | **客户档案** (customer 行) |
| 我的下层 | 整棵子树,不限层 (per AGENTS §6.6.1 Q13) | 客户归属 + 加盟枝下层归属的客户 (§3.4 (b2)) |
| 我的上层 | 上 3 层直系 (AGENTS §6.6.1 Q13, 2026-09-22 落) | **不可见** (列表无「我的上级加盟商的客户」这条) |
| 跨枝 | 系统管理员 = 全森林;普通用户 = 不可见 (AGENTS §6.6.1 Q13) | 同 — (b2) 用 `root_id IS NOT DISTINCT FROM` 守卫 (§3.4) |

**关键**: **图谱可见性的扩围不动** (AGENTS §6.6.1 Q13 已定);本 ADR 只动**列表可见性**这条线。这条边界若混淆,会出现「下级在图谱里能看到的节点,在列表里反而看不到她的客户」这种比现状还糟的口径打架。

---

## 2. 决策 (本节不引入新口径,只**归档**主文档已定决策)

> **所有决策的字面来源**:
> - D4 / D5 / D6 / D7 / D8 / D9 → `customer-identity-system.md` §7
> - §3.4 四段式 → `customer-identity-system.md` §3.4
> - §6.5 S1-S7 + SHARE-1..7 → `customer-identity-system.md` §6.5
> - B1-B4 硬约束 → `customer-identity-system.md` §3.3
> - E-1 / E-2 / E-3 边界 → `customer-identity-system.md` §3.4 + §6.5

### 2.1 决策列表

| # | 决策 (字面引用主文档) | 落点 | 引用 |
|---|---|---|---|
| **RBAC-1** | 列表可见集合 = `viewerCustomerScopeSql(viewer)` 四段式 (a / b1 / b2 / c) | `customer-scope.ts` 新增函数 (Phase D) | 主文档 §3.4 |
| **RBAC-2** | 手机号分级表 = `mine` / `direct_downline` / `upline_shared` 明文;`subordinate` / `other` / `none` 走 `maskPhone` | `identity.ts` toView + 集成测试 | 主文档 §3.4 + §3.3 B4 + §9.1 INV-5 |
| **RBAC-3** | 推送机制 = `customer_share` 表 + S1-S7 + SHARE-1..7 | migration 0028 + `customer-share.ts` 新模块 | 主文档 §6.5 |
| **RBAC-4** | manager 角色在扩围后与 sales 同口径 (走 `viewerCustomerScopeSql`) | `auth/rbac.ts::customerRbacFilter` 重审 | 主文档 §7.2 D9 |
| **RBAC-5** | 禁止二次转发 (S7) + 推送扩散上限 (S6) | `customer-share.ts` 校验层 | 主文档 §6.5.2 S6 + S7 |

### 2.2 四段式可见集合 (RBAC-1,引用主文档 §3.4)

> **本节是 §3.4 字面引用,不加一字**。重写请改主文档,本 ADR 仅归档。

```
listVisibleFor(viewer) =            -- me = viewer 的 franchisee 行
  -- ★ v1.3 前置硬守卫: viewer.franchisee_id IS NULL → 只允许 (a)
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
                   -- ★ 推送人必须与我在同一棵树 (跨枝防护, reviewer P0-B)
                   AND ( NOT EXISTS (SELECT 1 FROM "user" f
                                     WHERE f.id = cs.from_user_id AND f.franchisee_id IS NOT NULL)
                         OR EXISTS (SELECT 1 FROM "user" f
                                    JOIN franchisee ff ON ff.id = f.franchisee_id
                                    WHERE f.id = cs.from_user_id AND ff.deleted_at IS NULL
                                      AND ff.root_id IS NOT DISTINCT FROM me.root_id) ))
  ) : ( (a) )
```

**集中点** (`customer-scope.ts` 顶部加注释): `viewerCustomerScopeSql(viewer)` 走 a+b1+b2+c 四段 — 将来收窄为「仅直接下级」时**只动 (b2) 子句**,调用方 (列表 / 胶囊计数 / `/api/me` 概览 / 行级过滤) 零改动。

### 2.3 手机号分级表 (RBAC-2,引用主文档 §3.4)

| 归属取值 | 手机号展示 | 唯一真相源 |
|---|---|---|
| `mine` 我的客户 (a) | **明文** | §3.4 手机号分级表 |
| `direct_downline` 我的直推加盟商本人 (b1) | **明文** | §3.4 手机号分级表 |
| `subordinate` 我的下层归属的客户 (b2) | **maskPhone** (`src/lib/utils.ts:24`) | §3.4 + B4 |
| `upline_shared` 上级推送给我的客户 (c) | **明文** (D8, 2026-09-25 拍: 推送即授权跟进) | §3.4 + D8 |
| `other` 他人客户 | **maskPhone** (理论上不出现在列表中, 若出现 = scope 漏检告警) | §3.4 + B4 |
| `none` 无归属 | **maskPhone** (兜底: 无归属 ≠ 全可见) | §3.4 + B4 |

> ⚠ **B4 硬约束 + 集中点** (主文档 §3.3): 手机号分级**仅在这一处表声明**;`identity.ts::toView` 与所有 view 路径都必须读这张表,禁止分写。

### 2.4 推送机制 (RBAC-3,引用主文档 §6.5.2 + §6.5.6)

| 规则 | 含义 | 来源 |
|---|---|---|
| **S1** | 只有该客户的归属人 (`customer.owner_id`) **或** `role='admin'` 能推送 | §6.5.2 |
| **S2** | 接收人 `to_user_id` 必须是推送者所在枝的下层用户 (同 `root_id` + `placement_path` 前缀) | §6.5.2 |
| **S3** | 推送 ≠ 转移归属 (`customer.owner_id` **不变**);「先到先得」归属规则**不受推送影响** | §6.5.2 |
| **S4** | 同 (customer, to_user) **仅一条 active 推送** (部分唯一索引);重复推送 → 409 `ALREADY_SHARED` | §6.5.2 |
| **S5** | 接收人 / 推送人 / 当前归属人 / admin 四方都能撤销;`revoked_at = NOW()`, `revoked_by` 必填 | §6.5.2 |
| **S6** | **扩散上限**: 同一客户 active 推送数 ≤ 5;同一接收人每日收到 ≤ 100;超限 → 400 `SHARE_LIMIT_EXCEEDED` | §6.5.2 (D8 明文风险配套) |
| **S7** | **禁止二次转发**: 被推送人不能把收到的客户再推给她的下层 | §6.5.2 |

| 不变量 | 含义 | 来源 |
|---|---|---|
| **SHARE-1** | 推送不写 `customer.owner_id` | §6.5.6 |
| **SHARE-2** | 推送不改变紧急度算法结果 | §6.5.6 |
| **SHARE-3** | 被推送人看到的是**同一份客户档案**, 不是副本 (无 `customer_copy` 表) | §6.5.6 |
| **SHARE-4** | 推送**双方**账号 (`from_user_id` / `to_user_id`) **任一停用** → 列表不可见 | §6.5.6 + AGENTS §6.7 |
| **SHARE-5** | `customer_share` 表必挂审计触发器 (`customer_share_audit`) | §6.5.6 |
| **SHARE-6** | `customer.owner_id` 被 transfer 后,该客户的 active 推送**保留**;新 owner 可撤销 (S5 已含) | §6.5.6 |
| **SHARE-7** | `(b1)` 命中的客户其 ownership 必须是 `direct_downline`,不得落 `other` | §6.5.6 + §3.4 ownership 第 6 态 |

### 2.5 manager 与 sales 同口径 (RBAC-4,引用主文档 §7.2 D9)

**决策**: 扩围后 `auth/rbac.ts` 的 `manager` 分支保留 (`managedStoreIds` 逻辑),但**不在 manager 上加额外门店过滤** — 与 `sales` 共用 `viewerCustomerScopeSql` 入口。

**理由**: ADR-0015 Q8 已冻结门店维度;现有 manager 分支实际无数据 (没有 `store` / `staff` 行)。扩围后保持「我的客户」= `(a+b1+b2+c)` 一致,避免 manager 看到列表 ≠ sales 看到列表的二次割裂。

### 2.6 集中收窄开关 (R-9 主人挂起项的兜底)

主文档 §9.2 R-9 标 ★ (主人 2026-09-25 显式挂起),本 ADR 落地时只做**最小兜底**:

1. **收窄开关集中在 `customer-scope.ts` 一处** (`viewerCustomerScopeSql` 单一真相源)
2. **收窄策略默认 = (b) 全下层 (与图谱同源)**, 提供 `config flag` (`viewerScope.includeSubordinateSubtree: boolean`, default `true`) 后续可改为「仅直接下级」,只动 (b2) 子句
3. **集中缓存开关** (`viewerScope.cacheEnabled: boolean`, default `false`) — 默认 no-store,任何缓存层必须能感知 `customer_share` 撤销
4. **调用方禁止自写可见性 SQL** (§3.4 「集中点」E-1) — 包括 `/api/customers` / `/api/me` / 胶囊计数 / 行级过滤

> ⏸ **R-9 优化方案 (列表膨胀的具体收窄策略)**:**待主人拍** —— 主人 2026-09-25 显式挂起,Phase D 开工前**必提醒**主人处理。

---

## 3. 保留 / 不动的硬约束 (与扩围无冲突,显式归档)

| # | 约束 | 来源 |
|---|---|---|
| **H1** | **单一真相源物理位置 = `src/lib/db/queries/customer-scope.ts`** (现 `myCustomerScopeSql` 所在文件) — 扩围后**不搬迁**;新函数 `viewerCustomerScopeSql` 加在同一文件顶部,顶部注释引用本 ADR | 主文档 §3.4 「集中点」段 |
| **H2** | **ID 化连接** (`user.customer_id` 账号↔档案 + `user.franchisee_id` 账号↔节点) — 扩围不引入 `phone_hash` 连接 | ADR-0016 D3/D4 + §3.3 |
| **H3** | **B1-B4 硬约束** (B1 `deleted_at IS NULL` / B2 viewer 无节点时 `ownership ∈ {none, mine}` / B3 「直推」仅表示 `referrer_id` / B4 mask 分级) | 主文档 §3.3 |
| **H4** | **图谱可见性不动** (AGENTS §6.6.1 Q13: 全树下层 + 上 3 层直系) — 本 ADR 只动列表可见性 | AGENTS §6.6.1 Q13 + §1.3 |
| **H5** | **节点 ⇒ 账号不变量** (AGENTS §6.7: 推送双方账号必须 active, §3.4 (c) 两个 `EXISTS user active` 子句对齐) | AGENTS §6.7 |
| **H6** | **`adminReparentNode` 不改 `referrer_id`** (AGENTS §6.8 拆栏;返回 `referrerTouched: false`) — 推送机制不依赖 referrer | AGENTS §6.8 |

---

## 4. 影响面

### 4.1 文件清单 (Phase D 实施时按此清单改动)

> **本清单由主文档 §8.4 Phase D 验收清单 + §6.5.4 API 表整合而成;具体行号**由实施时落地确认**,本 ADR 不锁行号 (与 ADR-0017 / 0018 同根原则 — 不锁 file:line, 只锁文件与口径)**。

#### 4.1.1 新增文件

| 文件 | 作用 |
|---|---|
| `drizzle/migrations/0028_customer_share.sql` | 表结构 + 索引 (主文档 §6.5.1 字面) + down.sql 必带 |
| `drizzle/migrations/0028_customer_share.down.sql` | 回滚 (ADR-0004 强制) |
| `src/lib/customer/customer-share.ts` (新模块) | S1-S7 + SHARE-1..7 校验层;推送 / 撤销 / 查询三函数 |
| `src/lib/db/queries/customer-share.ts` (新) | `customer_share` 表的 Drizzle 实体 + 索引调用封装 |
| `src/app/api/customers/[id]/share/route.ts` | `POST` (推送) |
| `src/app/api/customers/[id]/share/[userId]/route.ts` | `DELETE` (撤销) |
| `src/app/api/customers/shares/received/route.ts` | `GET` (我收到的推送列表) |
| `scripts/audit-customer-share.ts` | 巡检: 跨枝推送 / 越权推送 / 重复 active / 双方账号停用 (SHARE-4) |
| `tests/customer-share.test.ts` | 覆盖 S1-S7 + SHARE-1..7 + 四段式可见集合 + 手机号分级 |

#### 4.1.2 修改文件

| 文件 | 改动 | 引用 |
|---|---|---|
| `src/lib/db/queries/customer-scope.ts` | 新增 `viewerCustomerScopeSql(viewer)` = 四段式 (a+b1+b2+c);顶部注释引用 §3.4 + 本 ADR RBAC-1 | §3.4 + §2.2 |
| `src/lib/auth/rbac.ts::customerRbacFilter` | `manager` 分支去掉额外门店过滤,与 `sales` 共用 `viewerCustomerScopeSql` (RBAC-4) | §7.2 D9 |
| `src/lib/customer/identity.ts::resolveCustomerIdentity` | 加 `direct_downline` 第 6 态 (SHARE-7);`ownership` 枚举扩展 | §3.4 ownership 第 6 态 + §6.5.6 SHARE-7 |
| `src/app/api/customers/route.ts` (列表) | 接入 `viewerCustomerScopeSql(viewer)`,supersede `myCustomerScopeSql` 调用 | §3.4 + §8.4 |
| `src/app/api/me/route.ts` (概览) | 接入 `viewerCustomerScopeSql(viewer)` | §3.4 集中点 |
| 胶囊计数 (现 `customerTypeCounts` 邻近代码) | 接入 `viewerCustomerScopeSql(viewer)` | §3.4 集中点 |
| 行级过滤 (`rbac.ts` 内) | 接入 `viewerCustomerScopeSql(viewer)` | §3.4 集中点 |
| `src/app/api/customers/[id]/route.ts` (详情) | 详情也走 `viewerCustomerScopeSql(viewer)` 单行过滤 — 否则会出现「列表能看 / 详情打不开」割裂 | §3.4 (扩展) |

> ⚠ **详情单行过滤是本 ADR 新增的隐性要求**:主文档 §3.4 列举的「调用方」是列表 / 计数 / 概览 / 行级过滤,**未显式提详情**。但若详情不接同一口径,会出现「列表能看到一行但详情 404」的体验事故,且违反 §3.4 「集中点」精神。**本 ADR 视此为 §3.4 集中点的合理外推,不引入新决策**,实施时落地。

#### 4.1.3 不动的文件 (显式归档)

| 文件 / 模块 | 不动原因 |
|---|---|
| `src/lib/db/queries/franchisee.ts` (`classifyRelation`) | 图谱可见性不动 (H4);此函数已读 `referrer_id`,与主文档 §2.1 P1 supersede 一致 |
| `src/lib/auth/registration.ts` | 建号路径不涉及推送 (ADR-0013 + AGENTS §6.6) |
| `src/lib/auth/franchisee-account.ts` | 节点 ⇒ 账号不变量是 H5 的引用源,不重写 |
| `src/lib/auth/franchisee-reparent.ts` (`adminReparentNode`) | H6: 显式不动 `referrer_id` |
| `drizzle/0020_customer_owner.sql` 等已有 migration (位于 `drizzle/` 直下,非 `drizzle/migrations/`) | 不动;只加 0028 additive |
| `src/lib/follow-up/urgency.ts` | SHARE-2 不变量:推送不改变紧急度算法结果 |
| Flutter `modules/customer/` (UI 层) | 主文档 §8.4 Phase D 验收;UI 改动另起 ticket (本 ADR 不动) |
| `customer-scope.ts:27-49` `directDownlineFranchiseeSql` | 维持 (主文档 §2.3 「不动」项);`viewerCustomerScopeSql` 内 (b1) 子句仍引用 |

### 4.2 Migration 0028 字面 (主文档 §6.5.1)

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

**配套审计触发器** (SHARE-5): 参照 `drizzle/audit_trigger.sql` 行 41-44 `franchisee_audit` 模式,挂 `customer_share_audit` 触发器,推送 / 撤销都要留痕。**不挂 `deleted_at`** (主文档 §3.4 「不挂 deleted_at」 E1 注)。

**兼容红线** (ADR-0004):

- 表为纯 additive — 不动现有列 / 不动现有函数 / 不写 default
- `pnpm db:compat` 必过;老 APK 不受影响 (本表与 Flutter APK INSERT 路径无关)

### 4.3 新增 / 修改的 API (主文档 §6.5.4 字面)

| 方法 | 路径 | 入参 / 返回 |
|---|---|---|
| `POST` | `/api/customers/[id]/share` | `{ toUserId: string, note?: string }` → `{ id, customerId, fromUserId, toUserId, note, createdAt }` (S1+S2 校验失败 → 403/400;S6 超限 → 400 `SHARE_LIMIT_EXCEEDED`) |
| `DELETE` | `/api/customers/[id]/share/[userId]` | `{ revokedBy: string, reason?: string }` → 200;不存在 / 已撤销 → 404 (幂等: 重复撤销返 200) |
| `GET` | `/api/customers/shares/received` | 返回当前 user 收到的所有 active 推送 (列表角标用) |

**zod refine**: `note` ≤ 200 字;`reason` (撤销原因) 必填,写审计 (S5);S1 校验 `from_user_id` = 当前 user OR `role='admin'`。

### 4.4 巡检脚本 (`scripts/audit-customer-share.ts`)

| 检查项 | 含义 |
|---|---|
| 跨枝推送 | `from_user.franchisee` 与 `to_user.franchisee` 不同 `root_id` 且 admin 不是 `from_user` |
| 越权推送 | `from_user_id` 既不是 `customer.owner_id` 也不是 `role='admin'` |
| 重复 active | 同一 `(customer_id, to_user_id)` 多条 `revoked_at IS NULL` (S4 不变量违例) |
| 双方账号停用 | `from_user_id` 或 `to_user_id` 的 `user.is_active = false` 但 `revoked_at IS NULL` (SHARE-4 不变量违例) |
| 推送人节点软删 | `from_user.franchisee.deleted_at IS NOT NULL` 但推送仍 active (§3.4 (c) 「推送人节点软删失效」条款) |

`--strict` 模式:任一违例 exit 1;非 strict 默认只报告不阻断。

---

## 5. 风险

> **本节不引入新风险;只把主文档 §9.2 R-9 / R-10 / R-11 三条★级风险与本 ADR 实施直接相关的部分显式归档**。

### 5.1 R-9 (列表膨胀) — ⏸ 主人 2026-09-25 显式挂起

| 字段 | 内容 |
|---|---|
| **现象** | Phase D 扩围后 viewer 列表候选集从 `owner_id = 我` 单集合扩到 `owner_id = 我 ∪ 同枝下层 ∪ customer_share 推送给我`,枝深的销售员可见行数显著增长 (`subordinate` 子树可能含数千客户) |
| **主人原话** | 「需要优化方案,本任务暂缓」(主文档 §9.2 ★ 注) |
| **本 ADR 的最小兜底** (§2.6) | ① 集中收窄开关 (config flag `viewerScope.includeSubordinateSubtree`);② 默认 no-store;③ 集中点 E-1 (调用方禁止自写);④ `bash tools/check-ui-density.sh` Phase D 上线前**必跑**全路由,`visibleRows ≥ 11` 棘轮不破 |
| **未决项 (待主人拍)** | 是否接受「枝深销售可见数千行」作为默认行为?是否需要先观察期灰度 (新功能先灰度 30 天再全量)? |

### 5.2 R-10 (推送撤销立即生效) — ⏸ 主人 2026-09-25 显式挂起

| 字段 | 内容 |
|---|---|
| **现象** | 用户期望「撤销推送 = 列表马上少一行」;若后端 / 前端任何一层缓存 `customer_share` 结果,撤销后用户仍能看到那行,信任崩塌 |
| **本 ADR 的最小兜底** | ① `/api/customers` 不缓存可见集合结果 (Drizzle 直查 + `revoked_at` 索引);② 推送撤销响应立即触发客户端刷新 (Flutter `RefreshIndicator` / Web admin `router.refresh()`);③ 集成测试断言: 推送 → 撤销 → 100ms 内列表 API 不再返回该客户;④ `idx_customer_share_to_active` 索引 `(to_user_id, revoked_at)` 保证撤销即过滤 |
| **未决项 (待主人拍)** | 撤销响应的客户端刷新触发是否要做成「服务端推送 (SSE / WebSocket)」而非「客户端轮询」? |

### 5.3 R-11 (is_seed 灰度期 30 天) — 主文档 §5.4 + §9.2

| 字段 | 内容 |
|---|---|
| **现象** | D3 (2026-09-25 拍) 客户类型从三态 (`franchisee` / `seed` / `normal`) 简化为二态;`is_seed` 列 DB 暂不 DROP;灰度期 30 天 |
| **本 ADR 的处理** | (本 ADR 与 is_seed DROP 无直接耦合 — `customer_share` 表是新增,不动 `customer.is_seed` 列);仍按主文档 §5.4 / §9.2 R-11 走 |
| **唯一相关** | 30 天后 `drizzle/0029_drop_customer_is_seed.sql` 编号已被 `customer_share` 占用 — 需改用 `0030` 或别的未占编号 (具体编号 Phase C/D 实施时确认) |

### 5.4 实施期通用风险 (本 ADR 新增的提醒,不引入新决策)

| 风险 | 缓解 |
|---|---|
| **R-IMPL-1** 详情单行过滤漏接 `viewerCustomerScopeSql` → 列表能看但详情 404 | §4.1.2 「详情单行过滤是本 ADR 新增的隐性要求」;Phase D 验收清单必检 |
| **R-IMPL-2** migration 编号冲突 (0028/0029 已有占位) | Phase D 实施前先 `ls drizzle/*.sql` 确认最终编号;按 §4.2 字面 `0028_customer_share.sql` 起草,主文档 §5.4 已预留 0029 = is_seed drop |
| **R-IMPL-3** customer-share.ts 模块与 customer-scope.ts 出现循环 import | 模块边界: `customer-share.ts` 只依赖 `schema.ts` + `auth/registration.ts` (校验归属);`customer-scope.ts` 不依赖 `customer-share.ts` (只是 SQL 引用 `customer_share` 表的列名) |
| **R-IMPL-4** 推送扩散上限 (S6) 默认值 5 / 100 拍的是否合理?无产品数据支撑 | 上线后 7 天观察期由 `scripts/audit-customer-share.ts` 跑推送异常检测 (`share_density` 统计),主人根据实测调阈值 |

---

## 6. 候选评估 (本 ADR 的「不动」决策 vs 已评估过的替代方案)

> 本节记录**已被主文档拍板排除的替代方案**,避免后人重复评估。

| 替代方案 | 排除原因 | 出处 |
|---|---|---|
| **A. 维持 `myCustomerScopeSql` 两段式,不做扩围** | D4 已拍 (主文档 §7.1) 业务诉求明确 | §7.1 |
| **B. 走 `phone_hash` 做下级归属的客户匹配** | ADR-0016 D3/D4 已拍「手机号不是身份」 | ADR-0016 D3/D4 |
| **C. 用多归属链接表 (`customer_owner`) 取代推送** | ADR-0015 Q11 已评估 + 拍 B (单归属 + 推送独立可见性) | ADR-0015 Q11-C |
| **D. 用 GraphQL 联合查询取代 SQL 扩围** | 项目未引入 GraphQL;引入 = 架构变,超出本 ADR 范围 | — |
| **E. 把推送机制放在 Flutter 端 (本地缓存推送列表)** | 违反「单一真相源」(H1) + 撤销后无法立即生效 (R-10) | §5.2 |

---

## 7. 实施闸门 (Phase D 开工前必走完,否则禁止合并)

> **本节是主文档 §8.4 「本阶段是隐私扩张点,开工前必走完」三条的字面归档 + 本 ADR 补充的实施前 checklist**。

### 7.1 必走三步 (主文档 §8.4 字面)

1. ✅ `docs/identity-privacy-review.md` 拍板 (本 ADR 关联文件)
2. ✅ 主人 `ask_user` 拍「同意扩围下级 / 上级推送可见性」
3. ✅ 评审通过才能合并 PR

### 7.2 实施前 checklist (本 ADR 补充)

- [ ] 本 ADR (0019) 状态从 `⏳ Proposed` 改 `✅ Accepted`
- [ ] 主文档 §8.4 Phase D 验收清单的「RBAC/隐私评审通过」勾选
- [ ] `ls drizzle/*.sql` 确认 0028 / 0029 实际可用编号 (主文档 §5.4 / §6.5.1 已预留)
- [ ] `bash tools/check-migration-compat.sh` (migration 0028 additive) — 必过
- [ ] `pnpm type-check` — 必过 (AGENTS §3 双线同步)
- [ ] (UI 改前)`bash tools/check-ui-density.sh` — 棘轮不破
- [ ] (UI 改前)`bash tools/check-auto-snapshot-extension.sh` — ✓

---

## 8. 关联文档

| 文档 | 关系 |
|---|---|
| [`docs/customer-identity-system.md`](../customer-identity-system.md) | **口径来源** (§3.4 / §6.5 / §7 / §8.4 / §9.2 — 本 ADR 字面引用) |
| [`docs/identity-privacy-review.md`](../identity-privacy-review.md) | **本 ADR 实施闸门文件** (§7.1 必走三步第 1 条) |
| [`docs/adr/0015-subject-model.md`](./0015-subject-model.md) | 「我的客户」口径 (Q2) / 主体模型 / 归属 vs 建档 |
| [`docs/adr/0016-identity-anchor.md`](./0016-identity-anchor.md) | ID 化连接 (本 ADR §3 H2 引用) |
| [`docs/adr/0017-web-admin-unfreeze.md`](./0017-web-admin-unfreeze.md) | web admin 解冻 — web admin 列表 / 详情同步需双线 (Phase E) |
| [`docs/adr/0004-schema-evolution.md`](./0004-schema-evolution.md) | additive 约束 (migration 0028 必走) |
| `AGENTS.md` §6.6.1 | 主体模型不变量 / 「我的客户」归属 ∪ 直推 |
| `AGENTS.md` §6.7 | 节点 ⇒ 账号不变量 (本 ADR §3 H5 引用) |
| `AGENTS.md` §6.8 | 拆栏 / `adminReparentNode` 不改 `referrer_id` (本 ADR §3 H6 引用) |
| `src/lib/db/queries/customer-scope.ts` | 单一真相源 (本 ADR 实施时新增 `viewerCustomerScopeSql`) |
| `src/lib/utils.ts:24` `maskPhone` | 手机号打码 (本 ADR §2.3 B4 引用) |
| `drizzle/audit_trigger.sql` 行 41-44 `franchisee_audit` | `customer_share_audit` 触发器参照模式 |
| `drizzle/0020_customer_owner.sql` 等 | 已有 migration (本 ADR 不动) |

---

## 9. 元数据

- **起草**: 2026-09-25 worker (Codex 风格);依赖主文档 v1.3 + AGENTS v0.1.5
- **拍板**: ⏳ 待主人 `ask_user` 拍「同意扩围下级 / 上级推送可见性」+ `identity-privacy-review.md` 签字
- **本决策对应元宪法**: `docs/CHARTER.md` §4 (域划分) · §7 (反模式沉淀)
- **实施闸门**: 评审 + 主人 ask_user + migration `pnpm db:compat` 三者全过方开工
- **下一步 (拍板后)**: 状态转 `✅ Accepted` · INDEX 加一行 (时间倒序顶部) · 主文档 §8.4 验收清单勾上 · Phase D 实施 task-snapshot