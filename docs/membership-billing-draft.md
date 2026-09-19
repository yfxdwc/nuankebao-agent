# 会员付费系统 — 工业级草案 (v0.1)

> **状态**: 🟡 **草案 (DRAFT) — 待主人拍板**. 本文只提方案与决策点, **不含任何已实施代码**。
> 拍板后: 决策沉淀成 `docs/adr/0012-membership-billing.md` (下一个 ADR 编号), 实施细节拆到 `docs/billing.md`。
>
> **阅读顺序**: 本文件 → [ADR-0006 加盟体系 + 合规边界](./adr/0006-franchise-boundary.md)(红线) →
> [phase-3-saas §3.5 计费层](./phase-3-saas.md)(2026-09 旧草案, 早于 APK 域) → [安全合规](./security-compliance.md)
>
> **作者**: agent (2026-09-18) — 依据 `CHARTER §1/§3/§4` + `ADR-0006/0008` + 当前 `schema.ts` 代码事实反推

---

## 0. TL;DR (一页看懂)

1. **先做「不算钱」的会员**: 套餐 + 权益 + 到期只读 + 人工开通 —— 0 支付集成, 2~3 天可上线, 立刻能对外收第一笔(对公转账)且无合规/技术风险 (**S0**)。
2. **再上在线支付**: 微信支付 / 支付宝 APP 支付 + 回调幂等 + 每日对账 (**S1**, 1~2 周, 卡在资质而非代码)。
3. **钱与加盟必须物理隔离**: `billing_*` 表独立 schema 前缀, 不跟 `franchisee`/`customer` 有任何外键或金额字段流转 ——
   否则触碰《禁止传销条例》红线 (ADR-0006 §2)。
4. **付费主体基本不是销售员本人**, 而是门店/品牌 (老板) —— 计价按「租户 + 席位 + AI 用量」, 不按人头拉下线。
5. **判权一律服务端**: 客户端 (APK 可反编译) 只做友好提示; 权益/配额判定走 `requireEntitlement()`。
6. **金额一律整数「分」**, append-only 账本 + 每日对账, 绝不出现 `float`/`double`。

---

## 1. 现状与前提 (代码事实, 2026-09-18)

| 事实 | 出处 | 对付费系统的影响 |
|---|---|---|
| 无任何计费/支付代码, 无 `tenant`/`plan`/`order` 表 | `grep` 全仓 | 全新域, 无历史包袱, 但也没有多租户地基 |
| 组织关系 = `franchisee` 树 + `store` 门店 + `user.role` (admin/manager/sales) | `src/lib/db/schema.ts` | 计费对象要么挂 `store` (门店), 要么挂未来 `tenant`; **不挂 franchisee 节点** |
| `franchisee`/`customer` **无任何金额字段**(红线) | ADR-0006 §2 | 计费域必须独立表空间, 不得回写加盟树 |
| AI 有真实边际成本 (MiniMax), 但**没有用量台账** | `src/lib/ai/client.ts` 只有 `usage` 返回, 无落库 | 若按 AI 量计费, 先补 `ai_usage` 台账 (S2) |
| 限流已有 (登录/上传/AI 10 次每分钟) | `src/lib/rate-limit.ts` | 配额限流可复用同一套内存计数器, 但要换持久化 (多实例) |
| 部署 = 自有服务器 + Cloudflare Tunnel (`nuankebao.tooyang.top`) | `docs/deploy/production-plan.md` | 能收 HTTPS 回调; 但**大陆区 ICP 备案 + 支付类目资质是硬门槛** |
| 审计 = 5 张表 PG 触发器 + `audit_log` | `drizzle/audit_trigger.sql` | 钱相关的写必须比这更严 → 独立 append-only 账本 (D12) |
| 双域: APK = 生产域 (销售员), WEB = 开发脚手架 | ADR-0008 | 支付 UI 必须先做 APK; 运营/财务后台属"纯管理功能", 在 WEB 冻结期内需主人破例 (D11) |
| Phase 3 SaaS 已规划多租户 + 计费 (¥99/¥299 草稿) | `docs/phase-3-saas.md §3.5` | 本草案 = 那条路线的**前传**: 先把单租户付费跑通, 再谈多租户 |

