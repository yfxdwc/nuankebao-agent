# ADR-0015: 主体模型 —— 人 / 账号 / 客户 / 节点 (消歧 + 单一真相源)

> **状态**: ⏳ Draft (待主人拍板; 本文件只写现状 + 候选, 未定的一项都不标 Accepted)
> **日期**: 2026-09-22
> **影响范围**: `user` · `customer` · `franchisee` · `referral_code` / `referral_reward` ·
> 客户列表 / 图谱 / 概览口径 · RBAC 行级过滤 · 建号路径 · 存量数据修复
> **相关**: [ADR-0013 账号 = 客户](./0013-account-customer-binding.md) ·
> [ADR-0006 加盟边界](./0006-franchise-boundary.md) ·
> [ADR-0012 会员 + 推荐码](./0012-membership-billing.md) ·
> [ADR-0014 多根 + 向上认领](./0014-multi-root-and-upline-claim.md) ·
> [ADR-0004 Schema 演进红线](./0004-schema-evolution.md) ·
> AGENTS §6.6 / §6.7 / §6.8

---

## 1. 背景 (主人原话)

> 「当前的客户体系和 app 用户体系还是有不够清晰明确的区分和关系。我们需要先**彻底理清楚这个底层**。」

**触发路径**: 2026-09-22 连续三次改动都在同一个地方卡住 ——

1. 修「自己不应该是自己的客户」: 发现**没有列**连接 `user` 和 `customer`, 只能靠手机号 hash 约定;
2. 修「列表「加盟」= 直推」: 发现「加盟」的判定散在 4 处, 而且和测试注释里写的口径已经不一致;
3. 想接 RBAC 行级过滤: 发现「**我的客户**」这个最基本的词, 代码里有 4 种互不相同的实现, 谁也说不清算哪个。

结论: 这不是某个查询写错了, 是**底层主体模型没有被定义过**。本 ADR 的目标是把它定义出来。

---

## 2. 现状地图 (实测, 可复现)

### 2.1 一个人可以有 5 张记录

| 表 | 位置 | 语义 | 关键列 |
|---|---|---|---|
| `user` | `schema.ts:293` | **能登录的账号** | `role` · `username` · `password_hash` · `franchisee_id` · `default_store_id` |
| `customer` | `schema.ts:369` | **被维护的客户档案** | 健康三密文 · `is_seed` · `referrer_id` · `store_id` · `created_by` |
| `franchisee` | `schema.ts:72` | **加盟树上的一个点** | `placement_parent_id` · `placement_path` · `root_id` · `referrer_id` |
| `staff` | `schema.ts:353` | 员工 (第 5 张"人"表) | `user_id` · `display_name` · `store_id` —— **当前 0 行, 基本未启用** |
| `salon_guest` | `schema.ts:970` | 沙龙带约客人 (可无账号) | `brought_by_user_id` · `name` · `phone_hash` |

### 2.2 唯一的"真连接"只有一条

```
user.franchisee_id ──────────────► franchisee.id     ← 全库唯一一条人↔人 FK (nullable, 应用层强制)

user.phone_hash  ~~~~ 约定 ~~~~  customer.phone_hash   ← 没有列连接, 只有"值相等"
user.phone_hash  ~~~~ 约定 ~~~~  franchisee.phone_hash ← 同上
```

- `user` ↔ `customer` **没有任何列连接** (ADR-0013 §5 已承认, 本 ADR 要正面解决)。
- 三张表**各自存一份**同一个人的姓名 + 加密手机号 → 改名/改号要三处同步, 且没有统一写路径。
- 全库没有第二条外键把"同一个人"的账号面 / 客户面 / 结构面钉在一起。

### 2.3 四条"谁带来谁"的边同时存在

