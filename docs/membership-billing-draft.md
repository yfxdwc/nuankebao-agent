# 会员付费系统 — 工业级草案 (v0.2)

> **状态**: 🟡 **草案 (DRAFT) — 待主人拍板**. 本文只提方案与决策点, **不含任何已实施代码**。
> 拍板后: 决策沉淀成 `docs/adr/0012-membership-billing.md`, 实施细节拆到 `docs/billing.md`。
>
> **v0.2 修订 (2026-09-19, 依主人补充信息)**:
> - 计费模型从"租户订阅" → **个人订阅**: 付费方 = 每个用户自己充值, 与门店/加盟无关
> - **免费档定义**: 免费用户可用除 9 项外的全部功能; 会员可用全部
> - **到期行为**: 停止会员功能, **继续用基础功能**(不是只读停用)
> - **价格**: 单月 ¥69 / 开通自动续费 ¥49·月
> - **推荐码**: 每人固定 6 位; 注册时可选填; 双方各得 15 天会员权益
> - **收款主体**: 个体工商户账户 (新增 §10.1 类目/资质/自动续费可行性)
> - 计费域与业务资金隔离: "加盟体系本身不收费；软件订阅费与资格/层级解耦" (ADR-0006 修订项)
>
> **阅读顺序**: 本文件 → [ADR-0006 加盟体系 + 合规边界](./adr/0006-franchise-boundary.md)(红线) →
> [phase-3-saas §3.5](./phase-3-saas.md)(2026-09 旧草案) → [security-compliance.md](./security-compliance.md)
>
> ⚠️ 本文所有合规/资质判断都是**工程口径 + 公开常识**, **不替代法律与税务意见**。上线前必须:
> ① 律师复核推荐码机制与用户协议; ② 代账确认税务与发票; ③ 渠道服务商确认个体户类目与周期扣款。

---

## 0. TL;DR (一页看懂)

1. **个人订阅制**: 每个用户自己充值; ¥69/月 (单月) 或 ¥49/月 (开通自动续费)。**与门店/加盟/团队成本无关**。
2. **两档能力**: 免费档 = 除 9 项会员功能外的全部功能; 会员档 = 全部功能。到期 → **自动降回免费档, 基础功能照用, 数据一条不删**。
3. **推荐码**: 每人固定 6 位; 新用户注册时可选填; **双方各得 15 天会员权益** (服务权益, 不可提现/转让)。
   ⚠️ 这是全案**最需要律师复核**的一条 (避免被解读为"拉人头计酬") → 见 §2.3 五道护栏。
4. **钱与加盟物理隔离**: `billing_*` 表与 `franchisee`/`customer` 无任何外键或金额流转; 计费代码不 import 加盟查询 (ADR-0006 §2 红线)。
5. **先做不算钱的 S0** (2~3 天): 免费/会员判定 + 推荐码 + 人工开通 (个体户收款码/对公转账) —— 0 支付集成、不等资质, 立刻能收第一笔。
6. **在线支付 S1** (1~2 周): 微信/支付宝 APP 支付 + 回调幂等 + 每日对账。**自动续费 (周期扣款) 单独一段 S2**, 因为个体户开通代扣成功率低 (§10.1)。
7. **判权一律服务端**: 会员功能入口在客户端隐藏 + 服务端 402 拒绝; 基础功能永不锁死。

---

## 1. 现状与前提 (代码事实, 2026-09-19)

| 事实 | 出处 | 影响 |
|---|---|---|
| 无任何计费/支付代码 | `grep` 全仓 | 全新域; 无历史包袱 |
| `franchisee`/`customer` **无金额字段** (红线) | ADR-0006 §2 + `schema.ts` | 计费域必须独立, 不得回写加盟树 |
| `user` 表: id/name/role/avatar_url, **无会员字段** | `schema.ts` | 加会员只需新增表 (不动 `user` 语义) |
| AI 有真实边际成本, **无用量台账** | `src/lib/ai/client.ts` (只有 `usage` 返回) | 付费功能里的 AI 调用要先补台账 (S2) |
| AI 接口: `/api/ai/{profile,follow-up,repurchase-prediction,effect-analysis}` | `src/app/api/ai/` | 会员判权的落点很清楚 (4 个 route) |
| 互动记录: `/api/interactions` (GET/POST) | 同上 | 判权点 |
| 生日提醒: `customer.birthday_remind_days` + `core/utils/birthday.dart` | 代码事实 | 判权点 = 客户页提醒条 + 表单开关 |
| 图片上传: `POST /api/photos` + wellness 上传器 | 同上 | 判权点 |
| **沙龙 (meeting) 不存在**: `flutter_app/lib/modules/meeting` 已不在仓库 | `find` 实测 | 该功能未实施 → 会员权益里先"占位", 上线即会员功能 (§2.2) |
| 部署: 自有服务器 + Cloudflare Tunnel | `deploy/production-plan.md` | 回调可收; 但**大陆区 ICP 备案 + 支付类目资质是硬门槛** |
| 审计: 5 表触发器 + `audit_log` | `drizzle/audit_trigger.sql` | 钱要更严 → 独立 append-only 账本 |
| 双域: APK = 生产域, WEB = 脚手架 | ADR-0008 | 付费 UI 先做 APK; 财务后台属"纯管理功能" (D13) |

