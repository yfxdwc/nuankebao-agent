# 待办 / 技术债 Backlog

> 用途: 主人点名「记住这个任务，在完成上面全部任务后开始」的条目，以及过程里发现的技术债。
> 规则: 每条带 **背景 / 方案选项 / 待拍板问题 / 前置依赖**；做完移到 CHANGELOG 并在本文件标 ✅。

---

## ✅ 挂起项已修 · 「认领为我的客户」行动是死路 (2026-09-23 发现 → 同日修)

> **主人原话**: 「先挂起这个bug，后期提醒我修。」→ 当天随后拍「修」, **已修** ✅
>
> **修法 (落地)**: 新增 `ActionItem.cta` (`create_task` | `claim_ownership`) —— 把
> 「这条行动该怎么闭环」**由后端声明**, 前端只按 cta 渲染按钮, 不在前端硬编码规则 id。
> L0 的 `profile_incomplete` 现在给「认领」按钮 → 调 `POST /api/customers/claim`
> → `hasOwner` 变 true → **行动消失** (闭环完成)。
> 成功提示后 invalidate 洞察 / 归属卡 / 详情 / 客户列表四处。
> 顺带: 按钮文案用「认领」而不是「认领为我的客户」—— 后者是它的**标题**,
> 同一行出现两遍既冗余又让人以为点错 (其它规则天然不同: 标题「约下次到店」+ 按钮「建任务」)。
> 护栏: `tests/customer-scoring.test.ts` 3 例 (每条规则都声明 cta /
> profile_incomplete 必须是 claim_ownership / 其余必须是 create_task);
> `customer_insight_header_test.dart` 5 例 (按钮形态 / 走 onClaim 不走 onBuildTask / 已认领 / 失败不崩 / 回归)。

**现象**: L0 会弹出行动「**认领为我的客户**」(`expected: 进入我的客户列表`),
但它唯一的按钮是「**建任务**」—— 建任务**完全不碰 `customer.owner_id`**,
于是 `hasOwner` 恒为 false, **这条行动永远消不掉**。
销售可以反复点出一堆「认领客户」任务, 客户始终不在他列表里。

**证据链 (三层, 已核实)**
1. 规则层 `src/lib/customer/actions.ts` 规则 8: `if (!input.hasOwner)` →
   `title: "认领为我的客户"` / `expected: "进入我的客户列表"` / `channel: "profile"`
2. UI 层 `flutter_app/lib/modules/customer/widgets/customer_insight_header.dart`
   `_ActionRow` **只渲染一个按钮**「建任务」→ `_buildTaskFromAction` → 写 `follow_up_task`
3. 全仓 grep: **没有任何地方对 `profile_incomplete` 做特殊处理**

**为什么现有两条认领路径兜不住它**: App 里能认领的地方是
「我推荐的人」页 + **新建客户**表单的填推荐码流程 —— **两条都走邀请码, 且都不在详情页**。
触发本行动的典型场景是「她挂在我的直推加盟分支下但 `owner_id` 为空」, 这时手里**未必有她的邀请码**。

**根因**: 「建任务」对另外 8 条规则是对的 (行动 = 去联系她 → 任务 = 提醒);
但 `profile_incomplete` 是**对客户档案本身做配置变更**, 不是一次联系动作 —— **动词用错了**。
(L0 那行其实已显示「本周 · 档案」, 说明 UI 知道类别, 却仍只给「建任务」。)

**修法 (已核实可行, 改动小)**
- `channel == 'profile'` (或按 `id == 'profile_incomplete'`) 时, 按钮改为「认领为我的客户」
- 调已有的 `customerService.claim(customerId)` (Flutter service 已封装好, `api.dart`)
- 后端条件成立: `claimCustomerOwnership` 只要求「无归属 → 成功 / 已是我的 → 幂等 /
  归属别人 → 409」, **不要求对方有账号** ✓
- 成功后 `hasOwner` 变 true → 行动自动消失 ✓
- 顺带: 归属别人时应显示「已被 X 认领」而不是给一个点了会 409 的按钮