---

## 2. 合规红线 (先看这节, 其他都可以谈)

> 依据: [ADR-0006 §2](./adr/0006-franchise-boundary.md) + 《禁止传销条例》(国务院令第 444 号)
> ⚠️ 以下是**工程合规口径, 不是法律意见**。对外正式商用前必须请律师复核 (ADR-0006 §TODO 已挂 P2)。

《禁止传销条例》识别传销的三特征: **入门费** + **拉人头** + **团队计酬**。本系统加了付费之后, 必须逐条保持"不构成":

| 特征 | 现在的防线 (ADR-0006) | 加付费后**必须保持** |
|---|---|---|
| 入门费 (交钱/买货才取得资格) | 系统不收任何费用 | **加盟资格与付费完全解耦**: 不续费只是"用不了软件", 不丢加盟身份/上下级/历史数据; 付费买的是**软件使用权**, 不是加盟资格 |
| 拉人头 (以发展人员数量计酬) | 无任何返利字段 | **禁止一切"推荐返现/介绍奖/发展下线打折"**。若将来真要做推荐优惠, 只能是一次性、与软件订单绑定的"抵扣券", 且需律师复核 (默认不做) |
| 团队计酬 (按下线业绩计酬) | `franchisee` 无金额列 | 计费域**不得**读取加盟树计算价格/折扣/返点; 价格只跟"租户 + 席位 + 用量"有关 |

**其余红线 (沿用 CHARTER)**:

- ❌ 客户健康/手机号等**绝不出境**, 也不得传给支付渠道 (只传订单号+金额+主体名称)
- ❌ 不引 AGPL 支付库; 不自研密码学 (用官方 SDK / MIT)
- ❌ 不把支付密钥入库/入 git; 不在日志里打印签名串与用户实名信息
- ✅ 所有钱相关的写: 走审计 + append-only 账本, 可追溯到"谁批准的"
- ✅ 退款/延期/赠送额度 = **人批 + 留痕**, 不留后门 API

---

## 3. 收费对象与计价维度 (产品侧)

### 3.1 谁付钱 (决策 D1/D2)

```
品牌方(总部) ── 多门店 ── 每店 N 个销售员 ── 每人 M 个客户
     ▲              ▲              ▲                  ▲
     └──────────────┴──────────────┴──────────────────┘
       付费主体通常在这里 (老板/店长), 不是销售员本人
```

- **主假设**: 付费人 = 门店老板 / 品牌总部; 使用者 = 销售员。销售员自己掏钱的场景 (个体加盟商) 存在但应作为"个人版"后置。
- **计价对象**: 租户 (品牌或单店) —— 现在没有 `tenant` 表 → S0 先做"单租户 + 伪 tenant_id=1", 表结构预留 `tenant_id` (D14)。

### 3.2 计什么价 (决策 D3/D9)

| 维度 | 是否计价 | 理由 | 备注 |
|---|---|---|---|
| **席位** (可用账号数) | ✅ 主维度 | 客户价值随人数增长; 易解释、易审计 | 超席位要拦住新增账号 (服务端) |
| **客户数上限** | ✅ 次维度 | 数据量=价值量; 也防止"一店开号全公司用" | 到期后**不删数据**, 只置只读 |
| **AI 用量** (话术/画像/效果分析) | ✅ 独立包 | MiniMax 有真实边际成本 (每次几厘~几分) | 需先补 `ai_usage` 台账; 复购预测是纯 DB 计算 → **不计费** |
| 照片/存储 | ⏳ 后置 | 有成本但不敏感 | S2 之后 |
| 门店数 (多店) | ⏳ 后置 | 品牌客户定制 | 与多租户一起 |
| 功能档 (报表/导入/审计) | ✅ 档位差 | 已在 WEB 域存在 | 见 §3.3 |