---

## 2. 收费模型 (产品侧, v0.2 核心)

### 2.1 两档能力

| 档 | 谁 | 能用什么 |
|---|---|---|
| **免费档 free** | 所有注册用户 (默认) | 客户档案 / 养生记录(不含图片) / 跟进任务 / 客户图谱 / 加盟网络 / 「我的」与全部设置 / 数据查看 |
| **会员档 member** | 付费中, 或持有推荐权益/赠送权益 | **全部功能** (免费档 + 下面 9 项) |

**到期后**: 不冻结、不清数据、不降权客户数量 → 只是**那 9 项会员功能关闭** (入口隐藏 + 服务端 402), 基础功能照常用。

### 2.2 会员功能清单 (9 项, 主人口述)

| # | 功能 key (服务端) | 主人说法 | 实施状态 | 免费 | 会员 | 判权落点 |
|---|---|---|---|---|---|---|
| 1 | `ai.assistant` | AI助手 | ✅ 已实施 (客户详情 4 卡 + 4 个 API) | ❌ | ✅ | `/api/ai/*` 全部 + 客户页 AI 区 |
| 2 | `ai.follow_up` | 跟进建议 | ✅ `/api/ai/follow-up` | ❌ | ✅ | 同上 |
| 3 | `ai.customer_profile` | 客户画像 | ✅ `/api/ai/profile/[id]` | ❌ | ✅ | 同上 |
| 4 | `ai.effect_analysis` | 效果分析 | ✅ `/api/ai/effect-analysis/[id]` | ❌ | ✅ | 同上 |
| 5 | `ai.repurchase` | **跟进推荐** (≈"谁该跟进了" / 复购预测) | ✅ `/api/ai/repurchase-prediction/[id]` (**纯 DB 计算, 零 AI 成本**) | ❓ | ✅ | 决策 **D21** (见下) |
| 6 | `meeting.salon` | **沙龙发起** | ❌ **未实施** (`modules/meeting` 已不在仓库) | ❌ | ✅ | 待建功能, 建好即会员专属 |
| 7 | `crm.interaction` | 互动记录 | ✅ `/api/interactions` | ❌ | ✅ | 互动区 + 弹层 + API |
| 8 | `crm.birthday_reminder` | 生日提醒 | ✅ 字段 + 算法 (客户页提醒条) | ❌ | ✅ | 提醒条/筛选 + 表单提醒开关 (数据仍可填) |
| 9 | `media.upload` | 图片上传 | ✅ `POST /api/photos` (养生记录拍照) | ❌ | ✅ | 上传 API + 拍照入口 |

> **D21 待定**: `ai.repurchase` (复购预测) 零成本、且是"AI 助手"区块的一部分。
> 建议 **归会员** (整块体验一致); 若想当"免费尝鲜钩子", 也可免费 —— 两条都说得通, 需主人拍。

**降级后的存量数据 (决策 D22)**: 建议「**可见、不可新增**」——
例如到期后: 已上传的照片仍能看, 但不能传新图; 已有互动记录仍能看, 不能新增。
理由: 数据主权是产品承诺 (CHARTER §1 + 自托管卖点), 拿数据做要挟=自杀式体验。

### 2.3 推荐码机制 (★ 需律师复核)

**主人要**: 每个用户一个固定 6 位推荐码; 注册时可选填; 填码的新用户得 15 天会员, 提供码的老用户也得 15 天会员。

**产品规则 (建议)**