**影响面**: 只有被 `profile_incomplete` 命中的客户 (无 `owner_id`)。
**严重度**: 中 —— 不崩不丢数据, 但违反 CHARTER §1.4「行动输出 = 明确的可落地指引」
和 P1 自己的「必须可闭环」原则; 且会给销售"点了没用"的挫败感。

---

## ✅ ⓪-新 · admin 「客户管理参数调节」页 (2026-09-23 完成)

> **主人原话**: 「挂起待办任务：在 admin 里增加管理、调节页面，让评分规则及其他客户管理中的参数可在管理页面进行调节」

**已落地** (CHANGELOG 同日条目):

| # | 东西 | 落地位置 |
|---|---|---|
| 1 | **DB 覆盖层** | 表 `app_config(key, value jsonb, description, updated_by, updated_at)` + audit 触发器; 迁移 `0024_app_config` |
| 2 | **读写口** | `src/lib/config/app-config.ts` (通用, 不懂业务) + `src/lib/customer/insight-config-store.ts` (夹区间 / 版本 / 重置) |
| 3 | **admin 页** | `/admin/settings/insight` + `components/business/insight-config-editor.tsx` (6 组折叠面板) |
| 4 | **版本提示** | 内容真变了才 `scoring.version`/`actions.version` +1 |
| 5 | **重置为默认** | 删覆盖行 (不是写一份等于默认的值) |
| 6 | **"其他客户管理参数"** | 通用表已就绪, 接新参数组只需加一个 `*-store.ts` (紧急度/分页待接) |

**额外做的**: 「预估影响面」按钮 —— 保存前抽样算一遍会改掉多少客户的分数/行动
(`POST /api/admin/insight-config/impact`)。

**为什么"改造门面"用抽样而不是全量**: 每位客户要按两套参数各跑一次完整洞察 (各 ~6 次查询),
全量在同步请求里不现实; 返回体带 `sampled` / `sampledAll`, 页面明示"抽样估算" (不假装精确)。

**已拍的 3 个问题** (按最窄口径实现, 若要放宽需主人再拍):
- 谁能改 → **仅系统管理员** (`role='admin'` 服务端查库)
- 改了通不通知销售 → **本期不做**; 靠参数版本号 + 详情页"规则已更新"提示兜
- 按不按门店隔离 → **全局一套** (CHARTER §3.6 门店维度已冻结)

**发现并记下的 repo 隐患**: drizzle 的 snapshot 只到 **0016**, 0017-0023 都是手写迁移 →
直接跑 `drizzle-kit generate` 会把 0020-0023 的变更**整段重放** (对已有库是灾难)。
本次按既有约定手写 `0024_app_config.sql` + 手工追加 `drizzle/meta/_journal.json`。
后续要么补齐 snapshot, 要么在 `db:generate` 上加护栏 —— 已记入下方技术债。

## 技术债 · drizzle snapshot 只到 0016, `db:generate` 会整段重放 (2026-09-23 发现, **已落地护栏 (b) 2026-09-23**)

**现象**: `npx drizzle-kit generate` 输出 `0024_*.sql` 里包着 **0020-0023 的全部变更**
(建表 + 重复 ALTER `customer.owner_id` 等)。原因是 `drizzle/meta/` 的 snapshot 停在 `0016`,
之后 0017-0024 都是手写迁移 + 手工改 `_journal.json`。

**风险**: 谁在不了解这一点时跑一次 `db:generate` 并 apply, 对已有库 = 重复 ALTER / 重复建表,
可能直接挂。

**可选方案**:
- (a) 补齐 0017-0024 的 snapshot 链 (工作量大, 但一劳永逸; **未做**, 评估见下方 §Snapshot 补齐 评估)
- (b) ✅ 在 `package.json` 的 `db:generate` 外面包一层护栏脚本: 先 dry-run, 若 diff 里出现
      已知表/列/索引的危险重放就拒绝并提示"手写迁移"
