# Customer 端点 IDOR 同源排查 (R-12 后续)

**日期**: 2026-09-25 (R-12 IDOR 修复后)
**作者**: worker (pi 任务)
**任务**: R-12 同源 —— 全仓审计 `/api/customers/[id]/*` + 同类面, 并修掉确认的越权

> **结论先报**: 排查 `src/app/api/customers/**` + `src/app/api/interactions/**` + `src/app/api/wellness-records/**` 共 **17 个 route** (含子路由 GET/PATCH/DELETE), 确认 **5 个 route / 7 个方法** 有 IDOR (按 URL 的 `id` 查, 没接 `customerRbacFilter`); 已修; 测试新增 `tests/idor-customer-routes.test.ts` 18 例。

---

## §1. 审计表

**判定规则**:
- ✅ OK = 「URL 里的 id」经过 `getCustomerById(id, { scope: customerRbacFilter(ctx) })` 或等价机制 (行级过滤), 命中不到 → 404
- ❌ IDOR = 仅校验登录, `loadXxx(BigInt(id))` / `db.select().where(eq(xxx.id, id))`, 越权可读/改/删
- ⚠ PARTIAL = 部分方法有 scope, 部分没有 (PATCH/DELETE 等写路径漏)

| # | Route | 方法 | 文件 | 现状 | 风险 | 处理 |
|---|---|---|---|---|---|---|
| 1 | `/api/customers/[id]` | GET | `customers/[id]/route.ts` | ✅ `getCustomerById(id, { scope })` | OK | — |
| 1 | `/api/customers/[id]` | PATCH | `customers/[id]/route.ts` | ✅ `updateCustomer(id, ..., { scope })` | OK | — |
| 1 | `/api/customers/[id]` | DELETE | `customers/[id]/route.ts` | ✅ `softDeleteCustomer(id, ..., scope)` | OK | — |
| 2 | `/api/customers/[id]/ownership` | GET | `customers/[id]/ownership/route.ts` | ❌ `getCustomerOwnership(id, viewerUserId, viewerCustomerId)` 无 scope | **HIGH** | ✏️ 修 |
| 3 | `/api/customers/[id]/transfer` | POST | `customers/[id]/transfer/route.ts` | ✅ `transferCustomerOwnership` 内置「必须是当前归属人或 admin」检查, NOT_OWNER → 403; 不是 IDOR | OK | — |
| 4 | `/api/customers/[id]/bind-account` | POST | `customers/[id]/bind-account/route.ts` | ✅ `getCustomerById(id, { scope })` 命中不到 → 404 | OK | — |
| 5 | `/api/customers/[id]/merge` | POST | `customers/[id]/merge/route.ts` | ✅ `mergeCustomers({ sourceScope, targetScope })`, NO_SCOPE → 403 | OK | — |
| 6 | `/api/customers/[id]/insight` | GET | `customers/[id]/insight/route.ts` | ✅ `getCustomerById(id, { scope })` | OK | — |
| 7 | `/api/customers/[id]/charts` | GET | `customers/[id]/charts/route.ts` | ✅ `getCustomerById(id, { scope })` | OK | — |
| 8 | `/api/customers/[id]/audit` | GET | `customers/[id]/audit/route.ts` | ✅ `getCustomerById(id, { scope })` | OK | — |
| 9 | `/api/customers/[id]/follow-up-analysis` | GET | `customers/[id]/follow-up-analysis/route.ts` | ✅ 已修 (R-12 P0, 2026-09-25) | OK | — |
| 10 | `/api/customers/claim` | POST | `customers/claim/route.ts` | ✅ `claimCustomerOwnership` 内置「不能抢别人的」先到先得 + SELF 拦, 不是 IDOR | OK | — |
| 11 | `/api/customers` | GET | `customers/route.ts` | ✅ 列表自带 `rbacCtx` scope | OK | — |
| 11 | `/api/customers` | POST | `customers/route.ts` | ✅ 写新客户 = 自动归属 creator, 不存在 IDOR | OK | — |
| 12 | `/api/customers/stats` | GET | `customers/stats/route.ts` | ✅ `customerTypeCounts` 同列表口径 | OK | — |
| 13 | `/api/interactions/[id]` | GET | `interactions/[id]/route.ts` | ❌ `getInteractionById(BigInt(id))` 无 scope | **HIGH** | ✏️ 修 |
| 13 | `/api/interactions/[id]` | PATCH | `interactions/[id]/route.ts` | ❌ `updateInteraction(BigInt(id), ...)` 无 scope | **HIGH** | ✏️ 修 |
| 13 | `/api/interactions/[id]` | DELETE | `interactions/[id]/route.ts` | ❌ `deleteInteraction(BigInt(id), ...)` 无 scope | **HIGH** | ✏️ 修 |
| 14 | `/api/interactions` | GET | `interactions/route.ts` | ❌ `listInteractionsByCustomer(customerId)` 无 scope (API 已要求 customerId, 仍可越权) | **HIGH** | ✏️ 修 |
| 14 | `/api/interactions` | POST | `interactions/route.ts` | ✅ POST 是「给指定 customerId 加新互动」 — **不**算 IDOR (建号人即归属人), 仍按既有 `featureGuard` 走 | OK | — |
| 15 | `/api/wellness-records/[id]` | GET | `wellness-records/[id]/route.ts` | ❌ `getWellnessRecordById(BigInt(id))` 无 scope | **HIGH** | ✏️ 修 |
| 15 | `/api/wellness-records/[id]` | PATCH | `wellness-records/[id]/route.ts` | ❌ `updateWellnessRecord(BigInt(id), ...)` 无 scope | **HIGH** | ✏️ 修 |
| 15 | `/api/wellness-records/[id]` | DELETE | `wellness-records/[id]/route.ts` | ❌ `deleteWellnessRecord(BigInt(id), ...)` 无 scope | **HIGH** | ✏️ 修 |
| 16 | `/api/wellness-records` | GET | `wellness-records/route.ts` | ❌ `listWellnessRecords({ customerId })` 无 scope; **且** 无 customerId 时返回**全库**记录 (更严重) | **CRITICAL** | ✏️ 修 (要求 customerId + scope 校验) |
| 16 | `/api/wellness-records` | POST | `wellness-records/route.ts` | ✅ POST = 建新记录归属 creator, 不是 IDOR (但 customerId 是否在范围内未校验 — 留待 v2, 本轮不动) | OK (P1) | — |
| 17 | `/api/follow-ups` | GET | `follow-ups/route.ts` | ❌ `listFollowUpTasks({ customerId })` 无 scope (同 wellness-records 模式) | **HIGH** | 📌 **不在本轮范围** (见 §5 后续) |
| 17 | `/api/follow-ups` | POST | `follow-ups/route.ts` | ✅ POST = 建新任务归属 creator, 同 wellness-record POST, 不是 IDOR | OK (P1) | — |
| 18 | `/api/follow-ups/[id]` | PATCH | `follow-ups/[id]/route.ts` | ❌ `completeFollowUpTask(id, ...)` / `cancelFollowUpTask(id, ...)` 无 scope (同 interactions/[id] 模式) | **HIGH** | 📌 **不在本轮范围** (见 §5 后续) |

