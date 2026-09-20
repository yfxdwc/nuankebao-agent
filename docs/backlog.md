# 待办 / 技术债 Backlog

> 用途: 主人点名「记住这个任务，在完成上面全部任务后开始」的条目，以及过程里发现的技术债。
> 规则: 每条带 **背景 / 方案选项 / 待拍板问题 / 前置依赖**；做完移到 CHANGELOG 并在本文件标 ✅。

---

## ① 原始加盟节点启动（Bootstrap Root）· ⏳ 待做（排在当前任务之后）

> **主人 2026-09-20 拍**: 「一个新的团队或加盟树开始时，没有加盟者，也就没人能创建并放置加盟节点。
> 在不破坏现有的加盟节点放置需要三方确认的情况下，怎样启动原始加盟节点？」
> **前置**: 当前迭代（客户跟进引擎 P0 前端 → P1 → P2）全部完成后开始。

### 背景（问题确认）

现有规则（主人 2026-09-19 拍）：
- 设置加盟 = **只有「已加盟用户」或「系统管理员」** 能发起
- 普通落位走 **三方确认**（发起人 + 新加盟商本人 + 目标父节点）；管理员**免多方确认**
- 落位必须给 `targetParentId`（目标父节点）+ `side`

**死锁**：全新团队/加盟树 = 一个加盟商都没有 →
① 没有「已加盟用户」能发起；② 就算管理员发起，**也没有父节点可挂**（根节点没有父节点）→ 第一个节点建不出来。

### 现状核查（代码事实）

| 能力 | 现状 |
|---|---|
| `POST /api/franchisees`（老"直接新增加盟商"） | 已收紧为**管理员专用**；`referrerId` 可空 = 根节点（schema 注释: "null = root (仅 admin 可)"）→ **能力存在，但 App 里没有入口** |
| `createPlacementRequest`（三方确认流） | **强制要 targetParentFid** → 建不了根 |
| dev 数据里的根（杨望 #75, `placement_path=''`） | 是 seed/脚本造的，不是产品流程 |
| App UI | 图谱/落位都需要"我已加盟"（`myFranchiseeTreeProvider` 空则显示"还不是加盟商"）→ 管理员也进不去建根的路 |

### 方案选项（待主人拍板）

| # | 方案 | 优点 | 风险 |
|---|---|---|---|
| **A（推荐）** | **管理员建根**：新增「建立根节点」入口（管理员可见），调一个专用 API（如 `POST /api/franchisees/root`）；校验：该团队**尚无根**才允许；建完根后**所有后续节点照旧走三方确认** | 与既有拍板「管理员免多方确认」一致；入口清晰；不碰三方确认 | 需要明确"一个团队能有几个根" |
| B | 邀请码建根：首个加盟商凭邀请码自助建根 | 无人工介入 | 需要引入"团队邀请码"概念（与 ADR-0012 推荐码不是一回事，容易混） |
| C | 部署时 seed 根节点（现状做法） | 零代码 | 每个新团队都要人工跑脚本，SaaS 化后不可行 |
| D | 「认领根」：第一个到店的加盟商在 App 里认领成根 | 无需管理员 | 谁先来谁是根 → 容易被滥用；且无法验证真实性 |

### 待拍板问题

| # | 问题 | 建议 |
|---|---|---|
| B1 | 一个租户/团队允许几个根？ | 允许多根（= 多门店/多团队），但**同一根下仍是一棵树**；根由管理员建 |
| B2 | 根节点能不能解除加盟 / 转移？ | 根**不能解除**（现有 `createPlacementRequest` 已挡 `根节点不能解除` ✓）；转移 = 换绑账号，另开条目 |
| B3 | 建根要不要留审计与凭据？ | 要：`created_by` + 审计日志 + 可选备注（门店名/来源） |
| B4 | 根节点的"团队"标识用什么？ | 暂用 `store_id`（W5 RBAC 已有列），SaaS 阶段升级为 tenant |

### 实现清单（拍板后）

1. `POST /api/franchisees/root`（管理员 + 该团队无根校验 + 审计）—— 或复用 `POST /api/franchisees`（`referrerId` 空）加显式守卫
2. Flutter：「我的」→ 管理入口「建立根节点」（仅 admin 可见）+ 表单（姓名/手机号/备注）
3. 冒烟 `scripts/smoke-bootstrap-root.ts`：非管理员 403 / 已有根 400 / 成功后该用户成为根且 `placement_path=''`
4. 文档：ADR 或 `docs/placement-confirmation-design.md` 补「根节点」一节

---

## ② build_runner 代码生成不可用 · 🔧 排查中（2026-09-20）

> **现象**: `flutter pub run build_runner build` 失败 → `PathNotFoundException: Cannot open file,
> path = '.dart_tool/build_resolvers/sdk.sum'`；清缓存后变为长时间无输出。
> **影响**: freezed / json_serializable **无法重新生成** → Flutter 侧新增 model 只能手写 `fromJson`（绕开代码生成）。
> **根因线索**: `build_resolvers` 需要先 `buildSdkSummary()` 生成 `.dart_tool/build_resolvers/sdk.sum`
> 并写入 `.deps`；Flutter 自带 Dart SDK 的 summary 生成耗时较长，中途被超时杀掉后会留下"文件不存在"的状态。
> **临时绕行**: 现有 `.g.dart` / `.freezed.dart` 已随 git 提交，改动源码后从 git 恢复生成物即可继续开发（本轮就这样保住了 App 可编译）。
> **候选修法**: ① 让 build_runner 一次性跑完（不设超时，5-15 分钟）；② `flutter pub cache repair`；
> ③ 升级 `build_runner`/`build_resolvers`（改 lockfile，需与其它 session 协调）；④ 减少代码生成依赖（长期）。