### 3.3 档位草案 (沿用并修正 phase-3-saas §3.5)

| 档 | 价格 (锚点, 待定) | 席位 | 客户上限 | AI 额度 | 功能 |
|---|---|---|---|---|---|
| 试用 Trial | ¥0 / 14 天 | 3 | 50 | 20 次 | 全功能, 到期只读 |
| 基础 Basic | ¥99/月 (¥999/年) | 5 | 500 | 100 次/月 | 客户 + 养生记录 + 跟进 + 图谱 |
| 专业 Pro | ¥299/月 (¥2999/年) | 20 | 5000 | 500 次/月 | + AI 全套 + 报表 + 导入 |
| 品牌 Brand | 定制 | 按店 | 不限 | 定制 | + 多店汇总 + 审计导出 + SLA |

> ⚠️ 价格只是**锚点**, 正式定价必须等"成本核算 + 3-5 个真实客户访谈" (D6)。

---

## 4. 域模型 (实体 + 关系)

```
 tenant ──1:N── subscription ──N:1── plan ──1:N── plan_feature
    │                │                                  ▲
    │                └──1:N── entitlement_override ──────┘  (手工加/减权益)
    │                │
    │                └──1:N── order ──1:N── payment
    │                              │
    │                              └──1:N── refund
    │                └──1:N── usage_counter (席位/客户/AI)
    └──1:N── seat (billing 视角的"已付费账号")  ← 映射 user.id
```

| 实体 | 一句话 | 关键字段 |
|---|---|---|
| `tenant` | 付费单位 (品牌/单店) | id, name, kind(brand/store), owner_user_id |
| `plan` | 套餐 (价格表**按生效时间**追加, 不覆写) | code, price_cents, interval, seats, customer_limit, ai_quota, features(jsonb) |
| `subscription` | 租户当前订阅 (状态机见 §5) | tenant_id, plan_id, status, period_start/end, trial_end, seats |
| `entitlement_override` | 手工加/减的权益 (赠送/补偿) | subscription_id, key, value, reason, granted_by, expires_at |
| `order` | 一次购买意图 | out_trade_no(唯一), amount_cents, status, plan_id, seats, paid_at |
| `payment` | 渠道支付流水 (一个订单可能多次尝试) | order_id, channel, channel_txn_id, amount_cents, raw_digest, paid_at |
| `refund` | 退款 | payment_id, amount_cents, reason, approved_by, status |
| `webhook_event` | 回调幂等表 (**先插后处理**) | channel, event_id, payload_digest, processed_at |
| `usage_counter` | 用量计数 (按期) | tenant_id, key(customers/seats/ai), period, used |
| `billing_ledger` | **append-only 账本** (钱的唯一真相) | ts, tenant_id, kind, amount_cents, ref, actor, snapshot_digest |

**隔离规则 (硬)**:
- 表名前缀 `billing_` / 无外键指向 `franchisee`、`customer`
- 唯一允许的交叉引用是 `seat.user_id → user.id` (为了判权) 与 `tenant` ↔ `store` (为了归属)
- 代码目录: `src/lib/billing/**` + `src/app/api/billing/**`, 不 import `queries/franchisee*` (CI 可加 grep 守门)

---

## 5. 生命周期与状态机

### 5.1 订阅状态

```
  注册/开通
     │
     ▼
  trialing ──到期──► expired ──续费──► active
     │  │                              ▲ │
     │  └──付费成功────────────► active ┘ │
     │                                   │ 到期未付
     └──(S0 手工开通)──────────► active   ▼
                                    past_due ──宽限期(7天, 全功能)──► suspended (只读)
                                       │                                   │
                                       └──付费成功──────────────────────────┘
                                                                           │
                                                       90 天仍不续 ──► expired (数据保留, 不删)
```

