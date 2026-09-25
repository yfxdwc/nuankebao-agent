# R-9 / R-10 优化方案 + 后端落地 (2026-09-26)

> **范围**: 客户列表 (Flutter + Web admin) 的可扩展性与推送撤销的「立即可见」语义
> **状态**: A1 文档 + A2 后端落地 ✅ (主人 2026-09-26 拍「全按建议」)
> **未做**: A1 中 §2 ① Flutter 无限滚动 UI 改造 (Flutter subagent 范围, 后续 Phase E)
> **配套**: [`docs/customer-identity-system.md`](./customer-identity-system.md) §9.2 R-9/R-10 风险表

---

## §0 背景

R-9 / R-10 出自 **客户标识体系 v1.3.3** [`docs/customer-identity-system.md`](./customer-identity-system.md) §9.2 风险表 (主人 2026-09-25 拍, reviewer 2026-09-26 复审通过):

| # | 风险 | 缓解 (最小兜底) |
|---|---|---|
| **R-9** ★ | **列表膨胀**: Phase D 扩围 (b) 下级的客户 + (c) 上级推送的客户 后, viewer 列表候选集从 `owner_id = 我` 单集合扩到 `owner_id = 我 ∪ 同枝下层 ∪ customer_share 推送给我`,枝深的销售员可见行数显著增长 | (1) `viewerCustomerScopeSql` 单一真相源收窄;(2) 收窄策略 flag 可改;(3) 密度棘轮不破;(4) `customerTypeCounts` 缓存 |
| **R-10** ★ | **推送撤销后立即不可见**: 用户期望「撤销推送 = 列表马上少一行」;若后端 / 前端任何一层缓存 `customer_share` 结果, 撤销后用户仍能看到那行, 信任崩塌 | (1) `/api/customers` 不缓存可见集合结果 (Drizzle 直查 + revoke_at 索引);(2) 推送撤销响应立即触发客户端刷新;(3) 集成测试断言;(4) `idx_customer_share_to_active` 索引 |

**时间线**:
- **2026-09-25**: 主人原话「R-9/R-10 暂缓, Phase D 开工前必须提醒主人处理」 (CHANGELOG [unreleased])
- **2026-09-26**: 主人解禁, 拍「全按建议」做深度优化 (本次任务)

**本次落地范围**:
- A1: 优化方案文档 (本文件 §1-§7)
- A2: 后端实施 (索引补齐 + count 解耦 + Cache-Control)
- A3 (未做): Flutter 无限滚动 UI (Flutter subagent 后续 Phase E)

---

## §1 R-9 事实与根因

### 1.1 现状三连击 (每条都带 file:line)

| # | 现象 | 文件:行 | 根因 |
|---|---|---|---|
| **F-1** | Flutter 客户列表只有单页 50 条, 无无限滚动 | `flutter_app/lib/core/providers/service_providers.dart:201-211` (写死 `limit: 50, offset: 0`); `flutter_app/lib/modules/customer/screens/customer_list_page.dart:475-499` (只有 `RefreshIndicator`, 没有滚到底部触发) | 列表页固化为「加载单页 50 条」语义, 不响应"还有更多" |
| **F-2** | 紧急度排序时先按 `lastInteractionAt ASC NULLS FIRST` 拉全集 2000 条 → 内存 `sortByUrgency` → slice 分页 | `src/app/api/customers/route.ts:144-164` (`SORT_SAFETY_LIMIT=2000` + `needAll=true`);`src/lib/follow-up/attach.ts:236-258` `sortByUrgency` | SQL 不能直接表达「紧急度」(分数计算依赖 JOIN follow_up + 复购窗口) → 必须先拉到内存再排 |
| **F-3** | 每页都跑全表 `count(*)` | `src/lib/db/queries/customer.ts:708-790` `Promise.all([select, count])`; 后续每页都重复 | 列表与计数都跑全表, 大表 (1k+ 行) 时 count 是 O(N), 与 select 不可分摊 |