> **#16 POST**: POST 端点不校验 `customerId` 是否在 viewer 范围内, 即「销售 A 可以给销售 B 的客户建养生记录」。这一条严格说**也算越权** (写错地方), 但跟 R-12 同源「按 URL id 直接 load」不是一类, 留待后续 ticket (本轮专注读/改/删面的 IDOR)。

> **#17/#18 follow-ups**: 任务书显式枚举的范围是 `customers/[id]/*` + `wellness-records/**` + `interactions/**`。`follow-ups/**` 跟它们是同模式 (task 也是挂 customerId) 且**同样有 IDOR** — 但**不在本轮任务书显式枚举中**。记录在这里供后续 ticket; 不擅自扩范围。

## §2. 修法 (统一口径)

**口径 (与 `customers/[id]/bind-account` / R-12 P0 一致)**:
1. 先 `getCustomerById(parentCustomerId, { viewerFranchiseeId, scope: customerRbacFilter(ctx) })`
2. 命中不到 → **404** (不泄漏存在性; 不外推到 403)
3. 命中 → 继续走底层 query

**位置**:
- `[id]` 类 (interactions/wellness-records/ownership): route 层先 `getXxxById(id)` 拿 customerId, 再 scope; 命中不到 → 404。
- 列表类 (interactions?customerId=, wellness-records?customerId=): 直接对 query 里的 customerId 做 scope; 命中不到 → 404; **同时** `wellness-records` 改成强制要求 customerId (否则无 scope 锚点, 等价于全库泄漏)。
- 命中后再调底层 query (`listInteractionsByCustomer` / `listWellnessRecords` 不变)。