**硬规则**:
- `suspended` = **只读**: 能看/能导出/能续费, **不能新增客户/记录/账号**, AI 关闭
- **永不删客户数据** (这是产品承诺, 也是"数据自托管"卖点) —— 过期只降能力
- 降级 (Pro→Basic) 时: 存量客户**不删**, 只是不能再新增 (超额只读)

### 5.2 订单状态

`created → pending(已下单待支付) → paid → (refunding → refunded)` / `closed(超时未付, 30 分钟)`

- `paid` 时: **同一事务内** 写 `payment` + 延长 `subscription.period_end` + 写 `billing_ledger` + 审计
- 回调与主动查单**结果一致** (幂等): `out_trade_no` 唯一约束 + `webhook_event` 去重

---

## 6. 数据模型草案 (Drizzle 风格, 未落地)

```ts
// src/lib/db/schema.ts (草案, 未提交)
// 约定: 金额一律 integer 分 (CNY); 时间 timestamptz; 只 append 的表不设 updatedAt

export const tenant = pgTable("tenant", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  name: text("name").notNull(),
  kind: text("kind", { enum: ["brand", "store", "personal"] }).notNull().default("store"),
  ownerUserId: bigint("owner_user_id", { mode: "bigint" }),   // 付费决策人
  contactPhoneEncrypted: text("contact_phone_encrypted"),     // 加密 (pgcrypto)
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`NOW()`),
});

export const plan = pgTable("plan", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  code: text("code").notNull(),               // trial/basic/pro/brand
  version: integer("version").notNull().default(1), // 价格表不可变 → 新版新行
  priceCents: integer("price_cents").notNull(),     // 整数分
  interval: text("interval", { enum: ["month", "year"] }).notNull(),
  seats: integer("seats").notNull(),
  customerLimit: integer("customer_limit").notNull(),
  aiQuota: integer("ai_quota").notNull().default(0),
  features: jsonb("features").$type<string[]>().notNull().default([]),
  effectiveFrom: timestamp("effective_from", { withTimezone: true }).notNull(),
  retiredAt: timestamp("retired_at", { withTimezone: true }),   // 下架≠删除 (老订阅继续跑)
}, (t) => ({ codeVer: uniqueIndex("idx_plan_code_version").on(t.code, t.version) }));

export const subscription = pgTable("subscription", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  tenantId: bigint("tenant_id", { mode: "bigint" }).notNull(),
  planId: bigint("plan_id", { mode: "bigint" }).notNull(),
  status: text("status", { enum: ["trialing","active","past_due","suspended","expired","canceled"] }).notNull(),
  periodStart: timestamp("period_start", { withTimezone: true }).notNull(),
  periodEnd: timestamp("period_end", { withTimezone: true }).notNull(),
  graceUntil: timestamp("grace_until", { withTimezone: true }),  // past_due 宽限
  seats: integer("seats").notNull().default(1),
  autoRenew: boolean("auto_renew").notNull().default(false),
  createdAt/updatedAt: ...,
}, (t) => ({ activeIdx: index("idx_subscription_tenant_status").on(t.tenantId, t.status) }));

export const order = pgTable("order", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  outTradeNo: text("out_trade_no").notNull().unique(),  // 与渠道对账的主键
  tenantId: bigint("tenant_id", { mode: "bigint" }).notNull(),
  planId: bigint("plan_id", { mode: "bigint" }).notNull(),
  seats: integer("seats").notNull().default(1),
  amountCents: integer("amount_cents").notNull(),
  status: text("status", { enum: ["created","pending","paid","closed","refunding","refunded"] }).notNull(),
  channel: text("channel", { enum: ["manual","wechat","alipay"] }).notNull().default("manual"),
  createdBy: bigint("created_by", { mode: "bigint" }).notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  paidAt: timestamp("paid_at", { withTimezone: true }),
});

export const webhookEvent = pgTable("webhook_event", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  channel: text("channel").notNull(),
  eventId: text("event_id").notNull(),           // 渠道事件 id / 交易号
  payloadDigest: text("payload_digest").notNull(), // sha256 (不存原文, 防泄露)
  receivedAt: timestamp("received_at", { withTimezone: true }).notNull().default(sql`NOW()`),
  processedAt: timestamp("processed_at", { withTimezone: true }),
}, (t) => ({ uniq: uniqueIndex("idx_webhook_channel_event").on(t.channel, t.eventId) }));

export const billingLedger = pgTable("billing_ledger", {
  id: bigserial("id", { mode: "bigint" }).primaryKey(),
  tenantId: bigint("tenant_id", { mode: "bigint" }).notNull(),
  kind: text("kind", { enum: ["order_paid","refund","grant","adjust","chargeback"] }).notNull(),
  amountCents: integer("amount_cents").notNull(),   // 收入为正, 退款为负
  refType: text("ref_type").notNull(), refId: text("ref_id").notNull(),
  actorUserId: bigint("actor_user_id", { mode: "bigint" }),   // 手工操作时=人
  note: text("note"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`NOW()`),
}, (t) => ({ /* 只插入, 无 UPDATE/DELETE 触发器守门 */ }));
```