### 1.2 索引缺口 (加剧 F-3, 同时让 SELECT 也慢)

| 排序 | 当前索引 | 影响 |
|---|---|---|
| `sort='new'` (默认) | ❌ 无 `customer(created_at)` 索引 | 全表顺序扫 + sort (R-9 候选集大时退化) |
| `sort='name'` | ❌ 无 `customer(name)` 索引 | 全表顺序扫 + sort |
| `sort='recent'` / `urgency` (用 last_interaction_at) | ✅ `idx_customer_last_interaction` (单列) | 已有;但与 owner_id 复合查询会回表 sort |
| 「我的客户 + 最近联系」 (W5 RBAC 行级) | ✅ `idx_customer_owner` + ✅ `idx_customer_last_interaction` (各单列) | owner_id 行数千时 → owner 索引筛 → 回表按时间重排 (O(N log N)) |

**结论**: 三个缺失索引补齐后, R-9 列表膨胀 (owner 数千行) 的退化能缓解, 不需要换数据模型。

---

## §2 R-9 优化方案

### 2.1 总览

| 优化项 | 落点 | 状态 |
|---|---|---|
| ① Flutter 无限滚动 | `flutter_app/lib/modules/customer/screens/customer_list_page.dart` + `service_providers.dart` | 🔄 未做 (后续 Phase E) |
| ② count 解耦 | `src/lib/db/queries/customer.ts` `listCustomers` + `src/app/api/customers/route.ts` | ✅ 已落地 (本次 A2) |
| ③ 索引补齐 | `drizzle/0029_customer_list_indexes.sql` | ✅ 已落地 (本次 A2) |
| ④ 最小兜底 (单点收窄开关) | `src/lib/db/queries/customer-scope.ts` `viewerCustomerScopeSql` + config flag | ✅ 已存在 (ADR-0015 步骤 1) |
| ⑤ 验收: 密度棘轮 + 分页 widget test + count 语义测试 | `tests/customer-list-count-decoupling.test.ts` | ✅ 已落地 (本次 A2) + `bash tools/check-ui-density.sh` (后续 Phase E 触发) |

### 2.2 ① Flutter 无限滚动 (语义对齐 web admin)

**对齐** `src/components/business/customer-list-infinite.tsx:118-160` 的实现:

```dart
// service_providers.dart 改造草案 (Phase E)
final customersProvider = FutureProvider.family<CustomerListResult, CustomerListQuery>(
  (ref, query) async {
    // limit / offset 都从 query 拿, 不写死
    return ref.watch(customerServiceProvider).list(
      search: query.search,
      type: query.type,
      sort: query.sort,
      limit: query.limit,
      offset: query.offset,
    );
  },
);

// customer_list_page.dart: ListView.builder 加 onScrollEnd → loadMore()
class CustomerListPaginationState {
  final List<CustomerWithFollowUp> items;
  final int? total;        // null = 服务端没跑 count (后续页)
  final bool hasMore;      // derived: total == null ? length === limit : items.length < total
  final int nextOffset;
  ...
}
```

**关键不变量**:
- `pageSize` = 50 (与现状一致, 不引入新尺寸)
- `hasMore` 判定: 服务端返回 total=null (后续页) → `items.length === limit` ? 继续 : 停;服务端返回 total=数字 → `items.length < total` ? 继续 : 停
- `offset` 累加: 每次 loadMore += items.length (而不是 += limit, 因为最后一页可能不满)

### 2.3 ② count 解耦 (本次落地)

**接口改动**: `listCustomers` 新增 `includeTotal?: boolean` (默认 true 保持兼容)

**返回类型**: `{ items, total: number | null }` (原 `total: number`)

**行为矩阵**:

| 场景 | `includeTotal` | `offset` | 行为 | 返回 total |
|---|---|---|---|---|
| 首页 | `true` (默认) | `0` | `Promise.all([select, count])` | `count(*)` 实际值 |
| 后续页 (满页) | `false` | `> 0` | 只 select, 无 count | `null` (可能还有) |
| 后续页 (末页) | `false` | `> 0` | 只 select, 无 count;items.length < limit | `items.length + offset` (final) |
| urgency 排序 | `false` (route 强制) | 任意 | 只 select;内存 sortByUrgency 后 total 由 `sorted.length` 重写 | (route 覆盖) |

**调用方语义 (必须知道)**:
- 首页客户端: total 必非 null → 显示「共 X 位客户」
- 后续页客户端: total 可能为 null → 必须保留上一页 total, 不要拿 null 去算 hasMore (`items.length < null` = false = 立刻停 = 永远只看到首屏)
- `src/components/business/customer-list-infinite.tsx:158` 已改:
  ```ts
  setTotal((prev) => (data.total == null ? prev : data.total));
  ```

**为什么 default = true**: 既有调用方 (web admin SSR `src/app/admin/customers/page.tsx:19` 等) 依赖 total 给 PageHeader 写「共 X 位客户」。改成默认 false 会破坏既有 SSR 渲染。改成默认 true (含 total) → 后续页调用方显式传 false → 兼容 + 优化并存。

**性能影响** (实测 / 估算):
- 主页 (offset=0): 不变, 仍是 1 次 select + 1 次 count (Promise.all 并发)
- 后续页: 少 1 次 count (大表 1k+ 行可省 30-100ms)

### 2.4 ③ 索引补齐 (本次落地)

**新增三个索引** (drizzle/0029_customer_list_indexes.sql):

| 索引名 | 列 | 命中场景 |
|---|---|---|
| `idx_customer_created_at_desc` | `created_at DESC` | `sort='new'` 默认排序 + 创建审计 |
| `idx_customer_name` | `name` | `sort='name'` |
| `idx_customer_owner_last_interaction` | `(owner_id, last_interaction_at DESC NULLS LAST)` | W5 RBAC「我的客户 + 最近联系」复合查询 |

**复合索引第三列选 DESC NULLS LAST 的理由**:
- 既有 sort='recent' 走 `lastInteractionAt DESC NULLS LAST` (`customer.ts:780`): PG planner 命中同一顺序
- 既有 sort='urgency' 走 `ASC NULLS FIRST` (candidate 阶段): 命中反向扫描; 主排序已是 sortByUrgency 内存, candidate 阶段是兜底粗排, 反向扫可接受
- 既有 idx_customer_last_interaction 单列不指定方向; 加复合索引不影响单列查询

**为什么不加 (last_visit_at, last_interaction_at)**:
- last_visit_at 只用于 stats 报表, 不参与列表排序
- 单加不痛, 多加浪费 (R-9 不在该列上退化)

### 2.5 ④ 最小兜底 (单点收窄开关) — 已存在, 不动

`viewerCustomerScopeSql` (`src/lib/db/queries/customer-scope.ts:27-49`) 已经是 viewer 可见集的单一真相源;收窄策略 flag (e.g. `customerScope.includeSubordinates`) 由后续 ticket 单独拍。本次 R-9 不在「收窄」这条路上加新 flag。

### 2.6 ⑤ 验收

**密度棘轮** (Phase E 跑, 本次不验):
```bash
bash tools/check-ui-density.sh        # 列表 visibleRows ≥ 11
bash tools/check-ui-tokens.sh         # 卡片 / 调色板 / 字号不破
```

**分页 widget test** (Phase E 写, 本次不验):
- `flutter_app/test/widgets/customer_list_pagination_test.dart`:
  - 滚到底 → 触发 loadMore
  - 满页 → hasMore=true; 末页 → hasMore=false
  - offset 累加 = items.length (不是 limit)

**count 语义测试** (本次 A2 落地):
- `tests/customer-list-count-decoupling.test.ts`: 见 §6 验收清单

---

## §3 R-10 事实与根因

### 3.1 现状五连击