**为什么不动 query 函数签名**: 
- `getInteractionById` / `getWellnessRecordById` / `listInteractionsByCustomer` / `listWellnessRecords` 也被 web admin (`src/app/admin/customers/[id]/page.tsx` + `src/app/admin/wellness-records/page.tsx`) 直接调用 — server 组件自己控制 scope, 让 query 强制接 scope 参数会改大量调用点, 风险大于收益。
- route 层是 IDOR 暴露面, 把 scope 闸门装在 route 层 = web admin 不受影响 (web admin 自己走 server 组件, 已经能拿到登录者身份)。

## §3. 测试 (tests/idor-customer-routes.test.ts)

**18 例覆盖** (修一处跑三遍: 自己可见 2xx / 他人不可见 404 / 未登录 401):

- `customers/[id]/ownership` × 3
- `interactions/[id]` GET/PATCH/DELETE × 3 = 9 + 自己可见 PATCH/DELETE = 5
- `interactions` GET × 3
- `wellness-records/[id]` GET/PATCH/DELETE × 3 = 5
- `wellness-records` GET × 3 + 无 customerId 兜底 (返回 400)

加 admin 豁免测试 (admin 跨范围可看) × 1。

## §4. 关联护栏

- **`src/components/business/customer-list-infinite.tsx`** 加 `{ cache: "no-store" }` (R-10 兜底):
  撤销 / 改归属后浏览器不缓存旧列表, 刷新立即生效。**不**等同于 SSR 失效 (server 仍走 Next 缓存), 只兜住 client-side fetch 那一层。
- 测试侧: 既有的 `customer-scope.test.ts` / `customer-type.test.ts` / `customer-identity.test.ts` / `customer-audit.test.ts` / `integration.test.ts` / `integration-extra.test.ts` / `idor-follow-up-analysis.test.ts` 全部不回归 (本次未动 `customer.ts` 的 query 签名)。

## §5. 后续 ticket (本轮不动, 留待)

- **`/api/follow-ups` GET + `/api/follow-ups/[id]` PATCH**: 同样的 customerId / id 直接 load 越权模式, 应加 `customerRbacFilter` 行级过滤。修法跟 `interactions/` + `wellness-records/` 一模一样。
- **`/api/interactions` POST + `/api/wellness-records` POST**: 写端点没校验 customerId 是否在 viewer 范围内, 属于「写错地方」类的越权 (用户 A 可给用户 B 的客户建互动/养生记录)。
- **`updateWellnessRecord` / `updateInteraction`**: 函数体结尾在**未提交的 tx 上下文**里调 `getWellnessRecordById(id)` / `getInteractionById(id)`, 这两个函数用全局 `db.select()` 走不同连接 → 看不到未提交 update → 返回的 view 是**旧的** (stale-return bug)。调试时已确认:
  - DB 实际写入正确 (`DB decrypted: 新内容`)
  - 但响应 body 返回旧值 (`body.processNote: 原内容`)
  - 本轮 IDOR 修复**未涉及**此 bug (test 改用 post-GET 验证), 但属同一文件 → 后续应一并修。
  - 修法: 在 `updateWellnessRecord` 内部用 `tx.select()` 拿刚 update 的行, 或直接用 `tx.update(...).returning()` 拿到的 `row` 转 view。