| 项 | 规则 |
|---|---|
| 码格式 | 6 位, 字符集 `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (去掉 0/O/1/I/L 易混字符, 32^6 ≈ 10.7 亿) |
| 归属 | 每个用户 **1 个固定码**, 注册成功即分配 (不可改) |
| 填写时机 | **注册时可选** (登录页/注册页一个输入框); 注册后不可补填 (防"事后挂单") |
| 奖励对象 | 填码的新用户 + 提供码的老用户, **各 15 天会员权益** |
| 发放时机 | 新用户**完成手机号验证 + 首次创建 1 个客户**后发 (防"空壳注册刷权益") |
| 叠加规则 | **顺延** (追加到当前 `member_until` 之后); 免费用户从"发放当天"起算 15 天 |
| 上限 (建议) | 每个推荐人: 每自然月 ≤ 2 次, 累计 ≤ 24 次 (可配); 被推荐人一生只能被推荐 1 次 |
| 权益性质 | **服务权益 (15 天会员)**, 不可提现、不可转让、不可折现、不可开票 |
| 与被推荐人重复注册 | 同一手机号/同一设备只能被推荐一次; 解绑换绑不重置 |

**五道合规护栏** (为了不触碰《禁止传销条例》的"拉人头/团队计酬"):

1. **只给服务权益, 不给钱** — 无现金、无红包、无提现、无抵扣现金
2. **只有一层** — 不因"下线的下线"再得奖; 无多级推荐
3. **与层级/等级无关** — 推荐多不会升级更高级别或更低价; 与加盟树**零关系** (推荐码不是加盟推荐人)
4. **封顶** — 月度/累计上限, 避免"以发展人员数量计酬"的外观
5. **协议写明** — 用户协议里明确"推荐权益为服务赠送, 不是投资收益, 与加盟资格无关"

> ⚠️ 即使有这五条, 本机制仍是全案最需要**律师复核**的一项 (ADR-0006 §TODO 已挂"对外商用前请律师复核")。
> 复核结论若为"风险偏高", 备选方案: 奖励只给新用户 (单向), 或改成限时活动而非长期机制。

### 2.4 价格与自动续费

| 商品 | 价格 | 结算周期 | 前置能力 |
|---|---|---|---|
| 单月会员 | **¥69** (6900 分) | 一次付清 30 天 | 普通支付 (APP 支付/转账) |
| 连续包月 (自动续费) | **¥49/月** (4900 分) | 每月自动扣, 直到用户取消 | **周期扣款签约** (微信委托扣款 / 支付宝周期扣款) —— 个体户能否过审存疑 (§10.1) |

**若代扣开不通 (现实概率不低)**, 备选 (决策 D8):
- **A. 手动续费优惠**: 到期前 7 天在 App 里"续费享 ¥49" (等价于包月价, 只是要用户点一次) —— 零资质风险, 推荐 ✅
- **B. 预付费包**: ¥499/年 (≈¥41.6/月) —— 一次支付, 现金流更好
- **C. 挂靠企业主体**: 找有资质的企业做收款方 (需税务/合同安排, 先问代账)

---

## 3. 合规红线 (先看这节, 其他都可以谈)

> 依据: [ADR-0006 §2](./adr/0006-franchise-boundary.md) + 《禁止传销条例》(国务院令第 444 号)。
> ⚠️ **工程口径, 不是法律意见**。

| 传销特征 | 加付费后**必须保持** |
|---|---|
| 入门费 (交钱才取得资格) | **加盟资格与付费完全解耦**: 不付费/不续费 = 只是用不上会员功能, 不丢加盟身份/上下级/历史数据。付费买的是**软件使用权** |
| 拉人头 (以发展人员数量计酬) | **禁止一切现金返利/佣金/介绍费**; 推荐奖励只能是"服务权益"且有封顶 (§2.3) |
| 团队计酬 (按下线业绩计酬) | 计费**不读加盟树**: 价格/权益只跟"个人 + 是否会员"有关; 无任何按下线人数×金额的计算 |

**主人已确认的口径 (写入 ADR-0006 修订)**: 「app 会员收费服务与用户业务资金没有任何关系;
加盟体系本身不收费; 软件订阅费与资格/层级解耦」。

**其余红线 (沿用 CHARTER)**:
- ❌ 客户健康/手机号等**绝不出境**, 也不得传给支付渠道 (只传订单号+金额+商品描述)
- ❌ 不引 AGPL 支付库; 不自研密码学 (用官方 SDK / MIT)
- ❌ 支付密钥不入库/不入 git; 日志不打印签名串与实名信息
- ✅ 钱相关写入: append-only 账本 + 审计 + "谁批准的可追溯"
- ✅ 退款/延期/赠送权益 = 人批 + 留痕, 不留后门 API

---

## 4. 域模型 (个人订阅版)

```
 user (已有) ──1:1── membership ──N:1── plan (free / monthly / monthly_auto)
                        │
                        ├──1:N── entitlement_grant (推荐 15 天 / 赠送 / 补偿)
                        │
                        └──1:N── order ──1:N── payment ──1:N── refund
                                     │
                                     └───────────► billing_ledger (append-only 钱账本)

 user ──1:1── referral_code (每人固定 6 位)
 user ──1:N── referral_reward (记录谁推荐了谁 / 发放状态, 防重复)