| # | 边 | 存在哪 | 语义 | UI 出口 |
|---|---|---|---|---|
| 1 | **账号推荐** | `referral_reward(referrer_user_id → referee_user_id)` (`schema.ts:1212`) + `referral_code` (`schema.ts:1190`) | 谁把账号带进来 —— 发会员天数的依据 | ✅ 会员奖励页 |
| 2 | **加盟"推荐人"** | `franchisee.referrer_id` (`schema.ts:92`) | 谁把她拉进加盟 (业务关系) | ⚠️ 图谱节点详情 |
| 3 | **加盟"点位父"** | `franchisee.placement_parent_id` (`schema.ts:93`) | 她挂在谁下面 (结构关系) | ✅ 图谱 / 落位 |
| 4 | **客户"推荐人"** | `customer.referrer_id` (`schema.ts:405`) | 客户图谱"老带新" | ❌ **全库零调用者 (死)** |

第 4 条的死亡证据 (三件套都没人用):

```
src/app/api/customers/graph/route.ts                  ← 端点, 无调用方
flutter_app/lib/core/providers/service_providers.dart:202  myCustomerGraphProvider ← 无人 watch
flutter_app/lib/modules/customer/widgets/customer_graph_view.dart:191 CustomerGraphView ← 无实例化
```

而 `customer.referrer_id` **是会被写入的** (`registration.ts:175`、`signup.ts:181`、`updateCustomer`),
只是**没有任何界面显示它** —— 有写入、没出口。

### 2.4 ADR-0013 的 "no_link" 让 1 和 4 永久分叉

ADR-0013 D4 明确: 推荐码**不写** `customer.referrer_id`（两条推荐线各自独立）。
于是同一句「我推荐了小张」，在库里的落地完全取决于**走的哪个入口**：

| 入口 | 边 1 (账号推荐) | 边 2 (加盟推荐) | 边 3 (点位父) | 边 4 (客户推荐) |
|---|---|---|---|---|
| 自助注册 `POST /api/auth/register` | ✅ 写 | ➖ | ➖ (未加盟) | ✅ 写 = 推荐人档案 (`signup.ts:181`) |
| 管理员建号 (`createAccountWithProfile`) | ✅ 写 | ➖ | ➖ | ✅ 写 = `customerReferrerId` (`registration.ts:175`) |
| 落位建节点 (`linkAccountAndCustomer`) | ➖ | ✅ 写 | ✅ 写 | ✅ 建档案 (不写推荐人) |

**产品语言（"我推荐的人"）与数据（4 条边）没有一一对应** —— 这就是"底层不清"的核心。

---

## 3. 问题清单（每条都带证据）

### Q1 「客户」是一类还是两类 —— 不明确

`customer` 表同时装着两类语义完全不同的记录：

| 类别 | 怎么进来 | 有账号吗 |
|---|---|---|
| **账号客户** | 建号即建档 (ADR-0013) | ✅ 有 |
| **非账号客户** | 导入存量、手动新建、到店客人 | ❌ 无 |

表里**没有列**区分它们，只能靠 `EXISTS(user.phone_hash = customer.phone_hash)` 现算。
"客户列表"要显示哪一类、算不算"客户总数"，没有定义。

### Q2 「我的客户」有 4 种实现，且互不相同 —— 最要命

| 候选 | 代码位置 | 覆盖谁 |
|---|---|---|
| a. 我建的 | `rbac.ts:85`（sales 分支 `created_by = me`） | 我手动建档的人 |
| b. 我店里的 | `rbac.ts:87`（`store_id = my default store`） | 同店的人（门店维度） |
| c. 我推荐的 | `customer.referrer_id`（无查询实现） | 走"老带新"进来的人 |
| d. 我的直推加盟 | `myDirectDownlineFranchiseeSql`（本次刚改） | 点位父 = 我的人 |

这四者**在真实数据下不等价** —— 例：BFS 顺延落位时（AGENTS §6.8）
「推荐人那侧满了 → 挂到别人名下」，同一个人可以"由 A 推荐、挂在 B 下面"，
于是 a/c 认为她是 A 的客户、d 认为她是 B 的客户。

**当前实现的选择是"全都要又都不是"**: 列表根本不传 `rbacCtx` → 退回全库口径
(`src/app/api/customers/route.ts:117` 的 `listCustomers({...})` 里没有 `rbacCtx`)，所以上面四种一个都没生效。