- (c) 只在 README/AGENTS 写明 (最轻, 但靠人记)

**已落地 (b) 2026-09-23**:

| # | 东西 | 位置 |
|---|---|---|
| 1 | **bash 包装** (隔离临时目录跑 drizzle-kit + 调纯函数检测) | `tools/check-drizzle-generate.sh` |
| 2 | **检测纯函数** (`detectReplay` / `collectExistingObjects`, 可单测) | `tools/check-drizzle-generate.ts` |
| 3 | **package.json 接入** | `"db:generate": "bash tools/check-drizzle-generate.sh"` (替代原 `drizzle-kit generate`) |
| 4 | **单测** | `tests/drizzle-generate-guard.test.ts` (16 例, 全 pass) |
| 5 | **设计要点** | 仓库 `drizzle/` **永不被碰** (drizzle-kit 跑在 `/tmp/drizzle-generate-guard.*/`, `trap EXIT` 兜底清理); 「已知表/索引」自动 grep `drizzle/*.sql` (33 表 / 71 索引, 不维护硬编码清单) |
| 6 | **危险判定** | ① CREATE 已存在表 ② ALTER 已存在表 (任意 ADD/DROP/RENAME/ALTER COLUMN) ③ DROP 已存在索引 (含 IF EXISTS) |
| 7 | **不误报** | CREATE INDEX IF NOT EXISTS / 全新表 / 空文件 / 纯注释 / 仅 DROP 不存在索引 全部放行 |

**为什么 (b) 而不是 (a)**: AGENTS §5「贴告示 ≠ 修复」同根 — 信任手写检查 = 复发温床;
护栏让「危险 diff 静默 apply 到已有库」物理上不可能。

**以后要加 migration 的正确姿势 (主路径, 必走)**:

```bash
# 1. 自己写 drizzle/<NNNN>_your_change.sql (见 0024_app_config.sql 格式 / ADR-0004)
#    纯 additive (CREATE TABLE / ADD COLUMN + DEFAULT / CREATE INDEX IF NOT EXISTS)
# 2. 在 drizzle/meta/_journal.json 追加一条:
cat drizzle/meta/_journal.json | jq '.entries[-1].idx'  # 取最新 idx
# 然后手添一条 { idx: <last+1>, version: "7", when: <Date.now()>, tag: "<NNNN>_your_change", breakpoints: true }
# 3. (破坏性变更) 补 drizzle/down/<同名>.down.sql + 跑 pnpm db:compat
# 4. 跑 pnpm db:generate 验证护栏无错 (应该 exit 0, 没命中危险)
#    - exit 0 = "你的 schema.ts 与新 snapshot 一致" 或 "新变更没命中危险模式" ✓
#    - exit 1 = "危险命中" → 修护栏的现有对象识别 (或确认是误报后 bypass)
```

**禁止 (反模式)**:
- ❌ 直接 `npx drizzle-kit generate` 绕过护栏 (护栏就是为这个设的)
- ❌ 把 generate 出来的 .sql 原样放进 `drizzle/` (即使护栏绿灯, 它是按 0016 snapshot 算的 diff, 仍可能与新加的 0025 snapshot 错位)
- ❌ 删旧 migration 让 snapshot 自动重算 (CHARTER §3.5 红线)

### Snapshot 补齐 (方案 a) 评估 — **未做**