**审计与账本的分工**:
- `audit_log` (已有): "谁改了什么" (通用)
- `billing_ledger` (新): "钱怎么变的" (账本, **禁止 UPDATE/DELETE**, 用触发器拒掉)
- 两者都写: 一次付费成功 = ledger 1 行 + audit_log 若干行

---

## 7. 接口草案 (REST, APK 消费)

| 端点 | 谁用 | 说明 |
|---|---|---|
| `GET /api/billing/me` | APK | 我的租户: 套餐 / 状态 / 到期日 / 席位余额 / 客户用量 / AI 余额 (一次拉完, 同 `/api/me` 风格) |
| `GET /api/billing/plans` | APK | 可购套餐 (只返回未下架 + 当前生效版本) |
| `POST /api/billing/orders` | APK | 下单 `{ planCode, seats }` → 返回 `outTradeNo` + 渠道支付参数 (无支付集成的 S0 阶段返回"请联系管理员开通") |
| `GET /api/billing/orders/:outTradeNo` | APK | 轮询支付结果 (客户端不做"支付成功"的判断, 只轮询服务端) |
| `POST /api/billing/webhooks/wechat` \| `/alipay` | 渠道 | 验签 + 幂等 + 入账 (**不返回业务错误**, 按渠道协议返回成功/失败) |
| `POST /api/billing/refunds` | admin | 申请/审批退款 (人批 + 留痕) |
| `POST /api/billing/admin/grant` | admin | 手工开通/延期/赠额度 (`{ tenantId, days, planCode, reason }`) — **S0 的唯一入口** |
| `GET /api/billing/admin/orders` | admin | 订单检索 + 导出 (对账用) |

**判权工具 (服务端内部, 不用 HTTP)**:

```ts
// src/lib/billing/entitlements.ts (草案)
const ent = await requireEntitlement(tx, tenantId, "ai.profile");   // 不满足 → throw BillingError
await assertQuota(tx, tenantId, "customers", +1);                   // 超限 → 402 Payment Required
```
- 错误码: `402` (配额/到期) + `403` (RBAC) 分开, 客户端话术不同
- APK 侧统一拦截 `402` → 弹"续费/升级"引导页, **但页面永远以服务端最新状态为准**

---

## 8. 资金、账务与对账 (工业级要求)

| 项 | 规范 |
|---|---|
| 金额 | `integer` 分; 代码里禁用 `float/double` 表达金额; 前端只做展示换算 |
| 币种 | CNY (单币种; 多币种留 `currency` 列, 不进 S0/S1) |
| 幂等 | `out_trade_no` 唯一 + `webhook_event` 去重 + "入账" 用事务 |
| 对账 | 每日 03:30 拉渠道账单 (微信/支付宝对账单 API) → 与本地 `payment` 比对 → 差异写 `reconciliation_report` + 告警 |
| 查单兜底 | 回调丢失时: 下单后 30s/2min/10min 三次主动查单 (客户离开支付页也能自动入账) |
| 退款 | 原路退回; 需 admin 批; 部分退款记负 ledger |
| 发票 | S1 手工开票 (记录抬头/税号**加密**) → S2 接电子发票 |
| 试用 | 0 元也建 order (audit 有据可查) |
| 账期口径 | 一律「含首不含尾」区间, 全仓统一, 与养生记录 `service_date` 口径一致 |