### Q3 「我推荐的人」到底是哪条边 —— 没定

见 §2.4 表格。至少需要明确：**哪些判定允许读哪条边**。
现在 `franchisee.referrer_id` 与 `placement_parent_id` 已被 AGENTS §6.8 拆栏，
但 `customer.referrer_id` 与它们的三角关系没人写过。

### Q4 `customer.referrer_id` 死活未定 —— 死代码比错代码更危险

它在写、在被 `updateCustomer` 校验、有完整端点 + Flutter provider + 视图类，
但**没有任何用户能看到它**。留着会被后来人当成真相源（本 ADR 的起草过程本身就踩了这个坑）。

### Q5 admin / 根账号要不要客户档案 —— 文档没写

ADR-0013 D1 说"任何建号路径必须有同手机号 customer 档案"，
D2 只豁免了 admin 的**推荐码**。实测 **prod 库管理员 (`id=1`) 没有档案**：

```
 prod: 2 users / 1 customer / 1 franchisee   →  user id=1 (admin) has_customer = false
```

这是"违反不变量"还是"admin 本该豁免"？两种解释都说得通 → 必须写死。

### Q6 非 app 的人（沙龙带约客人）算不算客户 —— 与"每个用户首先是别人的客户"冲突

`salon_guest` 存了姓名 + 加密手机号 + 谁带来的，但**不建 customer 档案**。
按 ADR-0013 的主人口径「每个用户首先都肯定是另一个用户的客户」，
这些被带约来的人天然就是"带约人的客户"，但系统里她们**不存在于任何人的客户列表**。

### Q7 全靠约定、没有约束 —— 已经在漂（实测）

| 检查项 | 本地 dev 库 | prod 库 |
|---|---|---|
| `referral_code` 孤儿（指向已删账号） | **254** | 0 |
| `user` 有账号、没客户档案 | 36 / 36（customer 表被清空） | **1 / 2（admin）** |
| `customer` 有档案、没账号 | 0（表为空） | 0 |
| `franchisee` 孤儿节点（§6.7 明令禁止） | **3** | 0 |

另: ADR-0013 写的"唯一建号入口 `createAccountWithProfile`"**已被绕过** ——
`src/lib/billing/signup.ts:156` 直接 `insert(userTable)` + `insert(customer)`，
自己维护了一遍不变量（当前维护住了，但两个入口 = 将来必分叉）。

---

## 4. 决策草案（⏳ 每一条都待主人拍板）

> 下面每条给「选项 + 建议 + 代价」。**建议不等于决定**，主人拍哪条就落哪条。

### Q1 建议: 不拆表, 用**派生标记**区分两类

- 选项 A (建议): 保留一张 `customer`，新增派生字段/视图列 `has_account`（由 `phone_hash join user` 得出）。
  文档明确"customer = 主体档案，账号只是它的一个可选面"。
- 选项 B: `customer.kind = 'account' | 'walk_in'` 落列（需回填 + 新老客户端兼容）。
- 选项 C: 拆成 `customer` + `lead` 两张表。
- **建议 A**：拆表会牵动健康数据 / 跟进 / 图谱 / 沙龙 / RBAC 全链路，收益不抵风险；
  `has_account` 是纯派生，不引入新真相源。

### Q2 建议: 定义 `我的客户 = 我建的 ∪ 我的直推加盟客户`

- 选项 A: `created_by = 我`（W5 RBAC 现成写法，最小改动）。
- 选项 B (建议): `created_by = 我` **∪** 点位父 = 我（直推加盟）。
- 选项 C: `customer.referrer_id = 我的档案`（老带新口径）。
- **建议 B**：与上一轮拍定的「列表加盟 = 直推」自然衔接；覆盖"我建的普通客户 + 直推加盟客户"。
  代价: 要同时吃 `created_by` 和 `placement_parent_id` 两个来源，需要一条显式 SQL 并加单测。
- ⚠ **前置条件（阻塞）**: `listCustomers` 要吃 `rbacCtx` 就必须先解决"Auth.js session 里没有 `role`"
  （`src/lib/auth/config.ts:73` 只塞了 `id` / `phone`）—— 否则 admin 会被当 sales 过滤。
  这一条应作为 Q2 的**独立前置任务**先做。