| 维度 | 评估 |
|---|---|
| 可行性 | 可行 — drizzle-kit 在 0016 snapshot 上跑一次 generate, 拿输出当 0017_snapshot.json, 依此类推到 0024。需要 `drizzle/0025_<empty>.sql` 当起点。 |
| 工作量 | 中 — 8 个 snapshot (0017-0024), 每个需要手工校对 vs 手写 .sql 的字段差异 (函数签名 / 默认值 / 列顺序)。预估 2-3 小时。 |
| 风险 | 中 — ① 校对漏字段会让下次 generate 重新输出旧结构, 假阴性消失但**真变更也被吞**; ② snapshot 一旦走错, 之后所有 generate 都基于错基线, 污染扩散; ③ 与现有 0017-0024 .sql 头部注释里写的「snapshot 不再更新」叙事冲突, 需主人拍「我们改主意了」。 |
| 收益 | 长期 — `pnpm db:generate` 恢复「真 diff」语义, 不用手写 migration (除非要加对象)。但主人已接受手写流程 (0022-0024 都是这么做的), 收益边际。 |
| 结论 | **不做** — 护栏 (b) 已经把「灾难级误操作」堵死, 剩余收益不足以抵消校对风险 + 主人已接受的工作流变更成本。**留作 future ticket**: 若主人在某天主动问「让 db:generate 恢复正常」再启动; 启动前需主人 ask_user 拍 (AGENTS §3 该做项「改了 migration 必跑 db:compat」同根 = 主人决策, 不 agent 自决)。 |

---

## ⓪ web admin 解冻 (2026-09-22 已拍板落地, ADR-0017)

- ✅ `src/app/admin/**` / `src/components/business/**` / `src/components/admin/**` 恢复活跃
- ✅ backend / schema 双线同步 (Flutter + web admin 同批更新, `pnpm type-check` 必过)
- ⚠️ 解冻 ≠ 重做: 存量页面不做大规模重构
- 功能归口: 销售侧 Flutter / 管理分析侧 web admin (不要求对齐)

---

## ① 原始加盟节点启动（Bootstrap Root）· ✅ 已落地（2026-09-21）

> **主人 2026-09-20 问**: 「一个新的团队或加盟树开始时，没有加盟者，也就没人能创建并放置加盟节点。
> 在不破坏现有的加盟节点放置需要三方确认的情况下，怎样启动原始加盟节点？」
> **主人 2026-09-21 拍板**: 「建根 = **先有账号**。admin 能建根, 但要用户**先注册**。」

### 结论（怎么在不破坏三方确认的前提下启动）

三方确认 = 发起人 + 新加盟商本人 + **目标父节点**。根节点**没有父节点** →
三方里有一方**物理不存在**（0 节点时更惨：连"发起人必须已加盟"这一条都不满足）。

所以建根**不进** `placement_requests` 状态机（硬塞 = 开一条「零确认即执行」的特例分支，
最容易被后续改动滥用），而是走 **admin 单方 + 审计留痕**，与既有两条豁免同源
（§6.5 管理员落位免多方确认 / §6.6 建号豁免）。**根一旦存在，后续节点照旧三方确认。**

同时**不加**"凭空造节点"能力：根必须挂到**已注册账号**（一个账号一个节点，`user.franchisee_id`），
因为"建号即强制建档"（§6.6）已经保证了账号 = 客户，节点背后必须是个真人。

### 落地清单

| # | 东西 | 位置 |
|---|---|---|
| 1 | `createRootForUser()`（校验 + `INSERT franchisee(path='',depth=0)` + `UPDATE user.franchisee_id` + 审计事务） | `src/lib/db/queries/admin-users.ts` |
| 2 | `GET /api/admin/users`（全部注册账号 + 全部加盟节点 + summary，手机号只回打码） | `src/app/api/admin/users/route.ts` |
| 3 | `POST /api/admin/users/[id]/root`（admin + `note` 必填 2-200 字） | `src/app/api/admin/users/[id]/root/route.ts` |
| 4 | APK「我的」→ 关于与帮助 → **用户管理**（仅 admin）→ 列表/图谱切换 + 「设为根节点」 | `flutter_app/lib/screens/admin_users_page.dart` · `admin_users_graph.dart` |
| 5 | 冒烟 13 项（含非管理员 403 / 二次建根 400 / 停用账号 400 / 审计留痕） | `scripts/smoke-bootstrap-root.ts` |
| 6 | 接口文档 | `docs/api.md` §15 |

### 拍板结果（原"待拍板问题"）