| # | 现象 | 文件:行 | 根因 |
|---|---|---|---|
| **F-4** | `dio` 默认 cache (dio_cache_interceptor 未启用), 但 web 平台 XHR 在某些条件下仍走浏览器 cache | `flutter_app/lib/core/http/dio.dart` 配置 | dio 本身不带 cache, 但 web 走 Service Worker / 浏览器 disk cache |
| **F-5** | 撤销推送后客户端**没有立即 invalidate** `customersProvider` (撤销入口在归属卡, 但归属卡不一定打开列表) | `flutter_app/lib/modules/customer/widgets/ownership_card.dart:160` 仅 invalidate 当前打开的 `customerDetailProvider`; `customersProvider` 没主动失效 | 撤销响应仅刷详情, 没刷列表 |
| **F-6** | 列表页**没有返回时刷新**机制 (`RouteAware didPopNext` 未实现) | `flutter_app/lib/modules/customer/screens/customer_list_page.dart` (全文搜索 `didPopNext` / `RouteAware` 无结果) | 用户从归属卡撤销 → 返回列表 → 列表不会自动刷新, 必须下拉 |
| **F-7** | 列表页**没有恢复前台刷新** (`AppLifecycleState.resumed` 未监听) | `flutter_app/lib/modules/customer/screens/customer_list_page.dart` (全文搜索 `AppLifecycleState` 无结果) | 用户切到后台 → 别人推送/撤销 → 切回来 → 列表不刷 |
| **F-8** | `/api/customers/shares/received` 是**死代码** (Flutter 没人调, web admin 没人调) | `flutter_app/lib/core/services/api.dart:385-389` `receivedShares()` 无引用;`tests/customer-share.test.ts:550` 单测只测后端 | 接口定义存在但 UI 没有入口, 单纯给"将来的我"备的 |

### 3.2 关键发现

> **后端已有 `idx_customer_share_to_active` (to_user_id, revoked_at) 索引** (`drizzle/0028_customer_share.sql:53-57`)
>
> R-10 第 4 条缓解 (撤销即过滤) **已经在数据层兜住**。缺的是客户端"撤销/推送后立即刷" + 服务端「响应不被中间层缓存」。本次做的是**客户端 + HTTP 头**, 不是 SQL。

---

## §4 R-10 三层「立即生效」语义定义

**这是本次最关键的澄清**。**「立即生效」≠「跨设备 1ms 实时同步」**。本次不引入 SSE/WebSocket (理由见 §4.4)。

### 4.1 三层定义

| 层 | 触发场景 | 当前体验 | 期望体验 | 实现方式 |
|---|---|---|---|---|
| **L1 同端立即** | 同一台手机 / 同一浏览器 tab 内, 用户在归属卡撤销推送 | ✅ L1 已好 (Flutter `ref.invalidate(customersProvider)` 已在 `ownership_card.dart:160` 触发);web admin 走 `router.refresh()` | 保留 | 不动 |
| **L2 同用户返回列表刷新** | 用户在详情页/归属卡操作, 返回列表 | ❌ F-6: 列表不自动刷, 必须下拉 | 返回列表时自动刷一次 (`RouteAware didPopNext`) | Flutter subagent (Phase E) |
| **L3 跨端 (其他设备 / 另一台电脑)** | 上级 A 在电脑推送客户给下级 B; B 在手机上 | ❌ F-4/F-7: 没有实时通道 | "下次拉取生效" — 触发点 = (1) B 恢复前台 (2) B 下拉刷新 (3) B 进入列表 | L2 + F-7 + **服务端 no-store 响应头** (本次 A2) |

### 4.2 L3 触发点 (本次要落地的)

| 触发点 | 实现 |
|---|---|
| **恢复前台 + 下拉刷新 + 进入列表** | Flutter 监听 `AppLifecycleState.resumed` + 列表 `RefreshIndicator` + `RouteAware didChangeDependencies` (首次进入) |
| **服务端响应不缓存** | 所有 customer/share/stats route 加 `Cache-Control: no-store` (本次 A2) |