### Q3 建议: 一条边管一类问题，**禁止交叉**

| 问题 | 唯一真相源 |
|---|---|
| 谁把我带进 app（发会员天数 / 推荐人确认） | `referral_reward`（边 1） |
| 我挂在谁下面（图谱 / 落位 / 上下级可见性） | `franchisee.placement_parent_id`（边 3） |
| 谁把我拉进加盟（业务展示，**不参与任何判定**） | `franchisee.referrer_id`（边 2，只读展示） |
| 客户"老带新" | 见 Q4 |

**规则**: 任何权限 / 可见性 / 计数 / 奖励判定，只允许引用上表最后一列；
其余边只能用于展示，且必须在代码注释里标注"仅展示"。

### Q4 建议: 先**废弃死链路**，要重启再单开 ADR

- 选项 A (建议): 删除 `/api/customers/graph` + `myCustomerGraphProvider` + `CustomerGraphView`；
  `customer.referrer_id` 列**保留**（ADR-0004 禁止 DROP），标 `@deprecated 仅存量`。
- 选项 B: 接一个 UI 出口（客户图谱 tab 展示"老带新"关系）。
- **建议 A**：当前没有任何产品需求在用它，留着只会继续误导；
  真要"老带新图谱"时，按 Q3 的规则重新定义边，再单独开 ADR。

### Q5 建议: admin **显式豁免**建档，根加盟商**必须**建档

- `role = 'admin'` → 允许没有客户档案（它不是任何人的下线，也不参与客户维护）。
- 根加盟商 / 普通 sales → **必须有**同手机号 `customer` 档案（ADR-0013 D1 不变）。
- 写进 AGENTS §6.6 的不变量清单，并让 `scripts/smoke-registration.ts` 覆盖 admin 豁免分支。

### Q6 建议: 沙龙客人**不自动建档**，但提供"转为客户"入口

- 理由: 中老年销售要的是干净列表；自动建档会让客户列表被大量"只来过一次的人"污染。
- 落地: `salon_guest` 保持原样 + 新增一键"转为我的客户"（建档后走同一套不变量 + 归属口径）。

### Q7 建议: 分两步把"约定"升成"约束"

- **第一步（additive，兼容 ADR-0004）**: 加 `user.customer_id`（nullable）+ 回填 + 唯一约束。
  从此账号↔档案有列可查，不再只靠 `phone_hash`。
- **第二步（另开 ADR）**: 给 `referral_reward` / `franchisee` / `customer` 之间的引用加 FK 与删除策略
  （当前 254 条孤儿码就是"没有删除策略"的直接后果）。

---

## 5. 建议的目标模型（一页图）

```
                    一个自然人
              identity = phone_hash (加密手机号, 唯一锚点)
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────▼────┐      ┌─────▼─────┐     ┌─────▼──────┐
   │ 账号面   │      │  客户面    │     │  结构面     │
   │ user    │      │ customer  │     │ franchisee │
   ├─────────┤      ├───────────┤     ├────────────┤
   │ 能登录   │      │ 被谁维护   │     │ 挂谁下面    │
   │ role    │      │ 健康档案   │     │ placement_ │
   │ 会员     │      │ 跟进记录   │     │  parent_id │
   │ 推荐码   │      │ is_seed   │     │ 树/路径     │
   └────┬────┘      └─────┬─────┘     └─────┬──────┘
        │                 │                 │
        └────────── 唯一真连接 ──────────────┘
                 user.franchisee_id → franchisee.id
                 user.customer_id   → customer.id      (Q7 第一步新增)

   关系边 (Q3: 一条边只管一类问题, 禁止交叉)
   ─────────────────────────────────────────────
   账号推荐   referrer_user_id → referee_user_id   (发奖 / 确认, 唯一真相)
   点位结构   franchisee.placement_parent_id       (图谱 / 落位 / 可见性, 唯一真相)
   加盟推荐   franchisee.referrer_id               (仅展示, 不参与判定)
   客户老带新 customer.referrer_id                 (Q4 拍 A = 废弃死链路)
```