| # | 问题 | 结果 |
|---|---|---|
| B1 | 一个团队允许几个根？ | **允许多根**（多门店/多团队），根由管理员建；`rootCount` 在返回里 |
| B2 | 根能不能解除？ | 不能（现有 `createPlacementRequest` 已挡）；转移 = 换绑账号，另开条目 |
| B3 | 留不留凭据？ | 留：`created_by` + `note`（加密 `notes_encrypted`）+ `user` 表审计触发器 |
| B4 | 根的"团队"标识？ | 暂用 `store_id`（W5 RBAC 已有列），SaaS 阶段升级为 tenant |
| B5 | 建根入口放哪？ | APK「我的」（web admin 冻结中）—— 主人要在手机上就能建 |

### 同日追加（主人拍板: 节点必须有账号 + 管理员强改上层）· ✅ 已落地 2026-09-21

> 原话: ①「无账号节点为什么要存在? 不能禁止/消除无账号节点吗, **要成为节点首先必需有账号**。」
> ②「给管理员一个『**协商处理后强改上层**』的后台功能。」（承接"上层一旦有人不能撤换, 除非联系系统管理员协商处理"）
>
> ① 的三道闸 + 存量清理 + seed 根因修复 → **ADR-0014 §3.7** / **AGENTS §6.7**
> ② 的接口 / 子树搬迁 / 留痕 / Flutter 弹层 → **ADR-0014 §3.8** / **AGENTS §6.8** / `docs/api.md §15`
> 冒烟: `scripts/smoke-admin-reparent.ts`（**44 项全过**, 含拆栏那两条）; 巡检修: `scripts/audit-orphan-nodes.ts` +
> `scripts/audit-placement-integrity.ts`（点位父列 ≡ path/side/depth, `--strict`）

### 还没做（下一步可选）

- **换绑 / 解除根**：根账号换人（`user.franchisee_id` 重指）—— 需要主人拍板"历史节点数据怎么办"
- ~~`franchisee` 表没挂审计触发器~~ → ✅ 2026-09-21 已补 (`franchisee_audit`, 见 backlog ⑧)

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

> ⚠ **再踩一次 (2026-09-21, 会员标识任务)**: 跑 `dart run build_runner build --delete-conflicting-outputs`
> 失败时会**先把已提交的生成物删掉** (10 个 `.freezed.dart` / `.g.dart` → `git status` 全 `D`)，导致
> `flutter analyze` 瞬间 187 个 error。恢复: `git status --porcelain flutter_app | awk '$1=="D"{print $2}' | xargs git checkout --`
> **结论**: 在 build_runner 修好前，**不要**跑它；需要新字段就走手写模型（例: 会员标识任务里
> `CustomerWithFollowUp.isMember` 而不是改 freezed 的 `Customer`）。

---

## ③ 会员标识: 还没覆盖的界面 · ⏳ 待主人点名（2026-09-21）

> **已完成**: 自己头像 / 客户页图谱节点 + 图例计数 / 客户列表行 / 管理员用户管理页。
> 详细口径见 `docs/membership-billing-draft.md` §5.1.1。

**同类界面还没画会员标识**（要的话直接复用 `MemberCrown`，数据侧各加一个 `member`/`isMember` 字段）:
- 客户详情页顶部头像 (`GET /api/customers/[id]` **已**返回 `isMember`，只差前端画)
- 加盟商详情页 / 客户页图谱点节点后的详情弹层
- 跟进待办页 (`/follow-ups`) 的行头像
- 沙龙客人 / 邀请列表 (`modules/salon/**`)
- 「我推荐的人」(`my_referrals_page.dart`)

---

## ④ 死代码: 客户推荐图 (`CustomerGraphView`) · ✅ 已删 (2026-09-22, ADR-0015 Q4)

> `flutter_app/lib/modules/customer/widgets/customer_graph_view.dart` +
> `myCustomerGraphProvider` + `GET /api/customers/graph` **无人调用**（客户页「图谱」tab 画的是
> 加盟树 `franchise_tree_painter.dart`，路径完全不同）。
> **2026-09-22 主人拍「废弃」已删**: 上述三处 + `CustomerGraphNode`/`CustomerGraph` 模型 +
> 新建客户表单的「选择推荐人」均移除; `customer.referrer_id` 列保留仅为存量 (ADR-0004)。
> 「谁带来谁」看: `referral_reward` (账号推荐) / `franchisee.placement_parent_id` (点位父)。