---

## 9. 安全、风控与审计

| 面 | 措施 |
|---|---|
| 回调伪造 | 渠道签名验证 (微信 APIv3 平台证书 / 支付宝 RSA2) + 金额与订单号反查一致性校验 |
| 重放 | `webhook_event` 唯一约束 + 时间窗 (±5 min) + 平台证书序列号校验 |
| 越权 | 只能查自己 `tenant_id` 的单; `admin` 才能 grant/refund; 租户切换要重新鉴权 |
| 刷单 | 下单限流 (复用 `RateLimits`), 同一租户 N 分钟内最多 M 单; 异常大额告警 |
| 试用滥用 | 试用以 `tenant` 为单位一次, 记录手机号 hash 防重复注册 (不存明文) |
| 密钥 | 商户私钥/APIv3 key 走 systemd `LoadCredential` 或 `.env.local` (chmod 600), **不入库不入 git**; 轮换 SOP 写在 `docs/billing.md` |
| 日志 | 回调原文**不落盘** (只存 sha256 + 关键字段); 手机号/实名/税号脱敏 |
| 数据最小化 | 传给渠道的只有: 订单号/金额/商品描述("暖客宝会员服务")。**不传**客户姓名、手机号、健康信息 |
| 审计 | `billing_ledger` append-only (触发器拒 UPDATE/DELETE) + `audit_log` + 操作人/IP |

---

## 10. 支付渠道 (国内现实)

| 通道 | 门槛 | 优点 | 缺点 | 建议 |
|---|---|---|---|---|
| **对公转账 + 人工核销** | 无 (有对公账户即可) | 0 集成、0 资质、立刻能收 | 手工、慢 | ✅ **S0 首选** |
| 微信支付 (APP 支付) | 营业执照 + 法人 + 对公账户 + **备案 APP/域名** + 类目资质 | 用户习惯最好 | 审核周期长, 类目可能被拒 | ✅ S1 |
| 支付宝 (APP 支付) | 同上 (企业支付宝) | 审核相对快 | 需企业主体 | ✅ S1 并行 |
| 云市场代收 (云厂商) | 上架审核 | 免直连资质 | 抽成 + 上架限制 | 备选 |
| 聚合支付 (Ping++ 等) | 依赖第三方 | 一次接多渠道 | 多一层资金方 + 数据出境风险 | ❌ 除非合规评估通过 |
| Stripe | 境外主体 | 开发体验最好 | **数据/资金出境 = 红线** | ❌ 不做 |

**关键技术风险 (S1 前要实测)**:
- Cloudflare Tunnel 收支付回调: POST + 大 body + 平台证书下载 → 需真机联调 (回调域名建议直连 IP + 证书, 或单独子域走隧道)
- 回调 **必须公网可达且稳定**; 家宽/断电场景要有"主动查单 + 对账"兜底 (已写进 §8)

---

## 11. 分期路线 (建议)

| 阶段 | 内容 | 工作量 | 前置 |
|---|---|---|---|
| **S0 会员骨架** (推荐立刻做) | `tenant/plan/subscription/entitlement` + 判权工具 + 到期只读 + 手工开通 API + APK 里显示会员状态/到期提醒 + 到期不删数据 | 2~3 天 | 主人拍板 D1/D2/D3/D7 |
| **S1 在线支付** | `order/payment/webhook_event/billing_ledger` + 微信/支付宝 APP 支付 + 回调幂等 + 主动查单 + 每日对账 + 退款 | 1~2 周 | 商户号 + 资质 + 法务文本 (用户协议/退款政策) |
| **S2 用量与增值** | `ai_usage` 台账 + AI 点数包 + 电子发票 + 优惠券 + 用量报表 | 1~2 周 | S1 稳定运行 1 个月 |
| **S3 多租户 SaaS** | 自助注册/试用/多店品牌版 + 子域名 + 持久化限流 → 与 `phase-3-saas.md` 合流 | 4~6 周 | 主人确认走 SaaS (phase-3-saas §6) |

