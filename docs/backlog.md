# 待办 / 技术债 Backlog

> 用途: 主人点名「记住这个任务，在完成上面全部任务后开始」的条目，以及过程里发现的技术债。
> 规则: 每条带 **背景 / 方案选项 / 待拍板问题 / 前置依赖**；做完移到 CHANGELOG 并在本文件标 ✅。

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

### 还没做（下一步可选）

- **换绑 / 解除根**：根账号换人（`user.franchisee_id` 重指）—— 需要主人拍板"历史节点数据怎么办"
- **`franchisee` 表没挂审计触发器**（只有 `user` 有）→ 建根只在 `audit_log` 留下 user 侧记录；
  加 `franchisee_audit` 触发器是独立小改动（见 `drizzle/audit_trigger.sql`）

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

## ④ 死代码: 客户推荐图 (`CustomerGraphView`) · ⏳ 待拍板删（2026-09-21）

> `flutter_app/lib/modules/customer/widgets/customer_graph_view.dart` (517 行) +
> `myCustomerGraphProvider` + `GET /api/customers/graph` **无人调用**（客户页「图谱」tab 画的是
> 加盟树 `franchise_tree_painter.dart`，路径完全不同）。
> 本次会员标识任务顺手给 `/api/customers/graph` 的节点加了 `member` 字段（保持口径一致），
> 但**没有**给这个 dead widget 画 UI —— 免得美化一段没人看的代码。
> **待拍板**: 删（`git rm` 3 处 + `docs/api.md` 对应小节）还是留作未来「客户推荐关系」视图的基础。

---

## ⑤ 多根加盟树: `placement_path` 跨根不唯一 · ✅ 已落地（2026-09-21）

> **主人 2026-09-21 拍板**: 「**要支持多根**」→ 走**方案 A**（additive `root_id` 列）。
> 同时拍板**新增「往根部发展」方案**（向上认领上级, `kind=promote`）——
> 因为客户公司现实里已有固有加盟树, app 只是同步它, 而初始用户大概率是中间层。
> 落地清单 / 决策全文: **[ADR-0014](../adr/0014-multi-root-and-upline-claim.md)**;
> 变更: `CHANGELOG.md`; 冒烟: `scripts/smoke-upline-promote.ts`（26 项全过）。
>
> **落地摘要**:
> - `drizzle/0017_multi_root_promote.sql`: `franchisee.root_id` + 索引 + 递归 CTE 回填 + 预占索引收紧到 `kind='create'`
> - 5 处子树/归属判定加「同 `root_id`」限定（`admin-users` / `getPlacementTree` / `getFranchiseeTree` /
>   `getFranchiseeChildren` / `customer.ts` 加盟判定 / `rbac.ts`）
> - `kind='promote'`: 现根认领现实里的直接上级 → 上级成新根, 整棵子树下降一层; 双方确认; 往下生长的三方确认**不变**
> - Flutter: 客户图谱底部「认领上级」（仅树根可见）+ 待确认页 promote 文案
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