---

## ⑤ 多根加盟树: `placement_path` 跨根不唯一 · ✅ 已落地（2026-09-21）

> **主人 2026-09-21 拍板**: 「**要支持多根**」→ 走**方案 A**（additive `root_id` 列）。
> 同时拍板**新增「往根部发展」方案**（向上认领上级, `kind=promote`）——
> 因为客户公司现实里已有固有加盟树, app 只是同步它, 而初始用户大概率是中间层。
> 落地清单 / 决策全文: **[ADR-0014](../adr/0014-multi-root-and-upline-claim.md)**;
> 变更: `CHANGELOG.md`; 冒烟: `scripts/smoke-upline-promote.ts`（**36 项全过**）。
>
> **落地摘要**:
> - `drizzle/0017_multi_root_promote.sql`: `franchisee.root_id` + 索引 + 递归 CTE 回填 + 预占索引收紧到 `kind='create'`
> - 5 处子树/归属判定加「同 `root_id`」限定（`admin-users` / `getPlacementTree` / `getFranchiseeTree` /
>   `getFranchiseeChildren` / `customer.ts` 加盟判定 / `rbac.ts`）
> - `kind='promote'`: 现根认领现实里的直接上级 → 上级成新根, 整棵子树下降一层; 双方确认; 往下生长的三方确认**不变**
> - Flutter: 客户图谱底部「认领上级」（仅树根可见）+ 待确认页 promote 文案
>
> **同日第二轮 5 条拍板已一并落地**（ADR-0014 §3.6）:
> ① 上层 = **点位父**（≠ 推荐码提供人）→ `getPlacementUpline` 按 path 认，不看 `referrer_id`
> ② 上层一旦有人**不能撤换**（无换上层入口，联系管理员协商）
> ③ 可认领**已在别的树里的节点**（`0018_placement_upline_fid.sql`，前提是她一层 2 个点位有空位）→ 两棵树合并
> ④ 我在上级的 **A线/B线 由上级自己挑**（发起免传 `side`，`decide` 接 `side`）
> ⑤ 图谱在「我」正上方新增**上层点位**那一格（有人画人 / 空着画虚线虚位「点此认领」/ 待确认画「待她确认」）
>
> ⬇️ 以下为**原始 recon 记录**（保留作决策背景, 结论以上文为准）

### 原始 recon（2026-09-21 上午）

> **怎么发现的**: 主人说「节点树可能有多个（不同加盟系统 / 同一系统的不同枝）」→ 我用
> `POST /api/admin/users/2/root` 在 dev 库里真造了第 2 个根（先用后回滚），第一次拉
> `/api/admin/users` 就发现 **节点行数翻倍**（33 → 35：`76`/`77` 各出现两次）。

### 问题（代码事实）

`franchisee.placement_path` 是**相对自己这棵根**的路径，根节点 path = `''`：

| id | name | referrer_id | placement_path |
|---|---|---|---|
| 75 | 杨望（根 1） | null | `''` |
| 142 | 预览受邀者（根 2） | null | `''` |
| 76 | SeedTest-李建国 | 75 | `L.` |
| 77 | SeedTest-王秀英 | 75 | `R.` |

于是任何「从根往下找子树」的写法，只要用 path 前缀/长度推导父子，都会**跨根串味**：

| 位置 | 写法 | 多根后果 |
|---|---|---|
| `admin-users.ts`（本轮我写的） | `p.placement_path = left(f.placement_path, len-2)` | **实测重复行**（`L.` 同时挂到两个根上）→ 已改 `p.id = f.referrer_id` ✅ |
| `franchisee.ts:545` `getPlacementTree` | 根 → `ne(path,'')` 取全部非根节点，再按 path 连父 | 根用户的「我的加盟网络」会把**别的树**当成自己的子树（还重复） |
| `franchisee.ts:467` `getFranchiseeTree` | 同一模式 | 同上（这个函数按 referrerId 建树，加载集大了但父链没错，主要影响子树判定/上下级） |
| `customer.ts:132-156` | `me.path='' AND f.path<>''` | 根用户按「我的加盟子树」筛客户 → **把别的树的客户也算进来** |