> S0 的价值: **不等资质、不动支付渠道**就能开始收费 (对公转账), 同时把"权益/到期/只读"这些真正难的产品逻辑先跑顺。
> 将来接支付只是把"人工开通"替换成"回调入账", 权益层零改动。

---

## 12. 关键决策点 (待主人拍板)

> 每条: **选项 / 影响 / agent 建议 / 最晚何时定**。可只答 D1/D2/D3/D7 就能开工 S0。

| # | 决策 | 选项 | agent 建议 | 最晚 |
|---|---|---|---|---|
| **D1** | 收款主体 | (a) 对公账户 (b) 个体户 (c) 先不收款只发码 | (a) 对公, 好开票好合规 | S1 前 |
| **D2** | 付费对象 | (a) 门店 (b) 品牌多店 (c) 销售员个人 | (a) 门店为主, 品牌后置; **不做个人** | S0 前 |
| **D3** | 计价维度 | (a) 席位+客户数 (b) 只席位 (c) 功能档 | (a) 席位为主 + 客户数上限 | S0 前 |
| **D4** | S0 收款方式 | (a) 对公转账+人工开通 (b) 等在线支付再上 | (a) 立刻可商用 | S0 前 |
| **D5** | 支付渠道 | 微信/支付宝/云市场 | 微信+支付宝 (APP 支付) | S1 前 |
| **D6** | 定价 | 沿用 ¥99/¥299 还是重设 | 先访谈 3-5 个客户再定, 代码里做成 `plan` 表 (可改) | S1 前 |
| **D7** | 试用/宽限/到期行为 | 天数 + 只读 or 停用 | 试用 14 天 / 宽限 7 天 / 到期**只读不删** | S0 前 |
| **D8** | 自动续费 (代扣) | 做 / 不做 | **S1 不做** (签约代扣要额外资质+授权文本) | S2 |
| **D9** | AI 怎么计价 | (a) 按次 (b) 按 token (c) 包月不限 | (a) 按次, 成本透明好解释 | S2 前 |
| **D10** | 判权实现 | (a) 服务端每请求查表 (b) 内存缓存 + 失效 | (a) 先用查表 (简单不错), 量上来再加缓存 | S0 前 |
| **D11** | 运营/财务后台 | (a) 先 API + SQL 手工 (b) 破例解冻 WEB 域做页面 | (a) 先 API, 等 WEB 解冻再做页面 | S0 前 |
| **D12** | 账本 | (a) 独立 append-only `billing_ledger` (b) 复用 `audit_log` | (a) 钱必须独立账本 | S1 前 |
| **D13** | 密钥存放 | (a) `.env.local` 600 (b) systemd LoadCredential (c) 加密入库 | (a) 起步, (b) 上公网时升级 | S1 前 |
| **D14** | 多租户时机 | (a) 现在单租户+伪 tenant (b) 等 Phase 3 | (a) 表结构预留, 逻辑单租户 | S0 前 |
| **D15** | 合规/法务 | 是否请律师复核 + 改 ADR-0006 | **必做**: 更新 ADR-0006 (付费≠入门费 的表述) + 律师复核用户协议 | S1 前 |
| **D16** | 发票与税务 | 谁开票/税率/是否要 EDI 资质 | 对公账户 + 增值税普通发票起步, 咨询代账 | S1 前 |
| **D17** | 退费政策 | 7 天无理由 / 按比例 / 不退 | 7 天无理由 (降低决策成本, 与 phase-3-saas 一致) | S1 前 |
| **D18** | 数据与订阅解耦 | 过期后保留多久 | **永久保留** (只读), 体现"自托管数据主权" | S0 前 |
| **D19** | 回调不可用兜底 | 主动查单 / 对账 / 人工核销 | 三者都做 (§8) | S1 前 |
| **D20** | 上线节奏 | S0 立刻 / 等 SaaS | **S0 立刻** (2~3 天, 不阻塞现有 APK 迭代) | 现在 |