**三条不变量的目标形态**（拍板后写进 AGENTS §6.6）:

1. 一个自然人 = 一个 `phone_hash`；账号面 / 客户面 / 结构面**都是它的可选面**，不是三个独立的人。
2. 有账号的人，其客户面与结构面由**建号唯一入口**统一创建（§6.6 现状）+ 有列可查（Q7 第一步）。
3. 任何"谁的谁"的判定，只允许读 Q3 表里那一列；其余是展示字段。

---

## 6. 影响

| 拍板项 | 影响的文件 / 模块 | 规模 |
|---|---|---|
| Q2 (我的客户口径) | `queries/customer.ts` · `api/customers/*` · `api/me` · `auth/viewer.ts` · `rbac.ts` | 中 (需先补 session role) |
| Q3 (边禁止交叉) | 全仓 `referrer_id` / `placement_parent_id` 读点 | 小 (审计 + 注释) |
| Q4 (废弃死链路) | `api/customers/graph` · `service_providers.dart` · `customer_graph_view.dart` | 小 (删 3 处 + 灰 Excel 列) |
| Q5 (admin 豁免) | `registration.ts` · `AGENTS §6.6` · `smoke-registration.ts` | 小 |
| Q6 (沙龙转客户) | `modules/salon/*` · `salon_guest` → `customer` | 中 (新功能, 需单开) |
| Q7 (加 `user.customer_id`) | `schema.ts` + migration (additive) + 回填脚本 + 建号入口 | 中 |

**兼容红线**（ADR-0004）: Q7 只允许 **additive**（加可空列 + 回填 + 唯一约束）；
`customer.referrer_id` 这类老列**不删**，只标废弃。

---

## 7. 风险 / 遗留

- ⚠️ **Q2 是阻塞项**: 没先补 `session.role` 就接行级过滤，会把 admin 也按 sales 过滤
  （`config.ts:73` 只塞 `id`/`phone`）。**顺序不能反**。
- ⚠️ **存量数据已漂**（本地 254 条孤儿码 / 3 个孤儿节点；prod 管理员无档案）。
  拍板后需配一次存量巡检 + 修复（可参考 `scripts/audit-orphan-nodes.ts` 的形态）。
- ⚠️ **本 ADR 只定义模型，不动代码**。落地要按 Q1–Q7 拆成独立小步提交（每步单独 task-snapshot）。
- ⚠️ **`customer.referrer_id` 若拍 A（废弃）**，需在 `docs/api.md` + Flutter README 同步标注，
  否则下一个人还会照旧踩。

---

## 8. 关联文档

- [ADR-0013 账号 = 客户](./0013-account-customer-binding.md) —— 本 ADR 的 §6.6 不变量来源
- [ADR-0006 加盟边界](./0006-franchise-boundary.md) —— 加盟不涉及钱（本 ADR 不改这条）
- [ADR-0012 会员 + 推荐码](./0012-membership-billing.md) —— 边 1 的规则来源
- [ADR-0014 多根 + 向上认领](./0014-multi-root-and-upline-claim.md) —— 结构面的多根语义
- [ADR-0004 Schema 演进红线](./0004-schema-evolution.md) —— Q7 的 additive 约束
- `AGENTS.md` §6.6 / §6.7 / §6.8 —— 建号 / 节点⇒账号 / 拆栏 三组不变量
- `docs/data-model.md` · `docs/api.md`

---

## 9. 元数据

- **起草**: 2026-09-22 (Codex, 基于本轮实测: 本地库 + prod 库 + 全仓 grep)
- **本决策对应元宪法**: `docs/CHARTER.md` §4 (域划分) · §7 (反模式沉淀)
- **拍板后动作**: 状态改 ✅ Accepted + 在 `docs/adr/INDEX.md` 补一行 + 把 §5 三条不变量写进 `AGENTS.md §6.6`
- **下一步**: 主人逐条回 Q1–Q7 → 本 ADR 转 Accepted → 按 §6 拆小步实施