### 根因

schema 里**没有存"这个节点属于哪棵树"**：`placement_path` 只在根内唯一，`placement_side`
只说"占父的哪边"，`referrer_id` 是**推荐人**（≠ placement 父节点，见 `franchisee.ts:511` 注释）。
所以placement 父节点只能靠 path 推 → 多根必然歧义。

### 候选方案（待拍板）

| # | 方案 | 优点 | 代价 |
|---|---|---|---|
| **A（推荐）** | 加 **additive 列** `franchisee.root_id`（根的 franchisee.id；根自己 = 自己），建根时写、老数据一次性 backfill（按现有单根场景全部指向当前唯一根） | 不动现有 path 语义；`WHERE root_id = $1` 一把梭；符合 ADR-0004（加列 + nullable + DEFAULT 兼容） | 加 1 列 + 1 个 backfill 脚本；4 处查询要改 |
| B | 让 `placement_path` 带根前缀（`#75.L.R.`） | 不加列 | 要迁移所有历史 path（数据迁移，风险高），且 path 语义变 |
| C | 暂不支持多根（回到"一个系统只有一棵树"，多个门店用 store_id 表达） | 零改动 | 与主人刚拍板的「多棵树（不同加盟系统）」冲突 |

### 待拍板问题

| # | 问题 | 建议 |
|---|---|---|
| C1 | 走 A 还是 C？ | A（主人已明确要多棵树；A 是 additive，不破坏冻结期兼容） |
| C2 | 多根之后"我的加盟网络"（客户图谱）对根用户显示哪棵？ | 显示**自己那棵**（`root_id = 我的根`），别的树归管理员图谱看 |
| C3 | 客户列表「加盟」筛选对根用户 | 同上：只算自己树 |
| C4 | 什么时候做？ | 建议**下一次动 schema 时一起**（建根功能已能用，单根场景当前无 bug） |

### 已做（本轮）

- `admin-users.ts` 改 `referrer_id` 连父 ✅（并在注释里写清为什么不能用 path）
- 图谱多棵树的可辨识度（每棵标「第 N 棵」+ 拖动提示 + 「适应屏幕」按钮）✅
- 本条目**先记不改**：其余 3 处要等 C1 拍板（都是跨根可见性/归属问题，不能顺手改）


---

## ⑦ `referrer_id` 双重语义必须拆列 (点位父 ≠ 推荐人) · ✅ **已落地 (2026-09-21, migration 0019)**