```

| 实体 | 一句话 | 关键点 |
|---|---|---|
| `plan` | 套餐 (免费/单月/连续包月) | **版本化** (价格改动=新版本, 不覆写历史); 39.9 那类改价不回溯 |
| `membership` | 某用户当前会员状态 | `user_id` 唯一; `member_until` (权益截止) 是所有逻辑的唯一真相 |
| `entitlement_grant` | 权益发放记录 (推荐/赠送/补偿) | 每次 +N 天; 带 `reason` + 发放人 + 幂等键 |
| `referral_code` | 推荐码 | `user_id` 唯一 + `code` 唯一 (6 位) |
| `referral_reward` | 推荐关系与发奖 | (referrer, referee) 唯一; 状态 pending/rewarded/rejected |
| `order` / `payment` / `refund` | 订单/支付/退款 | `out_trade_no` 唯一; 幂等 |
| `webhook_event` | 回调幂等表 | `(channel, event_id)` 唯一 |
| `billing_ledger` | 钱的 append-only 账本 | 触发器拒 UPDATE/DELETE |

**隔离规则 (硬)**:
- 表前缀 `billing_*` / `membership_*`; **无外键指向 `franchisee`/`customer`**
- 唯一交叉: `membership.user_id → user.id` (判权需要)
- 代码边界: `src/lib/billing/**` **不 import** `queries/franchisee*`; 可加 CI grep 守门
- 推荐码与本项目已有"加盟推荐人" (`franchisee.referrer_id`) **是两码事**, 命名/文档不得混用

---

## 5. 生命周期与状态机

### 5.1 会员状态 (按 `member_until` 派生, 不存冗余状态字段)

```
 注册 ──► free (member_until = null 或 < now)
            │
            ├── 付费成功 / 被推荐 / 被赠送 ──► member (member_until > now)
            │                                      │
            │                                      ├── 续费 ──► member_until += 30d
            │                                      ├── 推荐/赠送 ──► member_until += 15d
            │                                      └── 到期 ──► free  (功能降级, 数据保留)
            └── 会员期内 ~> 到期日 T-7 / T-3 / T-1 / 到期当天 提醒续费
```

**硬规则**:
- `member_until` = **权益截止时间**; 判定 `isMember = member_until != null && member_until > now()`
- 到期**不做**"只读封锁": 基础功能继续可用 (客户/养生记录/跟进/图谱), 只关 9 项会员功能
- **永不删用户数据** (含到期一年后)
- 权益来源可叠加: `member_until = max(now, member_until) + N 天` (顺延, 不吞掉已付时间)

### 5.2 订单状态

`created → pending(待支付) → paid` / `closed(30 分钟超时)` / `refunding → refunded`

- `paid` 时**同一事务**: 写 `payment` + `membership.member_until += 30d` + 写 `billing_ledger` + 审计
- 回调与主动查单结果一致 (幂等): `out_trade_no` 唯一 + `webhook_event` 去重

### 5.3 自动续费状态 (S2, 若资质允许)

`none → signed(已签约) → charging(扣款中) → charged | failed(重试≤3) → canceled(用户取消)`

- 用户随时可在 App 内一键取消 (法规要求"便捷取消")
- 每次扣款前 5 日显著提醒 (见 §10.2 法规要求)

---

## 6. 数据模型草案 (Drizzle 风格, 未落地)

```ts
// 约定: 金额一律 integer 分; 时间 timestamptz; 只 append 的表不设 updatedAt

export const plan = pgTable("plan", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  code: text("code").notNull(),                         // free / monthly / monthly_auto / yearly
  version: integer("version").notNull().default(1),     // 价格表不可变 → 改价=新版本
  priceCents: integer("price_cents").notNull(),         // 6900 / 4900
  intervalDays: integer("interval_days").notNull().default(30),
  autoRenew: boolean("auto_renew").notNull().default(false),
  features: jsonb("features").$type<string[]>().notNull().default([]), // 该档包含的 feature key
  effectiveFrom: timestamp("effective_from", { withTimezone: true }).notNull(),
  retiredAt: timestamp("retired_at", { withTimezone: true }),
}, (t) => ({ codeVer: uniqueIndex("idx_plan_code_version").on(t.code, t.version) }));

export const membership = pgTable("membership", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  userId: bigint("user_id", { mode: "bigint" }).notNull().unique(),
  planId: bigint("plan_id", { mode: "bigint" }),         // 当前生效套餐 (free 时可为空)
  memberUntil: timestamp("member_until", { withTimezone: true }), // 权益截止 = 唯一真相
  autoRenewState: text("auto_renew_state", { enum: ["none","signed","charging","failed","canceled"] })
    .notNull().default("none"),
  lastOrderId: bigint("last_order_id", { mode: "bigint" }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`NOW()`),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().default(sql`NOW()`),
}, (t) => ({ untilIdx: index("idx_membership_until").on(t.memberUntil) }));

export const entitlementGrant = pgTable("entitlement_grant", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  userId: bigint("user_id", { mode: "bigint" }).notNull(),
  days: integer("days").notNull(),                      // 15 (推荐) / 30 (补偿) ...
  reason: text("reason", { enum: ["referral_referee","referral_referrer","gift","compensation","manual"] }).notNull(),
  idempotencyKey: text("idempotency_key").notNull().unique(), // 防重复发放 (e.g. referral:12->34)
  grantedByUserId: bigint("granted_by_user_id", { mode: "bigint" }),
  note: text("note"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`NOW()`),
});

export const referralCode = pgTable("referral_code", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  userId: bigint("user_id", { mode: "bigint" }).notNull().unique(),
  code: text("code").notNull().unique(),                // 6 位, 去易混字符
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`NOW()`),
});

export const referralReward = pgTable("referral_reward", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  referrerUserId: bigint("referrer_user_id", { mode: "bigint" }).notNull(),
  refereeUserId: bigint("referee_user_id", { mode: "bigint" }).notNull(),
  status: text("status", { enum: ["pending","rewarded","rejected"] }).notNull().default("pending"),
  rejectReason: text("reject_reason"),
  rewardedAt: timestamp("rewarded_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`NOW()`),
}, (t) => ({ pairUniq: uniqueIndex("idx_referral_pair").on(t.referrerUserId, t.refereeUserId) }));

export const order = pgTable("order", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  outTradeNo: text("out_trade_no").notNull().unique(),
  userId: bigint("user_id", { mode: "bigint" }).notNull(),
  planId: bigint("plan_id", { mode: "bigint" }).notNull(),
  amountCents: integer("amount_cents").notNull(),
  status: text("status", { enum: ["created","pending","paid","closed","refunding","refunded"] }).notNull(),
  channel: text("channel", { enum: ["manual","wechat","alipay"] }).notNull().default("manual"),
  paidAt: timestamp("paid_at", { withTimezone: true }),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`NOW()`),
});

export const payment = pgTable("payment", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  orderId: bigint("order_id", { mode: "bigint" }).notNull(),
  channel: text("channel").notNull(),
  channelTxnId: text("channel_txn_id"),
  amountCents: integer("amount_cents").notNull(),
  rawDigest: text("raw_digest").notNull(),               // 回调 sha256, 不存原文
  paidAt: timestamp("paid_at", { withTimezone: true }).notNull(),
}, (t) => ({ txnUniq: uniqueIndex("idx_payment_channel_txn").on(t.channel, t.channelTxnId) }));

export const webhookEvent = pgTable("webhook_event", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  channel: text("channel").notNull(),
  eventId: text("event_id").notNull(),
  payloadDigest: text("payload_digest").notNull(),
  receivedAt: timestamp("received_at", { withTimezone: true }).notNull().default(sql`NOW()`),
  processedAt: timestamp("processed_at", { withTimezone: true }),
}, (t) => ({ uniq: uniqueIndex("idx_webhook_channel_event").on(t.channel, t.eventId) }));

export const billingLedger = pgTable("billing_ledger", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  userId: bigint("user_id", { mode: "bigint" }).notNull(),
  kind: text("kind", { enum: ["order_paid","refund","chargeback","adjustment"] }).notNull(),
  amountCents: integer("amount_cents").notNull(),        // 收入正 / 退款负; 服务权益(送天数)不进钱账本
  refType: text("ref_type").notNull(),
  refId: text("ref_id").notNull(),
  actorUserId: bigint("actor_user_id", { mode: "bigint" }),
  note: text("note"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`NOW()`),
});
// 附加: 触发器拒 UPDATE/DELETE (append-only)
```

**账本 vs 权益的分工 (重要)**:
- `billing_ledger` = **钱**的账本 (只有真实收付/退款)
- `entitlement_grant` = **送的天数** (推荐/赠送/补偿) —— 不写金额, 避免"权益=现金价值"的联想
- `audit_log` (已有) = 谁改了什么 (通用)

---

## 7. 接口草案 (REST)

| 端点 | 谁用 | 说明 |
|---|---|---|
| `GET /api/me` (已有, 扩展) | APK | 加 `membership: { isMember, memberUntil, planCode, features[], referralCode }` —— 客户端一次拿全 |
| `GET /api/billing/plans` | APK | 可购套餐 (未下架 + 当前生效版本): 6900 / 4900 / (49900 年付) |
| `POST /api/billing/orders` | APK | 下单 `{ planCode }` → `{ outTradeNo, payParams? }` (S0 阶段返回"请联系管理员开通") |
| `GET /api/billing/orders/:outTradeNo` | APK | 轮询支付结果 (**客户端不判断支付成功**, 只轮询服务端) |
| `POST /api/billing/referral/claim` | APK | 新用户填推荐码 `{ code }` → 校验 + 建 pending (完成手机号验证+首个客户后发奖) |
| `GET /api/billing/referral/summary` | APK | 我的码 / 已推荐人数 / 本月剩余名额 / 累计获得天数 |
| `POST /api/billing/webhooks/wechat` \| `/alipay` | 渠道 | 验签 + 幂等 + 入账 (按渠道协议返回, 不返回业务错误) |
| `POST /api/billing/admin/grant` | admin | 手工开通/延期/补偿 (`{ userId, days, reason }`) —— **S0 唯一入口** |
| `POST /api/billing/admin/refund` | admin | 退款 (人批 + 留痕) |
| `GET /api/billing/admin/orders` | admin | 订单检索 + 对账导出 |

**判权工具 (服务端内部)**:

```ts
// src/lib/billing/entitlements.ts (草案)
const m = await requireFeature(tx, userId, "ai.follow_up");  // 不是会员 → throw BillingError(402)
// 客户端只负责"别显示入口"; 服务端是唯一安全边界
```
- 错误码: `402` = 需要会员 (客户端弹"升级/续费"), `403` = RBAC 无权限 (客户端弹"找管理员") —— 两者话术不同
- 每个会员功能 API 入口第一行判权; **免费功能不加判断** (避免误伤基础体验)

---

## 8. 资金、账务与对账

| 项 | 规范 |
|---|---|
| 金额 | `integer` 分; 代码禁用 `float/double` 表达金额; 前端只做展示换算 |
| 币种 | CNY (留 `currency` 列, S0/S1 不用) |
| 幂等 | `out_trade_no` 唯一 + `webhook_event` 去重 + 入账用事务 |
| 对账 | 每日 03:30 拉渠道账单 → 与 `payment` 比对 → 差异表 + 告警 (差 1 分也要看) |
| 查单兜底 | 下单后 30s / 2min / 10min 三次主动查单 (用户付完就退出也能自动到账) |
| 退款 | 原路退回; admin 批; 负 ledger; 服务权益视情况扣回 (默认不扣, 除非恶意) |
| 发票 | S1 手工开票 (抬头/税号**加密存储**) → S2 接电子发票 |
| 试用/赠送 | 0 元不建订单, 只建 `entitlement_grant` (审计可查) |
| 账期口径 | 一律「含首不含尾」, 与养生记录 `service_date` 口径一致 |

---

## 9. 安全、风控与审计

| 面 | 措施 |
|---|---|
| 回调伪造 | 渠道验签 (微信 APIv3 平台证书 / 支付宝 RSA2) + 反查订单金额一致性 |
| 重放 | `webhook_event` 唯一约束 + 时间窗 (±5 min) + 证书序列号校验 |
| 越权 | 只能看/操作自己的 `user_id`; `admin` 才能 grant/refund; 后台切换账号要重新鉴权 |
| 刷单 | 下单限流 (复用 `RateLimits`); 同用户 N 分钟最多 M 单; 大额/异常告警 |
| **推荐码刷奖** | ① 一个被推荐人一生一次 ② 同一手机号/设备/IP 去重 ③ 必须完成手机号验证 + 创建首个客户才发奖 ④ 推荐人月度/累计封顶 ⑤ 异常批量注册 → 奖励 pending 待人工审 |
| 密钥 | 商户私钥/APIv3 key 走 `.env.local`(600) 起步, 上公网后升 systemd `LoadCredential`; **不入库不入 git**; 轮换 SOP 写 `docs/billing.md` |
| 日志 | 回调原文不落盘 (只存 sha256 + 关键字段); 手机号/实名/税号脱敏 |
| 数据最小化 | 传给渠道的只有: 订单号/金额/商品描述("暖客宝会员服务")。**不传**客户姓名/手机号/健康信息 |
| 审计 | `billing_ledger` append-only (触发器拒改) + `audit_log` + 操作人/IP |

---

## 10. 收款渠道与资质 (个体户现实)

### 10.1 个体工商户能收这笔钱吗? (主人问的"经营类别有要求吗")

**结论: 能收, 但类目/资质要匹配, 且自动续费是最大不确定项。** 以下为公开常识级别的工程口径,
**必须**向渠道服务商 + 代账确认 (决策 D1/D8):

| 项 | 要求 (待确认) |
|---|---|
| 主体材料 | 个体工商户营业执照 + 经营者身份证 + 结算账户 (可用**经营者个人银行卡**, 也可对公户) |
| **经营范围** | 建议含: **信息技术服务 / 软件开发 / 软件销售 / 技术服务、技术开发、技术咨询 / 计算机系统服务 / 数据处理服务 / 互联网信息服务**。**类目必须与执照范围一致**, 否则进件驳回或事后风控冻结 |
| 微信支付类目 | 倾向 "IT科技 → 软件服务/互联网服务" (或按服务商建议的类目); 虚拟/在线服务类**通常要补**材料: **ICP 备案** (网站/APP 备案)、**软件著作权**、应用上架截图、服务协议 |
| 支付宝类目 | 倾向 "IT服务 / 软件服务 / 信息服务"; 个体户可进件 |
| 费率 | 软件服务类一般 ~0.6% (以渠道报价为准) |
| **自动续费 (周期扣款)** | 微信「委托扣款」/ 支付宝「周期扣款」**通常要求企业主体 + 行业报备**, 个体户**通过率低** → 必须准备备选 (§2.4 D8) |
| 税务 | 个体户小规模纳税人需**按期申报**; 增值税小规模起征点/免税政策随政策变动 (找代账确认); 可开增值税普通发票, 专票按当地代开规则 |
| 备案 | 微信支付进件常要求"网站/APP/公众号 任一已备案" → 我们的 `nuankebao.tooyang.top` 走 Cloudflare 隧道**不算大陆备案**, 需评估走备案域名 (§deploy/production-plan.md) |

> 💡 **最省事的路径**: 找一家微信/支付宝**服务商**做进件 (他们熟类目话术, 能提前告诉你哪一类会被拒),
> 一次性问清三件事: ①我的执照经营范围够不够 ②要不要软著/备案/上架证明 ③周期扣款我这个主体能不能开。

### 10.2 自动续费的法规要求 (若做)

- 扣款前**显著提醒** (常见要求: 到期前 5 日), App 内 + 短信/服务通知
- 提供**显著、简便的取消入口** (App 内一键取消, 不能"只能找客服")
- 协议里明确: 扣款周期 / 金额 / 何时扣 / 怎么取消
- 依据:《网络交易监督管理办法》《消费者权益保护法实施条例》(自动展期/自动续费条款) —— **具体条文以法务确认为准**

### 10.3 通道对比

| 通道 | 门槛 | 建议 |
|---|---|---|
| **个体户收款码 / 对公转账 + 人工核销** | 无集成 | ✅ **S0 首选** (0 资质等待, 今天就能收) |
| 微信支付 / 支付宝 APP 支付 | 进件 + 类目审核 | ✅ S1 (先跑通单次支付) |
| 周期扣款 (自动续费) | 企业主体要求 | ⏸ S2, 先问清再排期 |
| 云市场代收 | 上架审核 | 备选 |
| 聚合支付 / Stripe | 多一层资金方 / **资金出境 = 红线** | ❌ 不做 |

---

## 11. 分期路线

| 阶段 | 内容 | 工作量 | 前置 |
|---|---|---|---|
| **S0 会员骨架 + 推荐码** (立刻做) | `plan/membership/entitlement_grant/referral_*` + 9 项会员判权 + 免费档默认 + 到期降级 + 推荐码生成/填写/发奖 + 手工开通 (admin grant) + APK 会员状态与到期提醒 | 3~5 天 | 主人拍 D1/D21/D22/D23 |
| **S1 在线支付 (单次)** | `order/payment/webhook_event/billing_ledger` + 微信/支付宝 APP 支付 + 回调幂等 + 主动查单 + 每日对账 + 退款 | 1~2 周 | 个体户进件通过 + 法务文本 |
| **S2 自动续费 + 增值** | 周期扣款签约 (若资质允许; 否则走"手动续费 ¥49") + 电子发票 + AI 用量台账/点数包 + 对账自动化 | 1~2 周 | D8 结论 |
| **S3 多租户/SaaS** | 自助注册/门店版/品牌版 → 与 `phase-3-saas.md` 合流 | 4~6 周 | 主人确认走 SaaS |

> S0 的价值: **不等资质、不动支付渠道**就能开卖 (个体户收款码/对公转账 + 人工开通),
> 同时把"免费/会员判定 + 到期降级 + 推荐发奖"这些真正难的逻辑跑顺。S1 只是把"人工开通"换成"回调入账", 权益层零改动。

---

## 12. 关键决策点 (v0.2, 待主人拍板)

> 每条: **选项 / 影响 / agent 建议 / 最晚何时定**。只答 D1/D21/D22/D23 就能开工 S0。

| # | 决策 | 选项 | 建议 | 最晚 |
|---|---|---|---|---|
| **D1** | 收款主体 | 个体户 / 企业 / 先不收款 | **个体户** (已确认), 但先问服务商类目+代扣可行性 | S1 前 |
| **D2** | 付费对象 | 个人自己充 (已确认) / 门店代付 | **个人** (主人已定); 代码里不建"门店买单"逻辑 | — |
| **D3** | 计价维度 | 个人月费 (已确认) | **个人订阅**, 不设席位数/客户数上限 (**不要**再引入按人头计价) | — |
| **D4** | S0 收款方式 | 个体户收款码 / 对公转账 / 等在线支付 | **收款码 + 人工开通** (今天就能收) | S0 前 |
| **D5** | 支付渠道 | 微信 / 支付宝 / 都上 | **微信 + 支付宝都上** (用户习惯覆盖) | S1 前 |
| **D6** | 定价 | 69 / 49 + 是否加年付 | 主人已定 69/49; 建议**加年付 (¥499)** 提现金流 | S1 前 |
| **D7** | 到期行为 | 降级免费档 (主人已定) / 只读 | **降级免费档** — 基础功能照用, 数据不锁 | — |
| **D8** | 自动续费 | 真代扣 / 手动续费同价 | **先做手动续费 ¥49** (个体户代扣存疑), 能开代扣再上 S2 | S1 前 |
| **D9** | AI 计价 | 含在会员内 (主人已定) / 另卖点数 | **含在会员内**; 但**必须补 `ai_usage` 台账**防止单个用户烧穿成本 (S2) | S2 前 |
| **D10** | 判权实现 | 每请求查表 / 缓存 | **查表** (简单不错); 量上来再加缓存 | S0 前 |
| **D11** | 会员购买页在哪 | APK (生产域) / WEB | **APK**; WEB 域冻结期内不做购买页 | S0 前 |
| **D12** | 账本 | 独立 append-only / 复用 audit_log | **独立 `billing_ledger`** | S1 前 |
| **D13** | 财务/运营后台 | 先 API+SQL / 破例解冻 WEB | **先 API + SQL**; 页面等 WEB 解冻 | S0 前 |
| **D14** | 多租户时机 | 现在不做 / 预留 | **不做多租户**, 但表里留 `tenant_id` 列 (未来 SaaS) | S3 |
| **D15** | 法务 | 律师复核 (推荐码 + 用户协议 + 自动续费条款) | **必做**; 同步修订 ADR-0006 表述 | S1 前 |
| **D16** | 发票与税务 | 手工普票 / 电子发票 | S1 手工普票 (抬头加密存), S2 电子发票 | S1 前 |
| **D17** | 退费政策 | 7 天无理由 / 按比例 / 不退 | **7 天无理由** (月费小额, 降低决策成本) | S1 前 |
| **D18** | 降级后存量数据 | 可见不可新增 (推荐) / 隐藏 | **可见、不可新增** (数据主权承诺) | S0 前 |
| **D19** | 回调兜底 | 主动查单 + 对账 + 人工核销 | **三者都做** | S1 前 |
| **D20** | 上线节奏 | S0 立刻 / 等 SaaS | **S0 立刻** | 现在 |
| **D21** | 复购预测 (零成本 AI 区功能) 归哪档 | 会员 / 免费钩子 | **归会员** (AI 区块体验一致); 想拉新可改成免费 | S0 前 |
| **D22** | 推荐奖励封顶 | 月度 2 / 3 / 不限 | **每自然月 2 次 + 累计 24 次** (合规护栏, 可配) | S0 前 |
| **D23** | 推荐发奖条件 | 注册即发 / 验证+首个客户后发 | **完成手机号验证 + 创建首个客户后发** (防刷) | S0 前 |
| **D24** | 推荐权益是否可转移/折现 | 不可 (推荐) / 可 | **不可提现、不可转让、不可折现** (写进协议) | S0 前 |
| **D25** | 免费档是否有人数/客户数上限 | 无 (推荐) / 有 | **无上限** (免费档的价值是"用得起来") | S0 前 |

---

## 13. 风险登记

| 风险 | 影响 | 缓解 |
|---|---|---|
| **推荐码被解读为"拉人头"** | 高 (法律) | §2.3 五道护栏 + 封顶 + 律师复核 + 协议写明"服务权益"; 备选: 改单向/限时活动 |
| **个体户类目/代扣被拒** | 中 (拖延 S1/S2) | 先跑 S0 人工收款; 提前问服务商; 备选"手动续费同价" |
| 自动续费法规违规 (未显著提醒/取消难) | 中 (投诉/处罚) | 到期前 5 日提醒 + 一键取消 + 法务确认条文 |
| 资质/备案卡住 (大陆备案) | 中 | 评估备案域名; S0 不依赖 |
| 回调丢失/隧道不稳 | 中 | 主动查单 + 每日对账 + 人工核销通道 |
| 单个用户烧穿 AI 成本 | 中 | `ai_usage` 台账 + 每用户日/月软上限 + 异常告警 (D9) |
| 到期用户以为"数据没了" | 中 (口碑) | 文案明确"数据都在, 续费即恢复"; 导出永远可用 |
| 密钥泄露 | 高 | 不入库/不入 git + 轮换 SOP + 最小权限 |
| 权益判定被客户端绕过 | 中 | 服务端判权 (APK 只做提示) |
| 价格表被覆写致历史对不上 | 中 | plan 版本化 + ledger 快照 |

---

## 14. 开工前置清单

- [ ] 主人拍板 **D1 / D21 / D22 / D23** (S0 可开工), 其余分阶段
- [ ] **服务商三问** (S1 前): ①执照经营范围够不够 ②要不要软著/备案/上架证明 ③周期扣款能否开通
- [ ] 法务: 《用户服务协议》《会员服务协议(含自动续费条款)》《退款政策》 (D15/D17)
- [ ] **ADR-0006 修订**: 写入主人确认的表述"加盟体系本身不收费; 软件订阅费与资格/层级解耦"
      + 补"推荐权益为服务赠送"条款 + 律师复核项
- [ ] 代账确认: 税务/发票/费率
- [ ] 回调联调环境 (S1): 公网 HTTPS 可达性实测 + 平台证书下载
- [ ] 数据模型评审 → 落 `docs/billing.md` + ADR-0012

---

## 15. 附录

### 15.1 术语

| 词 | 含义 |
|---|---|
| 免费档 free | 默认档; 除 9 项会员功能外全部可用 |
| 会员档 member | 付费或持权益; 全功能 |
| `member_until` | 权益截止时间 (会员判定的唯一真相) |
| 权益发放 grant | 送天数 (推荐/赠送/补偿), 不涉及钱 |
| 账本 ledger | 钱的 append-only 流水 (唯一真相) |
| 周期扣款 | 渠道侧自动续费签约能力 (S2, 资质存疑) |

### 15.2 明确不做 (v0.2)

- ❌ 现金返利 / 佣金 / 介绍费 / 红包 —— 传销红线 (推荐只送服务权益)
- ❌ 二级及以上推荐奖励; 按下线人数定价/升级
- ❌ 把会员等级写进加盟树 / 图谱 (两张图永不相交)
- ❌ 到期锁死基础功能 / 删除用户数据
- ❌ 自研支付/签名/对账格式; 引 AGPL 支付库
- ❌ 把客户健康数据/手机号传给支付渠道
- ❌ 账本 UPDATE/DELETE (append-only)

### 15.3 本版与 v0.1 的差异 (便于 review)

| 项 | v0.1 (2026-09-18) | v0.2 (2026-09-19) |
|---|---|---|
| 付费对象 | 租户 (门店/品牌) | **个人** (每人自己充值) |
| 计价 | 席位 + 客户数 + AI 量 | **个人月费** (69 / 49) |
| 档位 | 试用/基础/专业/品牌 | **免费档 / 会员档** (9 项受限) |
| 到期行为 | 只读停用 (suspended) | **降级免费档**, 基础功能照用 |
| 推荐 | 无 | **6 位固定推荐码 + 双向 15 天** (§2.3) |
| 收款 | 对公转账 → 微信/支付宝 | **个体工商户** + 类目/代扣可行性 (§10.1) |
| 新增决策 | D1-D20 | +D21~D25 (复购预测归属/推荐封顶/发奖条件/不可折现/免费档无上限) |