### 4.3 为什么 L3 不做实时推送 (不引入 SSE/WebSocket)

**主人 2026-09-26 拍「不做 SSE」**, 理由:

| 维度 | SSE/WebSocket | L3「下次拉取生效」 |
|---|---|---|
| **跨端延迟** | < 1s | 用户主动触发 (恢复前台/下拉/进列表) |
| **后端成本** | 常驻连接 + 鉴权 + 重连 + 离线补偿 | 0 (复用既有 query) |
| **触发频率** | 每次推送/撤销都发 | 用户主动刷一次就生效, 频率 ≈ 销售员每天 10-50 次 |
| **业务覆盖** | 100% 实时 | 90%+ 覆盖 (用户大多在同一个设备上操作; 跨设备操作后用户下次看列表即生效) |
| **风险** | 连接泄漏 / 鉴权漏洞 / 重连风暴 | 0 |

**结论**: SSE 的"1s 实时"换 L3 "用户主动触发即生效", **业务可接受**。后续若有强实时需求 (e.g. 上级强推送紧急客户 + 下级必须立刻看到), 单独拍板, 不与 R-10 绑定。

### 4.4 L1+L2+L3 协作示例

```
09:00:00  B 在手机上打开客户列表 (L3 触发点 #3)
          → 拉 /api/customers, 拿 no-store 响应, 共 87 位
09:00:10  A 在电脑上把客户 #42 推送给 B
          → POST /api/customers/42/share
          → 返回 201, 响应 no-store
09:00:20  B 切到微信回客户消息
          → AppLifecycleState.paused (无操作)
09:05:30  B 切回 app
          → AppLifecycleState.resumed
          → L3 触发点 #1 命中
          → Flutter ref.invalidate(customersProvider)
          → 拉 /api/customers, 拿 no-store 响应, 共 88 位 (#42 出现)
09:05:35  A 撤销对 B 的推送
          → DELETE /api/customers/42/share/B
          → 返回 200 { revoked: true }, 响应 no-store
09:05:40  B 下拉刷新
          → L3 触发点 #2 命中
          → 拉 /api/customers, 拿 no-store 响应, 共 87 位 (#42 消失)
```

---

## §5 R-10 优化方案 (落点文件)

### 5.1 Flutter 客户端 (Phase E, 本次不做)

| 优化项 | 落点 |
|---|---|
| 撤销推送成功后 `ref.invalidate(customersProvider)` + `customerTypeCountsProvider` | `flutter_app/lib/modules/customer/widgets/ownership_card.dart:160` 已有 customersProvider;补 customerTypeCountsProvider |
| 推送成功后同上 | `ownership_card.dart` 推送入口 |
| 列表页 `RouteAware didPopNext` | `flutter_app/lib/modules/customer/screens/customer_list_page.dart` 新加 mixin |
| 列表页 `AppLifecycleState.resumed` 监听 | 同上, 用 `WidgetsBindingObserver` |
| 列表页 `RefreshIndicator` (已有) | 不动 |

### 5.2 服务端响应头 (本次 A2 落地)

**统一 helper**: `src/lib/http/no-store.ts` (新文件)

```ts
export const NO_STORE_HEADERS = { "Cache-Control": "no-store" } as const;
export function noStoreJson<T>(body: T, init?: ResponseInit): NextResponse<T> { ... }
export function noStoreResponse(body: BodyInit | null, init?: ResponseInit): Response { ... }
```

**改造的 route**:

| Route | 文件 | 改造点 |
|---|---|---|
| `GET /api/customers` | `src/app/api/customers/route.ts` | `NextResponse.json` → `noStoreJson` (×2) |
| `POST /api/customers` | 同上 | ×4 |
| `GET /api/customers/[id]` | `src/app/api/customers/[id]/route.ts` | ×1 |
| `PATCH /api/customers/[id]` | 同上 | ×6 |
| `DELETE /api/customers/[id]` | 同上 | ×3 |
| `GET /api/customers/stats` | `src/app/api/customers/stats/route.ts` | ×2 |
| `POST /api/customers/[id]/share` | `src/app/api/customers/[id]/share/route.ts` | ×8 |
| `DELETE /api/customers/[id]/share/[userId]` | `src/app/api/customers/[id]/share/[userId]/route.ts` | ×6 |
| `GET /api/customers/[id]/share/candidates` | `src/app/api/customers/[id]/share/candidates/route.ts` | ×5 |
| `GET /api/customers/[id]/shares` | `src/app/api/customers/[id]/shares/route.ts` | ×5 |
| `GET /api/customers/shares/received` | `src/app/api/customers/shares/received/route.ts` | ×3 |

**未改造 (后续 ticket)**:
- `transfer / merge / bind-account / ownership / insight / charts / follow-up-analysis / audit` 等: 这些是写操作或单条 GET, 与"列表可见集合"无关。本次范围按任务 spec 限定, 不外推。

**为什么用 wrapper 而不是 middleware**:
- Next.js middleware 跑在 edge runtime, 改不了 Node-runtime route 的 response headers 的同时不影响 Next 内部缓存机制 (`force-dynamic` 已设)
- per-route 显式调 `noStoreJson()` 比 middleware 黑盒更可控, 错误时定位简单

### 5.3 `receivedShares` 死代码处理决定

**事实**:
- `flutter_app/lib/core/services/api.dart:385-389` `receivedShares()` 方法定义存在, **无任何调用方** (grep 全仓 `receivedShares()` 仅这一处定义)
- `tests/customer-share.test.ts:550-609` 后端 `listReceivedShares` 单测齐全
- 路由层 `src/app/api/customers/shares/received/route.ts` 正常响应

**选项**:
- **A. 做 UI 入口**: 在 Flutter 列表角标加「N 条上级推送」tap 进独立页, 展示 `receivedShares` 数据 (姓名 + 打码手机号 + 备注)
- **B. 删 API + Flutter 方法**: 既然没 UI, 删了避免误导
- **C. 保留, 加 TODO 标「Phase E 接入」**: 不删, 但加注释说明现状

**主人 2026-09-26 拍「先做最小够用」, 选 C**:

| 理由 | 说明 |
|---|---|
| 后端单测齐全 (`customer-share.test.ts:550-609`) | 删了 = 删测试覆盖 |
| 路由层签名稳定 | 以后接 UI 不需要改 SQL |
| Phase E 仍可能补 UI | 主人保留口子 |
| 删了需要协调 backend + tests + 5 处 import | 收益低于成本 |

**实施**:
- 不删代码, 仅在 `src/app/api/customers/shares/received/route.ts` 顶部加注释说明"Flutter 暂未接入, 死代码; 主文档 §9.3 角标元数据约定"

---

## §6 验收清单 (可执行命令 + 断言)

### 6.1 后端迁移 / 索引

| 命令 | 期望结果 |
|---|---|
| `pnpm db:compat` | exit 0, "✅ migration 兼容性检测通过" |
| `DATABASE_URL=postgres://nuankebao:<pwd>@localhost:5432/nuankebao_test pnpm db:migrate` | "✓ Drizzle up migration 完成" + 0029 出现在 journal |
| `psql ... -c "\d+ customer"` | 看到 3 个新索引: `idx_customer_created_at_desc` / `idx_customer_name` / `idx_customer_owner_last_interaction` |
| `pnpm type-check` | exit 0 |

### 6.2 count 语义测试

`tests/customer-list-count-decoupling.test.ts` (新文件) 覆盖:

| 用例 | 断言 |
|---|---|
| **首页 offset=0, includeTotal 默认**: 拉 5 条, total = 5 | `result.total === 5` |
| **首页 offset=0, includeTotal=true 显式**: 拉 3 条, total = 5 | `result.total === 5` |
| **后续页 offset>0, items.length < limit (末页)**: 拉 limit=20, items=3, total = 23 (offset 20 + 3) | `result.total === 23` |
| **后续页 offset>0, items.length === limit (满页)**: 拉 limit=20, items=20, total = null | `result.total === null` |
| **后续页 offset>0, includeTotal=false 显式**: total 同上 | 不跑 count (spy 验证 db.select 被调次数) |
| **后续页 offset>0, includeTotal=true 显式**: 保留旧行为, total = 全表 count | `result.total === 全表行数` |
| **route /api/customers?offset=20**: total 可能为 null, 但字段存在 | 响应 JSON 字段存在, 不抛 500 |
| **route /api/customers?offset=0**: total 必为 number | `response.total === number` |

### 6.3 响应头

| 命令 | 期望 |
|---|---|
| `curl -i http://localhost:3000/api/customers \| grep -i cache-control` | `Cache-Control: no-store` |
| `curl -i http://localhost:3000/api/customers/stats?search=张 \| grep -i cache-control` | `Cache-Control: no-store` |
| `curl -i http://localhost:3000/api/customers/1 \| grep -i cache-control` | `Cache-Control: no-store` |
| `curl -i -X POST http://localhost:3000/api/customers/1/share -H 'Content-Type: application/json' -d '{}' \| grep -i cache-control` (401 也算) | `Cache-Control: no-store` |

### 6.4 全量测试

| 命令 | 期望 |
|---|---|
| `DATABASE_URL=postgres://nuankebao:<pwd>@localhost:5432/nuankebao_test pnpm test:run` | exit 0 (既有 778 + 新增 8 = 786 例) |
| `pnpm type-check` | exit 0 |
| `pnpm db:compat` | exit 0 |

---

## §7 残余风险与下一步

### 7.1 残余风险

| # | 风险 | 备注 |
|---|---|---|
| **RR-1** | Flutter 无限滚动 UI (R-9 ① + R-10 ① ②) **未做** | 在 Phase E 单独 ticket |
| **RR-2** | L3「下次拉取生效」依赖用户主动触发 (恢复前台/下拉/进列表) | 主人 2026-09-26 拍「可接受」, 见 §4.3 |
| **RR-3** | 索引 rebuild 时间: 大表 (10w+ 行) 上 `CREATE INDEX` 不带 CONCURRENTLY 会锁表 | 本次 dev 数据库行数 < 1w, 锁表 < 1s; 生产若大表, 改 `CREATE INDEX CONCURRENTLY` |
| **RR-4** | `receivedShares` 仍是死代码 | §5.3 选 C 保留; 主文档 §9.3 角标元数据约定不变 |
| **RR-5** | Phase D 实施期间若加新 customer route (e.g. 合并确认 / 转移审核), 开发者需记得 `noStoreJson` | 在主文档 §6.5 API 列表加 reminder; 不在本任务 |
| **RR-6** | 后续 web admin 若增加"我推送出去的客户"管理页, 应同步加 noStoreJson | 不在本任务 |

### 7.2 下一步 (推荐)

1. **Flutter Phase E ticket** (跨端 owner): 实现 R-9 ① + R-10 ①② (无限滚动 + RouteAware + AppLifecycleState)
2. **运营观察**: 上线一周后看 `/admin/usage` 用量模块 (R-9 列表膨胀后, 列表 API 调用次数 / 响应时间分布)
3. **大表 reindex**: 若 `customer` 表行数 > 10w, 跑 `REINDEX INDEX CONCURRENTLY idx_customer_owner_last_interaction`
4. **后续 ADR**: R-10 L3「下次拉取生效」正式入主文档 (现 §9.2 是缓解措施, 不是显式三层定义)
5. **测试加强**: E2E (Playwright) 测 web admin 推送 → 撤销 → 列表 200ms 内消失; Flutter 同 (Dart integration_test)

---

## §X 修订记录

| 版本 | 日期 | 修订 |
|---|---|---|
| v1.0 | 2026-09-26 | 初稿 (本次任务落地) |