> **背景**: `franchisee.referrer_id` 这一列现在**同时**承担两个角色:
> ① 「推荐人」(Flutter 加盟商详情页把它显示成「推荐人」卡片)
> ② 「点位父」( `placeNewFranchisee` 的槽位判定用它; `createFranchisee` 也把 `referrer_id` 写成落位父节点)
>
> 而主人 2026-09-21 已明确拍板: 「**『上层』= 点位父, 不一定是推荐码提供人**」—— 两者在业务上是**两件事**。
>
> **为什么现在必须做**: 管理员「协商处理后强改上层」(`POST /api/admin/nodes/[fid]/reparent`) 落地后,
> 为了让新上层那条线不出现"看着空、其实有人"(→ 新节点 path 撞车), 强改上层时**只能把 `referrer_id`
> 一起改**。后果 = 连带改写「谁推荐了她」这句话。原值在 `audit_log.changed_fields` 里可追, 但界面上已经错了。
>
> **拆法 (additive) —— 主人 2026-09-21 拍「拆」, 当天落地**:
> 1. ✅ migration `0019_placement_parent_id.sql`: 加列 + 索引 + 回填 (「path 去尾段 + 同 root_id」为主口径,
>    path 断链沿用 `referrer_id` 兜底) + `DO $$ ... RAISE EXCEPTION` 自检; **全程不动 `referrer_id`**
> 2. ✅ `placeNewFranchisee` 占位判定 + BFS 子节点查找改读 `placement_parent_id`; 开头加缺列保护 (人话报错)
> 3. ✅ `reparent` 只改 `placement_parent_id` (+ `placement_side`), 返回值带 `referrerTouched: false`
> 4. ✅ 用户可见口径: `GET /api/me` 的「我的上级」/ `countDirectDownline` / `rbac` 直接下线 → 点位父;
>    「推荐人」语义 (`getFranchiseeTree` / 图谱 `relation` / `?referrerId=` 显式过滤) 继续读 `referrer_id`
> 5. ✅ 冒烟: `smoke-admin-reparent.ts` 44 项 (含「强改上层后 `referrer_id` 不变」+ 推荐人≠点位父的落位 +
>    全库巡检 + `/api/me` 口径)
>
> **新增巡检**: `npx tsx scripts/audit-placement-integrity.ts --strict` (6 类结构不一致 + 同树 path 唯一)
>
> **Flutter 收口 (同日完成)**: 详情页「上级加盟商」卡改读 `placementParentId`
> (relation node payload 加字段 + `Franchisee` model 加字段 + 详情页改读; 已重建 Flutter web + 截图验证 ——
> 把 `referrer_id` 临时改成别人, 卡片仍显示点位父)
>
> **关联**: ADR-0014 §3.9 / §5 第 1 条; AGENTS §6.8

## ⑧ 审计触发器覆盖不全 · 🔧 待补（2026-09-21）

> **现象**: 做「管理员强改上层」时发现 `franchisee` 表**一行审计都没有** (19 个触发器里没它) ——
> 而这张库存的是整棵加盟树的 `placement_path` / `placement_depth` / `root_id` / `referrer_id`,
> 改一次动一整棵子树。本次已给 `franchisee` 补上 (`drizzle/audit_trigger.sql` 的 `franchisee_audit`)。
>
> **待办**: 全库过一遍「哪些表还没有 `*_audit` 触发器」, 按「这行数据改动要不要能查是谁改的」判:
> 字典 / 服务项 / 配置类要不要挂 (噪声 vs 价值)。CHARTER §3 红线摆在那, 但不必无脑全挂。

---

## ⑥ 手工 build 撞 flutter-web 守护进程 · 🔧 有绕行（2026-09-21）

> **现象**: 手工跑 `tools/build-flutter-web.sh --auto` 时断在编译阶段，两种报错轮流出现：
> ① `Target dart2js failed ... Internal Error: The compiler crashed when compiling this element`
>   （`.dart_tool/flutter_build/72d1c8b.../app.dill`）
> ② `IconTreeShakerException: Expected to find kernel file ... app.dill, but no file found`
>
> **根因**: 手工 build 与 `nuankebao-flutter-web-watch.service`（文件变了就自动重建）
> **共用**同一份增量目录 `flutter_app/.dart_tool/flutter_build/<hash>/` —— 两边同时写
> `app.dill` 就互相踩（改文件那一瞬间守护进程正好启动 = 必撞）。
>
> **绕行（已验证）**:
> ```bash
> systemctl --user stop nuankebao-flutter-web-watch.service
> python3 -c "import shutil; shutil.rmtree('flutter_app/.dart_tool/flutter_build', ignore_errors=True)"
> bash tools/build-flutter-web.sh --auto
> systemctl --user start nuankebao-flutter-web-watch.service
> ```
>
> **候选治本**: ① build 脚本自己加 `flock`（手工 build 时守护进程让路）；
> ② 守护进程改成调同一个脚本 + 同一把锁；③ 干脆只用守护进程，手工改完不 build 只等它。
> **关联**: 本项目已两次因「两个进程共用 Flutter 增量目录」翻车（另一次见 ② build_runner）。