---

## 13. 风险登记

| 风险 | 影响 | 缓解 |
|---|---|---|
| **合规误判** (付费被解读为加盟收费) | 高 (法律) | 域隔离 + ADR-0006 更新 + 律师复核 + 用户协议写明"软件订阅费" |
| 资质/商户号卡住 | 中 (拖延) | S0 走对公转账, 不阻塞 |
| 回调丢失 / 隧道不稳 | 中 (用户付款没到账) | 主动查单 + 每日对账 + 人工核销通道 |
| 到期只读被用户当"数据没了" | 中 (口碑) | 文案明确"数据都在, 续费即恢复"; 导出功能永远可用 |
| 密钥泄露 | 高 | 不入库/不入 git + 轮换 SOP + 最小权限 |
| 试用被刷 | 低 | 租户级一次性 + 手机号 hash 去重 |
| 权益判定被客户端绕过 | 中 | 服务端判权 (APK 只做提示) |
| 价格表被覆写导致历史对不上 | 中 | plan 版本化 (只追加) + ledger 快照 |

---

## 14. 开工前置清单

- [ ] 主人拍板 **D1/D2/D3/D7** (S0 可开工), 之后 D4~D20 分阶段
- [ ] 收款主体: 营业执照 + 对公账户 (D1)
- [ ] 法务文本: 《用户服务协议》《会员服务与退款政策》 (D15/D17)
- [ ] ADR-0006 修订: "系统不收任何费用" → "加盟体系本身不收费; 软件订阅费与加盟资格/层级完全解耦"
- [ ] 支付资质 (S1): 微信商户号 / 企业支付宝 / APP 备案 / 类目资质
- [ ] 回调联调环境 (S1): 公网 HTTPS 可达性实测 + 平台证书下载
- [ ] 数据模型评审 → 落 `docs/billing.md` + ADR-0012

---

## 15. 附录

### 15.1 术语

| 词 | 含义 |
|---|---|
| 租户 tenant | 付费单位 (品牌/店) |
| 套餐 plan | 价格 + 配额 + 功能集 (版本化, 不可覆写) |
| 订阅 subscription | 租户当前处于哪个套餐、什么时候到期 |
| 权益 entitlement | 由 plan + override 派生出的"能不能用 X" |
| 配额 quota | 能用多少 (席位/客户/AI 次) |
| 宽限期 grace | 到期后仍全功能的天数 (挽留期) |
| 账本 ledger | 钱的 append-only 流水 (唯一真相) |

### 15.2 明确不做 (v0.1)

- ❌ 返利 / 佣金 / 推荐奖 / 按下线人数打折 —— 传销红线
- ❌ 把会员等级写进加盟树 / 图谱 (两张图永不相交)
- ❌ 自动续费代扣 (S1 阶段)
- ❌ 自研支付、自研签名、自研对账格式
- ❌ 把客户健康数据/手机号传给任何支付渠道
- ❌ 到期删数据 (哪怕用户欠费一年)

### 15.3 相关文档

- [ADR-0006 加盟体系 + 合规边界](./adr/0006-franchise-boundary.md) — 红线来源
- [phase-3-saas §3.5](./phase-3-saas.md) — 旧计费草案 (多租户视角)
- [security-compliance.md](./security-compliance.md) — 数据安全基线
- [deploy/production-plan.md](./deploy/production-plan.md) — 备案/部署现实约束
- [profile-and-settings.md](./profile-and-settings.md) — 「我的」页 (会员状态将来展示在这里)
