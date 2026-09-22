# AGENTS.md — 暖客宝 项目协作约定 (给 pi / Codex / 任何 agent)

> **本文件是项目操作层规约** (Operational Layer)。任何 agent 进入本项目时,**应先读元宪法** [`docs/CHARTER.md`](docs/CHARTER.md) **理解治理哲学与红线,再读本文件理解具体执行规则**。
>
> **版本**: v0.1.4
> **同步 CHARTER**: v0.1.4 (双域细化 + 底座模块化, 详见 CHARTER §4 + ADR-0007 + ADR-0008)
> **派生层**: 元宪法 → `docs/CHARTER.md`; 战略层 → `docs/adr/*`
>
> **阅读顺序**:
> 1. `docs/CHARTER.md` (L0 元层 —— 治理哲学 / 红线 / 域边界)
> 2. 本文件 (L2 操作层 —— 具体怎么做)
> 3. `docs/adr/*` (L1 战略层 —— 历史决策,按需)
>
> **章节引用约定**: 本文件每个 `## §X` 标题后标注 `(CHARTER §Y)`,对齐元宪法章节。

## §1. 项目 vibe (CHARTER §1 宗旨 + §2 原则 2/3)

**项目**: 暖客宝(NuankeBao)· 大健康行业销售人员的 CRM + AI 客户维护 + 养生记录系统

**用户群体**:养生保健 / 健康管理 / 康复养老 / 营养食品 / 健康生活方式 等大健康细分行业的**销售 + 客服人员**(中年女性为主,移动端重度使用)

**目标用户**:
- 主:大健康门店 / 品牌**销售 + 客服人员**(中年女性为主,移动端重度使用)
- 次:门店老板 / 店长(看报表 + 团队管理)

**视觉风格**:
- 简洁 + 温暖(养生行业气质)
- 移动优先,PC 端也要可用
- 不要 SaaS 风(避免传统 CRM 的销售漏斗 / 冷色调 / dashboard 风格)

**核心交互**:
- 一键录入:养生记录结构化表单(部位 / 状态 / 用料 / 效果)
- 客户画像:看一个客户 = 看到他的所有历史
- AI 辅助:跟进建议 + 话术生成(后期)

**反 vibe**:
- ❌ 不要传统 CRM 的销售漏斗(Kanban / pipeline)主界面
- ❌ 不要 dashboard 复杂图表(养生销售看不懂)
- ❌ 不要炫技动画
- ❌ 不要暗色主题(养生行业偏温暖)

## §2. 技术栈 (CHARTER §3.2 技术栈红线 + ADR-0001) (已拍板 2026-09-03)

```
- 前端:    Next.js 15 (App Router) + shadcn/ui + Tailwind CSS
- 后端:    Next.js Route Handlers (单体仓库,后期可拆 NestJS)
- ORM:     Drizzle (SQL-first, 比 Prisma 轻)
- 数据库:  PostgreSQL 16 + pgcrypto (字段加密) + pgvector (向量检索)
- 认证:    Auth.js v5 + 手机号验证码 (阿里云短信网关)
- AI:      MiniMax API (国内 endpoint, 假设 minimax = MiniMax)
- 部署:    Docker Compose, 主人自有物理服务器
- 监控:    Postgres 触发器审计 + OpenTelemetry + 简易 Grafana
- 包管理:  pnpm
- 语言:    TypeScript (strict)
- 测试:    Vitest (单元) + Playwright (E2E)
```

> 📚 **学习借鉴**: 我们借鉴 NocoBase / Twenty / Frappe / Vault / Oso / Formily 等成熟项目的设计思路与实现方法。详见 [`docs/references.md`](./docs/references.md)。
> **原则**: 借鉴思路 ≠ 复制代码 — 看懂设计, 重新实现; 引用代码片段时注明出处 + 协议允许。

## §3. pi 协作规则 (CHARTER §5 决策权 + §2 原则 6/7)

### 该做
- ✅ **每次开新 feature** → 先 `pi`,在 prompt 里描述 vibe,不要直接动手
- ✅ **小步快跑** → 一次只让 pi 实现一个 feature,不要一次堆 10 个
- ✅ **必须自己验收** → UI 类必须截图看,LIB 类必须跑通单测
- ✅ **git commit 要带上下文** → `feat(mood-tracker): 加滑块 + 曲线图`
- ✅ **数据敏感字段必须加密** → 健康状态 / 疾病史 / 联系方式 走 pgcrypto
- ✅ **任何数据库写都要走 audit log** → 谁改了什么
- ✅ **选端口前先检测** → 跑 `./tools/check-port.sh [PORT]` 确认空闲，避免撞主人其他项目
- ✅ **改了端口的 commit 必须经过 pre-commit hook** → `tools/pre-commit-port-check.sh` (安装: `ln -s ../../tools/pre-commit-port-check.sh .git/hooks/pre-commit`)
- ✅ **改 / 加 migration 前必跑 `pnpm db:compat`** → 检查 DROP / RENAME / ALTER TYPE 无 USING / SET NOT NULL 无 DEFAULT 等禁止模式。CI `db-compat` job 失败 = PR 阻断。详见 CHARTER §3.5 + ADR-0004
- ✅ **前端同步策略 (web admin 已解冻, v0.1.5 主人拍, 2026-09-22, ADR-0017)**:
  - **销售侧功能 (录入/拍照/跟进/客户详情)** → **仍以 Flutter APK 为准** (`flutter_app/`), 不必做 web 同名功能 (apk-first 不变)
  - **管理与分析功能 (报表/导入/审计/用量/团队管理)** → **web admin 为主** (`src/app/admin/**`), 不必做 Flutter 同名页
  - **Backend / API / schema 改动** → **双线同步** = Flutter service 必同步 + web admin client 同批更新, `pnpm type-check` 必须过 (flutter-only-sync 作废)
  - **不要求两边功能对齐**: 同一功能单一入口即可 (ADR-0017 第 1 条); 解冻 ≠ 重做存量 web 页面
  - **拍板来源**: 主人 2026-09-22 原话「"web admin 冻结中"这是个错误, 需要解冻结。新模块接入 web admin。」详见 CHARTER §4.4 + ADR-0017 (部分 Supersede ADR-0005)
  - **活跃目录** (v0.1.5 起): `flutter_app/lib/**` + `src/app/api/**` + `src/lib/**` + `src/middleware.ts` + `src/app/(auth)/login/**` + `src/app/admin/**` + `src/components/{admin,business,ui}/**`
  - **仍冻结** (独立机制, 与本次解冻无关): preview framework 9 路径 (AGENTS §9 + ADR-0009)
- ✅ **任务开始前必打 task-snapshot** → `bash scripts/task-snapshot.sh start <task-name>` (或依赖 `.pi/extensions/auto-task-snapshot.ts` 在第一条 user 消息自动打). 完整 SOP 见 §8.1. 改 / 加 ≥ 3 文件 或 跨域时**强制**先 snapshot.
- ✅ **改 / 加 migration 后必跑巡检 + `--strict`** (2026-09-21 立) → 拆栏后点位结构有两处真相
  (`placement_parent_id` 列 + `placement_path` 布局), 改过落位/改上层/建根后必跑
  `npx tsx scripts/audit-placement-integrity.ts --strict` (不一致 → exit 1). 另: 脚本里读 env 一律
  `import "./_env"` 放第一个 import (见 `scripts/_env.ts`), 不要用老的 `loadEnv()` 写法
- ✅ **单点问题修一处后必全仓扫一遍** (2026-09-15 主人立) → 修一个具体 bug (如整页刷新的 `<a>`) 后, 必须全仓 grep 同类问题 (如所有 `<a href>` / `window.location` / `router.push` / `<form action>`), 确认无其他遗漏才 commit. 单点修复 = 必复发, 跟 §5 登录循环 w14 三次复发同根.
- ✅ **改前端必起 dev server + 截图验证** (2026-09-15 主人立) → 任何 web admin / Next.js / Flutter web UI 改动, 必 `pnpm dev` 起服务 (port 先跑 `./tools/check-port.sh`) + 截图 (playwright / 浏览器) + 视觉验证, 不能只看 `tsc --noEmit` / `pnpm build` 就 commit. 详见 §5 w14 R12 puppeteer ≠ Flutter web UI 真行为 同根问题.

### 不该做
- ❌ **不要 sudo 改系统配置** — 这是 暖客宝 项目级别,跨用户操作要找主人拍
- ❌ **不要 git push** — 主人拍后再推 remote
- ❌ **不要写一堆 TODO 占位代码** — TODO 一定是真要做的,不是凑数
- ❌ **不要装 pip/npm 依赖不写进 package.json/requirements.txt**
- ❌ **不要把客户健康数据放第三方公有云** — 自有服务器是底线
- ❌ **不要用 AGPL 协议的底座** — 未来 SaaS 会被卡脖子
- ❌ **不要用 OpenAI API 直连** — 数据出境风险, MiniMax / 通义 替代

## §4. 文件组织约定 (v0.1.3 底座 + 模块化插件) (CHARTER §4 域划分)

> **双域共存架构** (v0.1.4 细化): **APK 域 = 生产域** (销售员 Flutter app, 独立 native dev cycle) + **WEB 域 = 开发域** (主人自用脚手架, 跑 production mode 永久). 两域**共存**, 不是 dev↔prod 切换. 详细功能清单 / 协作流程 / 边界规则: 见 [ADR-0008](docs/adr/0008-apk-web-domain-spec.md) (11 节, 400 行). 元宪法落地: [CHARTER §4.5](docs/CHARTER.md).

> **架构定位 (v0.1.3)**: 项目按"**双域 + 底座 + 模块化插件**"组织。
> - **APK 域** = 主产品 (销售员日常用的移动端), 物理位置 `flutter_app/lib/`
> - **WEB 域** = 开发项目 APK 用的脚手架 (开发 / 预览 / 部署 / 文档), 物理位置 `src/` + 周边
> 每个域内部 = **底座** (不可替换) + **业务模块** (可独立替换/改进)
> 详见 [`docs/CHARTER.md`](docs/CHARTER.md) §4 + [`docs/adr/0007-modular-architecture.md`](docs/adr/0007-modular-architecture.md)

```
nuankebao-agent/                              ← v0.1.3 底座 + 模块化插件
├── flutter_app/                ← ✅ 活跃 (APK 域 = 主产品)
│   ├── lib/
│   │   ├── core/               ← ★ APK 底座 (不可替换)
│   │   │   ├── router/         ← go_router 配置
│   │   │   ├── providers/      ← 共享 Riverpod providers
│   │   │   ├── http/           ← dio + 拦截器
│   │   │   ├── theme/          ← Material 3 养生绿
│   │   │   ├── models/         ← 共享 freezed models
│   │   │   └── widgets/        ← 共享 widgets
│   │   ├── modules/            ← ★ 业务模块 (可独立替换/改进)
│   │   │   ├── auth/           ← 登录
│   │   │   ├── customer/       ← 客户档案
│   │   │   ├── wellness/       ← 养生记录
│   │   │   ├── follow_up/      ← 跟进任务
│   │   │   ├── presentation/   ← 图谱(graph) + 列表(list) 合并
│   │   │   ├── salon/          ← ★ 沙龙 (v0.1.5 Phase 7 已实施; 旧名 meeting)
│   │   │   └── relation/       ← ★ 客户/加盟关系 (接口 + 默认实现)
│   │   ├── app.dart / main.dart
│   │   └── _deprecated/        ← 旧文件暂存, 待 Phase 1-7 迁移完后清理
│   └── android/                ← APK 构建产物
├── deploy/                     ← ✅ 活跃 (dev-modules/deploy 物理位置)
│   ├── backup.sh               ← 工业级备份 (PG + Media + GPG + 异地 + GFS)
│   ├── code_snapshot.sh        ← 代码快照 (dirty + untracked → 外置盘)
│   ├── restore_verify.sh       ← PG 月度演练 (decrypt → temp PG → 行数比对)
│   ├── install-systemd.sh      ← 一键装 systemd user timers + enable
│   ├── README.md               ← §10 备份 SOP 落地文档
│   └── systemd/                ← 6 个 unit (3 对 service+timer)
├── data/                       ← ⚠ gitignored (backup-key + backup-health + logs)
├── src/                        ← Next.js (WEB 域 = 脚手架)
│   ├── app/
│   │   ├── (auth)/login/       ← ✅ 活跃 (登录页, Flutter + Web 共用)
│   │   ├── admin/              ← ✅ 活跃 (web admin, 2026-09-22 解冻 ADR-0017)
│   │   ├── api/                ← ✅ 活跃 (Route Handlers, 两域共享; 含 api/usage + api/admin/usage)
│   │   ├── app-preview/        ← ✅ 活跃 (dev-modules/flutter-preview)
│   │   └── preview/            ← ✅ 活跃 (dev-modules/flutter-preview)
│   ├── components/
│   │   ├── ui/                 ← ✅ 活跃 (dev-modules/ui-kit)
│   │   ├── business/           ← ✅ 活跃 (web admin 业务组件; 含 usage-dashboard)
│   │   ├── admin/              ← ✅ 活跃 (sidebar/topbar/bottom-tab)
│   │   ├── auth/               ← ✅ 活跃 (login-form, Flutter 同步)
│   │   └── preview/            ← ✅ 活跃 (dev-modules/flutter-preview)
│   ├── lib/                    ← ✅ 活跃 (共享后端业务逻辑)
│   │   ├── db/                 ← Drizzle schema + migrations
│   │   ├── ai/                 ← MiniMax wrapper + prompt 模板
│   │   ├── usage/              ← 用量事件词表 + 清洗/校验 (v0.1.5)
│   │   ├── crypto/             ← pgcrypto 字段加密封装
│   │   ├── auth/               ← Auth.js 配置
│   │   └── audit/              ← 审计日志封装
│   ├── hooks/                  ← React hooks
│   └── styles/                 ← Tailwind + 全局样式
├── /home/tooyan/nuankebao-databackups/    ← ⚠ gitignored (项目外独立备份目录, 防 rm -rf)
│   ├── backup-key.gpg                  ← GPG 密钥 (chmod 600, 主副本)
│   ├── pg-backups/                     ← pg-*.dump.gpg (GFS 7 份)
│   ├── media/                          ← media-*.tar.zst.enc (GFS 7 份)
│   ├── backup-health/                  ← atomic JSON 状态
│   └── logs/                           ← backup.log / code-snapshot.log / restore-verify.log
├── /media/tooyan/<盘符>/nuankebao-*    ← ⚠ 异地盘副本 (3-2-1 异地策略, AGENTS §6.1; 当前 dev 机器未挂载, 路径待补)
├── tests/                              ← ✅ 活跃 (Vitest + Playwright)
├── docs/                       ← ✅ 活跃 (设计文档 + ADR + dev-modules 文档化视图)
│   ├── adr/                    ← 架构决策记录 (0001-0007)
│   │   ├── 0001-tech-stack.md
│   │   ├── 0002-data-model.md
│   │   ├── 0003-flutter-dev-workflow.md
│   │   ├── 0004-schema-evolution.md
│   │   ├── 0005-mobile-only-phase.md
│   │   └── 0007-modular-architecture.md  ← ★ 新增 (本架构)
│   ├── dev-modules/            ← ★ WEB 域开发模块文档化视图 (Phase 8 创建)
│   │   ├── README.md           ← 总入口 + 模块清单
│   │   ├── task-snapshot.md    ← scripts/ + .pi/extensions/
│   │   ├── references.md       ← docs/references.md
│   │   ├── ui-kit.md           ← components/ui/ + tailwind
│   │   ├── project-skill.md    ← AGENTS.md + .pi/ + .muse/
│   │   ├── architecture.md     ← CHARTER §4 + 架构图生成脚本
│   │   ├── flutter-preview.md  ← src/app/{app-preview,preview}/ + components/preview/
│   │   └── deploy.md           ← tools/ + deploy/ + systemd
│   ├── CHARTER.md              ← 元宪法 (v0.1.3)
│   ├── data-model.md           ← 数据模型详细
│   ├── phase-1-mvp.md          ← Phase 1 实施计划
│   └── security-compliance.md  ← 安全合规方案
├── tools/                      ← 脚本 (dev-modules/deploy 物理位置 + env-check + check-migration-compat)
├── scripts/                    ← ✅ 活跃 (dev-modules/task-snapshot 物理位置)
│   └── task-snapshot.sh        ← 任务级快照 (start/list/find/diff/rollback)
├── docker/                     ← Docker 配置
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── init.sql                ← pgvector + pgcrypto 初始化
├── .env.example                ← 环境变量示例
├── package.json
├── tsconfig.json
├── drizzle.config.ts
├── next.config.ts
└── AGENTS.md
```

### §4.5 模块化约束 (CHARTER §4.3 模块化规则)

**APK 域模块** (`flutter_app/lib/modules/<module>/`):
- ✅ **必须有**: `screens/` + `providers/` + `README.md`
- ⚠ **可选**: `widgets/` + `services/` (模块私有)
- ❌ **禁止**: 跨模块直接 import — 必须走 `core/` 底座接口
- ❌ **禁止**: 把业务逻辑写在 `core/` — `core/` 只放基建

**WEB 域开发模块** (物理位置不动, 文档化视图 `docs/dev-modules/<name>.md`):
- ✅ **模块清单已锁定** (7 个, per ADR-0007): task-snapshot / references / ui-kit / project-skill / architecture / flutter-preview / deploy
- ✅ **新增模块时**: 同步 `docs/dev-modules/<name>.md` README + 更新 `docs/dev-modules/README.md` 索引
- ⚠ **物理位置**: 维持现状 (`scripts/` + `docs/` + `.pi/` + `tools/` + `deploy/`), 不强制迁移

**客户/加盟关系模块** ★ (CHARTER §4.3 + ADR-0007 §详细方案):
- 📁 位置: `flutter_app/lib/modules/relation/`
- 🔌 接口: `RelationSystem` abstract class (7 方法契约)
- 🏭 默认实现: `FranchiseRelationSystem implements RelationSystem`
- 🔄 切换: 改 `relationSystemProvider` 默认值, 调用方零改动

**`lib/screens/profile_page.dart`** (WEB 域 admin 扩展页, v0.1.4 Phase 9 决策):
- 按 v0.1.3 §4.4.5 主人拍板 "override §4.4 freeze" 后保留
- **不归入 modules/customer/** (profile 是 web admin 扩展, 不是 APK 模块)
- **不归入 modules/profile/** (新建模块需主人 ask_user 拍板)
- 后续若要做独立模块 (profile), 主人拍板后再迁移
- 2026-09-18 同伴文件 (同在 `lib/screens/`, 同样**不是模块**):
  `profile_widgets.dart` (分区卡/条目/数字框) + `profile_sheets.dart`
  (编辑资料 / 检查更新 / 网络自检 弹层) + `about_page.dart` (路由 `/profile/about`)
  数据源 `GET /api/me` + `GET /api/app-version` (见 `docs/api.md §13`);
  本机设置 `core/providers/settings_provider.dart` (shared_preferences)

**`lib/_deprecated/`** (v0.1.4 Phase 9 真删评估):
- 1 周观察期已过 (v0.1.2 → v0.1.3 拍板 2026-09-07 → 现在 > 1 周)
- **可删**: git rm -r flutter_app/lib/_deprecated/ (per _deprecated/README.md)
- 但: 主人实际部署后, 若主理人未验证生产环境, 保留备份更稳
- **本次决定**: 暂不删 (per AGENTS §3 "不要 sudo 改系统配置" 类比), 主人 review 后手工删

**`src/app/preview/`** (v0.1.4 Phase 9 并入 app-preview):
- history: W19 早期版本, v0.1.3 重构后完整版在 `/app-preview`
- **本 commit**: `/preview` → redirect to `/app-preview` (307)
- 下次清理: 主人 review 后可删 `src/app/preview/page.tsx` 单文件 (留 1 周观察)

### §4.6 渐进迁移路线 (per ADR-0007 §实施路线图)

| Phase | 模块 | 时间 | 状态 |
|---|---|---|---|
| 0 | 架构基线 (CHARTER v0.1.3 + AGENTS §4 + ADR-0007 + CHANGELOG [0.5.0]) | 0.5 天 | ✅ |
| 1 | `modules/auth/` | 0.5 天 | ✅ |
| 2 | `modules/customer/` | 1 天 | ✅ |
| 3 | `modules/wellness/` | 1 天 | ✅ |
| 4 | `modules/follow_up/` | 0.5 天 | ✅ |
| 5 | `modules/presentation/` (graph + list 合并) | 1 天 | ✅ |
| 6 | `modules/relation/` ★ (抽接口 + 默认实现) | 1.5 天 | ✅ (调用方迁移 Phase 6.5 待做) |
| 7 | `modules/salon/` ★ (沙龙模块, 原占位 meeting → 完整实施) | — | ✅ v0.1.5 (2026-09-18) |
| 8 | `docs/dev-modules/` WEB 域文档化视图 | 1 天 | ✅ |
| 9 | CHARTER §4 / AGENTS §4 实地更新收尾 | 0.5 天 | 🔄 随各 Phase 增量更新 |

**每 Phase DoD**:
- [ ] `git mv` 历史可追 (`git log --follow <file>` 能查到旧路径)
- [ ] `flutter build apk` 成功 (Phase 1-7)
- [ ] 真机验证核心功能 (主人 + 1-2 个测试场景)
- [ ] 单测通过 (Phase 6 必须有 RelationSystem 单测)
- [ ] commit message 标注 phase 编号

> **Phase 7 沙龙实施记录 (v0.1.5, 2026-09-18)**: 主人拍板 5 项决策 —— 一级页名 **沙龙** (salon),
> 不建统一关系图谱 (用 `user` + `salon_invitation`, 后期用 RelationSystem 接口包装),
> 允许非 app 受邀者 (姓名+加密手机号), 带约机制先做「自报预计人数 + 主理人手动核对」简单版,
> 本次范围 = 完整方案 (列表+详情+创建+RSVP+带约任务+二级客人+动态/资料)。
> 落地: 6 张表 (migration `0008_rich_ink`) + 14 个 API route + `modules/salon/` (5 screen) +
> `tests/salon.test.ts` (18 例)。模块从 `modules/meeting/` 改名 (`git mv` 历史可追)。


## §5. 反模式 (前 3 个月踩过的坑) (CHARTER §7 反模式沉淀)

**记录中,边做边记**

- ❌ **不要用 Prisma** —— Drizzle 更 SQL-first,养生记录复杂 JSONB schema Drizzle 写起来更顺
- ❌ **不要把养生记录存成大文本** —— 必须结构化(部位/状态/用料/效果 分字段),AI 才能用
- ❌ **不要相信前端校验** —— 所有健康字段后端也要二次加密 + 校验
- ❌ **不要把客户手机号明文存** —— 即使"自己用",手机号也走 pgcrypto
- ❌ **不要 import lodash 全文** —— lodash-es 按需 import,养生系统体积敏感
- ❌ **拍脑袋设端口** —— 必须先跑 `./tools/check-port.sh [PORT]` 确认空闲，不要默认 3000/3001 (主人机器已被占用)
- ❌ **凭印象选端口** —— 不准凭"我以为"或"上次选的"设端口，必须每次检测。主人机器上 30+ 端口被占用，3000/3001/3002/3100/3400/8080/9090 都冲突
- ❌ **不要硬编码端口到文档** —— README/文档中端口号仅供参考，主人部署时需根据实际环境调整
- ❌ **migration 不向后兼容** —— `DROP COLUMN` / `DROP TABLE` / `RENAME` / `ALTER COLUMN TYPE` 无 `USING` 全部阻断 (CI 跑 `tools/check-migration-compat.sh`)。详见 CHARTER §3.5 + ADR-0004
- ❌ **migration NOT NULL 列不加 DEFAULT** —— 老 APK INSERT 失败 = W3 必崩。加 DEFAULT 或 nullable
- ❌ **删破坏性 migration 不写 down.sql** —— 跑挂后无回滚 = 主人手工处理。`drizzle/down/<同名>.sql` 必带 (CHARTER §3.5)
- ❌ ~~**mobile-only 阶段加 web admin 新功能** (v0.1.2 起, CHARTER §4.4)~~ —— **已作废 (2026-09-22 解冻, ADR-0017)**: web admin 恢复活跃, 管理与分析类新功能优先落 `/admin/*`; 销售侧功能仍以 Flutter 为准 (apk-first 不变)
- ❌ ~~**mobile-only 阶段同步 web admin client 类型/调用**~~ —— **已作废 (2026-09-22 解冻, ADR-0017)**: 恢复双线同步, backend / schema 改动后 Flutter + web admin 同批更新, `pnpm type-check` 必过
- ❌ **贴告示 ≠ 修复 (登录循环 w14 第三次复发, 2026-09-11)** — 在登录按钮上方加 banner 解释“为什么不能点”，不等于阻止了循环。**修法 = 让触发条件物理上不发生** (pointer-events:none / 服务端拦截 / API disable / 重构为不可能调用)，不是“让人自觉”。w14 第一次（R4 单点修）和第三次（加 banner）都犯这个错。详见 `docs/login-failure-triage.md §0` DoD。
  - ⚠ **主人 override (2026-09-12, CHANGELOG [0.4.1])**: /app-preview 完全删除 blockIframe 机制, iframe 永远可点. Banner 降级为纯 informational (sky 蓝, 恢复 dismiss 按钮). R12 登录循环改用其他方式 (puppeteer 拦截 / middleware / API disable, 待实施). 后果: iframe 里点登录 = 必崩循环. 主人拍接受这个风险. **此变更仅限 /app-preview, 不要外推到其他登录场景**. 后续补: post-mortem + AGENTS.md §5 沉淈特例条目.
- ❌ **修一个根因就 commit (登录循环 w14 三次复发, 2026-09-11)** — R1-R12 共 12 个已知根因（详见 `docs/login-failure-triage.md §2`）。任何登录 / auth / 拦截器 / middleware / Flutter web 相关改动，**必须全 12 项过一遍验证**，不能“修了 R4 就 commit, R6 下次再说”。单点修复 = 必复发。CI 阻断（待补 §6 checklist）。
- ❌ **puppeteer / curl 模拟 ≠ Flutter web UI 真行为 (w14 R12 发现, 2026-09-11)** — puppeteer `ctx.request.post()` 走 chromium 完整 cookie jar，模拟不到 dio web 平台 XHR 拿不到 Set-Cookie 头的真实情况。**"puppeteer 通过" ≠ "Flutter web 能用"**。任何“登录成功”的验证不能只看 API 状态码 / puppeteer 模拟，必须跑真 Flutter web UI（input → button click → 看 toast）+ 主人真手机 APK 验证。详见 `docs/login-failure-triage.md §4`。
- ❌ **Button asChild 套原生 `<a>` 触发整页刷新 (2026-09-15 发现)** — shadcn `Button asChild` 套 `<a href="/admin/x">` 时, 浏览器按超链接语义跳转, 整页 HTML 重新加载, sidebar/topbar 全部重挂载, 视觉上整页闪一下。**修法 = 必须 `Button asChild` 套 `<Link href>`** (next/link) 走 RSC 软导航, 只换 `<main>` 区域 children, sidebar/topbar 保留。例外 (仍用原生 `<a>`): `tel:` 协议 (按钮触发拨号) + `download` 属性 (浏览器原生下载) + `mailto:`。仓内已知误用点: `src/components/business/import-customers.tsx:272` 修复于 commit 717a289。验证手段: playwright + dev server, Network 面板看 `document` 请求数 = 0 + `fetch/xhr` 请求 (RSC `?_rsc=...`) > 0 = 软导航成功。
- ❌ **Next.js dev mode 下不要并发打 30+ API 请求 (2026-09-20 w21 调试 prewarm 失误)** — dev mode 懒编译下并发请求 = webpack 编译队列堆积 + 内存爆炸 (实测 1.4GB), 单路由响应从 <1s 退化成 30-60s, 必须 `systemctl --user restart nuankebao-nextjs.service` 才恢复。**修法 = 改完路径 / 重写 prewarm 类脚本后, 先 dry-run 用 `grep` / `sed -n` 验证 URL 路径, 再 curl 测单个路径, 不要 30+ 并发打**。教训: dev mode 架构性问题 (冷编译) 治本是换 `next start` production 模式; dev mode 仅适合「边改边看 HMR」, 不适合「批量验证脚本」。详见 CHANGELOG [0.5.4] + `tools/prewarm-dev-routes.sh` 头部注释。

- ❌ **组件主题里只写字号、不写 color → 真机白字 (2026-09-22 发现)** — 给 `ThemeData` 的组件样式
  (`chipTheme.labelStyle` 等) 设了**非 null 但没 color** 的 TextStyle, 等于整个**顶掉** Flutter 的组件默认色
  (`RawChip` 取样式 = `chipTheme.labelStyle ?? chipDefaults.labelStyle`; 默认色来自 M3: 未选 `onSurfaceVariant` /
  选中 `onSecondaryContainer`) → 文字 `color = null` → 引擎兜底色 = **白** (Android/Skia 实测 `#FFFFFF`)
  → 白卡片上根本看不见 (主人 2026-09-22 报的「字号档位 chip 白字」就是这个)。
  ⚠ Flutter web (CanvasKit) 兜底色是**黑** → `/app-preview` 看着"正常", **预览端验收必被骗**;
  只有真机 APK 看得出来。**修法 = 主题里每个组件 TextStyle 都显式写 color**;
  **测 UI 的 widget test 必须带到真主题** (`MaterialApp(theme: AppTheme.light())`) —— 不带主题 = 走 Flutter
  默认样式, 这类 bug 永远测不出来 (profile_page_test.dart 之前就是不带, 16 例全挂都发现不了)。
  同类坑: 主题里 `minimumSize: Size(double.infinity, …)` 的按钮放进 `Row` / `Wrap` (无界宽度) 会断言
  `BoxConstraints forces an infinite width` (debug 当场炸 / release 静默变形) —— 要有 `Expanded` / `SizedBox` 兜宽。
  详见 CHANGELOG (2026-09-22) + `flutter_app/test/chip_label_color_test.dart` + `flutter_app/lib/core/theme/app_theme.dart` chipTheme 注释。



- ❌ **拍「公开」之前先答「auth 保护什么」三问 (2026-09-21 apk-download 拍板)** — 想去掉 `auth()` 之前必答: ① 这端点返回的东西没登录也能看到/猜到吗 ② 真正敏感的数据/能力在哪 ③ 带宽滥用归谁管 (Cloudflare Tunnel / nginx 限速)。全答 "是/在哪/Cloudflare" → 公开可; 否则加 auth。**反面教材**: 惯性「什么接口都加登录」= 形式主义, 把推荐二维码形同摆设 (被推荐人还没账号扫码必然 401 → 主人 2026-09-21 拍"app 不准备上应用商店, 需要让被推荐人方便下载 apk" = 去 auth 的根因)。同根: §5 "贴告示 ≠ 修复" — "看起来保护了" ≠ 真的保护了。涉及端点: `src/app/api/apk-download/route.ts` + `src/app/api/apk-qr/route.ts` 公开化 (commit `bc8ca42`)。

- ❌ **pre-commit freeze hook 阻断 ≠ 默认 `--no-verify` 绕过 (2026-09-21 public/app/ 撞 preview-framework-freeze)** — 看到「🚫 Preview Framework Guard」阻断 banner 先停手, **先问「这文件本来就不该在 git 里吧?」**:
  - `public/app/` 在 9 个冻结路径里 = Flutter web 编译产物, 本质不该跟踪
  - build artifact = docker build 拷 working dir 进镜像 = git 不 track 也照样部署 (`deploy/prod-deploy.sh` 用 working dir 上下文)
  - **修法 = `git restore --staged <files>` + 留 working dir**, 不用 bypass, 不写 commit, deploy 仍生效
  - `--no-verify` 仅在「主人拍板要动 preview framework 本身」时用 (AGENTS §9.2), 图省事 = 复发温床。涉及路径: AGENTS §9.1 冻结清单第 9 项 + `tools/pre-commit-preview-guard.sh` 头部注释。

- ❌ **APK 分发走 volume mount, 不靠 commit 不靠 rebuild image (2026-09-21/22 两次 prod-deploy 后沉淀)** — Flutter 重 build 出新 APK 在 `flutter_app/build/app/outputs/flutter-apk/app-release.apk`, 但 prod `/api/apk-download` 服务的是容器内 `/app/public/downloads/NUANKEBAO-release.apk`:
  - `docker-compose.prod.yml` 挂 `./data/prod/downloads:/app/public/downloads:ro` (host → container)
  - `src/lib/apk.ts::apkCandidates()` 列 7 个候选, env > mtime 排序选最新 (md5 缓存按 mtime 失效)
  - **修法 = `cp flutter_app/build/app/outputs/flutter-apk/app-release.apk data/prod/downloads/NUANKEBAO-release.apk`**, 立即生效 (无需重 build 镜像 / 重启容器)
  - 验证: `curl /api/apk-download | md5sum` 应等于 `md5sum data/prod/downloads/NUANKEBAO-release.apk`
  - 反模式: 把 APK 编进 docker 镜像 = 每次发版都重 build 镜像 (90s+); commit APK 进 git = APK 不是源码 = 不该跟踪。同根: §5 "migration NOT NULL 列不加 DEFAULT" — 把运行时产物当部署真相。
## §6. 命名一致性 (全 nuankebao 化, 2026-09-07) (CHARTER §3.4 改名红线)

> **历史**:
> - 2026-09-05 §6.1-6.2 用户可见 / 代码标识符改名 (CHANGELOG [0.2.0])
> - 2026-09-06 §6.3 主人原拍"内部代号保留 bbt-", 仓库路径改名 (CHANGELOG [0.2.1])
> - 2026-09-07 **反转 §6.3**: 主人在 ask_user「命名一致性」选 all-nuankebao, 内部代号也全切. 详见 CHANGELOG [0.3.0].

### 6.1 全栈命名表 (统一 nuankebao, 2026-09-07 终态)

| 类别 | 名称 | 备注 |
|---|---|---|
| 产品名 | 暖客宝 (NuankeBao) | 用户可见 |
| 仓库路径 | `/home/tooyan/nuankebao-agent` | git 工作目录 |
| Docker container | `nuankebao-postgres` / `nuankebao-web` / `nuankebao-nginx` | compose 定义 |
| Docker volume | `nuankebao-postgres-data` | named volume |
| Docker network | `nuankebao-net` | bridge |
| systemd system | `nuankebao-stack.service` / `nuankebao-cloudflared.service` | /etc/systemd/system/ |
| systemd user | `nuankebao-nextjs.service` | ~/.config/systemd/user/ |
| 脚本前缀 | `tools/nuankebao-*.sh` | tools/ |
| 日志前缀 | `/tmp/nuankebao-*.log` | system + script |
| PG user/db | `nuankebao` / `nuankebao` | ALTER ROLE + ALTER DATABASE |
| Tunnel hostname | `nuankebao.tooyang.top` | Cloudflare DNS + tunnel ingress |

### 6.2 脚本内部变量 (历史命名, 不动)

> 工业界惯例: 脚本内部 `BBT_DIR` / `BBT_PORT` / `BBT_HOSTNAME` 等变量名保留 (改名只改默认值, 不改引用). kubernetes / docker 都有这种"内部名 vs 外部 brand"解耦. 切到 nuankebao 影响所有 backup / restore / guard 脚本, 风险大于收益.

### 6.3 ⚠ 强绑定 (任何一项变, 必须同步变其他)

```
[hostname] Cloudflare DNS + tunnel config  (/home/tooyan/.cloudflared/config.yml)
    ↓ 验证 / 影响
[AUTH_URL] .env                          (middleware getPublicBaseUrl() 用它做 fallback)
    ↓ 验证 / 影响
[APK base URL] flutter build apk --dart-define=NUANKEBAO_API_BASE=...
```

**只改其一必报错**:
- 改 hostname 但没改 AUTH_URL → OAuth callback URL 错 → 登录失败
- 改 AUTH_URL 但没重新 build APK → APK 仍指旧 hostname → 销售员登录失败
- 改 hostname 但没在 Cloudflare Dashboard 配 tunnel → 老 hostname 失效

切换 SOP: `docs/deploy.md` §6 (待补, 后续 ticket).

### 6.4 已变更 (部署默认值, 生产 deploy 时手工覆盖)

- Postgres default user/db: `nuankebao` (docker-compose.yml / .env 2026-09-07 in-place rename 完成)
- Postgres default password: `nuankebao_password` (生产 deploy 时改强密码)
- AUTH_URL fallback: `https://nuankebao.tooyang.top`
- 云上中转路径: `/opt/nuankebao/...`
- 云上密钥路径: `/etc/nuankebao/secrets/`

> 当前 dev 机器已 100% nuankebao 化. 生产 deploy 时按本表执行.

## §6.6 建号不变量 (账号 = 客户, 主人 2026-09-19 拍)

> **主人原话**: 「每个用户首先都肯定是另一个用户的客户」
> **拍板**: 「建号即强制建档 + 推荐码必填，推荐码作为用户账户最强身份识别码（admin/根可空）」
> **ADR**: [0013 账号 = 客户](./docs/adr/0013-account-customer-binding.md)

- ✅ **唯一建号入口** = `src/lib/auth/registration.ts::createAccountWithProfile()`
  —— 任何建号路径 (批量导入 / 未来注册页) **必须**走它; 直接 `db.insert(user)` = 违规
- ✅ 三条不变量: ① 每个账号有同手机号 customer 档案 ② 非 admin/根必须有推荐码 ③ 建号即分配自己的推荐码
- ✅ 推荐码**不写** `customer.referrer_id` (主人拍板 no_link: 账号推荐关系 ≠ 客户图谱老带新)
- ✅ **自己的客户档案不进自己的客户列表** (主人 2026-09-22 拍: 「自己不应该是自己的客户」):
  建号强制建档的后遗症 = 每个账号都有自己的 customer 档案 (语义 = 「她作为**别人**的客户」),
  客户列表 / 图谱 / `/api/me` 概览必须按手机号 hash 排除当前登录者自己那条
  —— 口径 = `src/lib/db/queries/customer.ts::selfCustomerExclusionSql` 一处, 三处共用, 勿各写各的
- ✅ 存量补齐: `scripts/backfill-account-customer-link.ts` (幂等, 支持 `--dry-run`)
- ✅ 冒烟: `scripts/smoke-registration.ts` (无码被拒 / 建档 / 码归属 / no_link / 409 / admin 豁免)
- ⚠️ 用户 ↔ 客户仍是**手机号 hash 约定, 无 FK 列** (后续可加 `user.customer_id`, additive)

### 6.6.1 主体模型不变量 (主人 2026-09-22 拍「全按建议」, [ADR-0015](docs/adr/0015-subject-model.md))

> 上文是「建号」这条线的规则; 下面是**整个主体模型**的全局口径 (系统视角 / 用户视角 / 图谱可见性 / 归属)。
> ADR-0015 共 16 项决策全部按建议通过; 下面对应条目里标 🔄 的是**已拍板但代码未落**。

- ✅ **一个自然人 = 一个邀请码** (唯一识别码; [ADR-0016](docs/adr/0016-identity-anchor.md), 2026-09-22 拍):
  账号面 `user` / 客户面 `customer` / 结构面 `franchisee` 都只是她的**可选面**, 不是三个独立的人。
  ⚠ **手机号不是身份** —— 只是联系方式 (可能换号 / 可能同号); 姓名可能重名。
  系统内部"同一个人"的连接一律走 **ID**: `user.customer_id` (账号↔档案) + `user.franchisee_id` (账号↔节点);
  撞号 → **识别提醒** (`409 PHONE_EXISTS` + 弹层), 不静默合并
- ✅ **巡检/修复**: `npx tsx scripts/audit-subject-integrity.ts [--fix]`
  (七项: 孤儿推荐码 / 无账号节点 / 缺档案 / 列连接缺失 / 列连接漂移 / 归属悬空 / 节点手机号漂移)
- ✅ **任何「谁的谁」的判定, 只允许读唯一真相源那一列, 禁止交叉** (Q3):

  | 问题 | 唯一真相源 |
  |---|---|
  | 谁把我带进 app (发会员天数/推荐奖励) | `referral_reward` |
  | 我挂在谁下面 (图谱 / 落位 / 上下级可见性) | `franchisee.placement_parent_id` |
  | 谁把我拉进加盟 (业务展示, **不参与任何判定**) | `franchisee.referrer_id` |
  | 客户「老带新」 | ❌ **废弃** (死链路已删, Q4) |

- ✅ **推荐码 ≠ 关系 (禁令)**: 推荐码职责 = **身份唯一性识别** + **推荐奖励凭证** + 建号必填;
  用我的码注册的人**不会**自动成为我的下级/下线 (Q10);
  若要新增「按推荐码查人」接口, **只返回姓名 + 打码手机号 + 会员标识 + 限流 + 审计** (不返回完整手机号)
- ✅ **客户归属 (Q11/Q12)**: `customer.owner_id` = 谁的客户列表 (migration 0020 ✅); `created_by` = 建档人(审计) —— **建档 ≠ 归属**;
  建号**不自动**归属推荐人 (§6.6 建号只建档), 推荐人在「我推荐的人」页**显式添加** (先到先得, 已有归属 → 明确报错)
- ✅ **「我的客户」= 归属我的人 ∪ 我的直推加盟** (点位父 = 我; Q2) —— 列表 / 胶囊计数 / `/api/me` 概览 / 行级过滤
  四处同一口径 (`src/lib/db/queries/customer-scope.ts` 单一真相源, 2026-09-22 落)
- ✅ **客户类型** = 加盟客户 (直推, 结构口径: 点位父=我) / 普通客户 / 种子客户 (`is_seed` 人工勾选):
  优先级 加盟 > 种子 > 普通; 种子/普通无法按「是否付费」自动派生 (ADR-0006: 全库无金额字段)
- ✅ **图谱可见性 (Q13)**: 系统管理员 = **全森林 + 未接入**; 普通用户 = 自己所在枝的**全部下层** + **上 3 层直系**;
  多根语义见 §6.8 / ADR-0014
  (2026-09-22 落: `getUplineAncestors(fid, 3)` + `/api/franchisees/me/tree` 返回 `uplines` +
   行级过滤同行 3 层 + Flutter 图谱画 3 格; 旧 `getPlacementUpline` 已删)
- ✅ **「孤儿节点」消歧 (Q14)**: 产品/文档口径 = **未接入** (没有加盟节点); §6.7 代码口径 = **无账号节点** —— 两者不得混用
- ✅ **admin 建号豁免建档 (Q5)**: `role='admin'` 不建客户档案 (推荐码照发); 根加盟商 / 普通 sales **必须**有
  (prod admin 现状 = 无档案, 合法; 2026-09-22 落)
- ✅ **沙龙客人不自动建档 (Q6)**: 提供「转为我的客户」入口 (🔄 待做)
- ✅ **`store` / `staff` 冻结 (Q8)**: 客户归属不带门店维度; CHARTER §3.6 红线已同步改为「必须有归属过滤」
- ✅ **角色真相源 = DB `user.role`** (步骤 0, 2026-09-22): `getRbacContext` 以 DB 为准 (session 里只作兜底) ——
  提权/降权立即生效; 老 token 无 `role` 字段也能自愈

### 6.6.2 账号生命周期 (初步机制, ADR-0016 D7, 主人 2026-09-22 拍「先有骨架, 后期完善」)

| 动作 | 含义 (三面口径) | 入口 |
|---|---|---|
| **停用账号** | 不能登录; **不删**客户档案、**不摘**加盟节点 (默认**不级联**) | `PATCH /api/admin/users/[id] {isActive:false, reason}` |
| **启用账号** | 恢复登录 (档案/节点一直在) | `PATCH /api/admin/users/[id] {isActive:true}` |
| **软删客户档案** | 移出客户列表; 账号、节点不受影响 | `DELETE /api/customers/[id]` |
| **软删加盟节点** | 退出图谱/落位; 账号保留但视为"未加盟" | 三方确认 unjoin / admin 强删 |

- guardrail: 不能停用**自己**; 不能停用**最后一个在用 admin**; 停用**必须写原因** (审计)
- 审计: `user` 表挂了 `user_audit` 触发器 → 停用/启用自动进 `audit_log`
- 后期完善 (未做): 级联规则 (停用账号时她的客户档案怎么办) / 离职交接 (归属转移) / 真删除

## §6.7 节点 ⇒ 账号 不变量 (加盟节点必须对应账号, 主人 2026-09-21 拍)
> **主人原话**: 「无账号节点为什么要存在? 不能禁止/消除无账号节点吗, **要成为节点首先必需有账号**。」

- ✅ **唯一口径** = `src/lib/db/queries/franchisee-account.ts`
  - 新建节点前必过 `resolveNodeAccount(tx, { referralCode, phoneHash })` —— **优先按邀请码找账号**
    (ADR-0016 D1/P6; 找到后节点姓名/手机号直接取自账号); 没有 active 账号 → 抛人话错误, 事务回滚
    (`requireAccountForNode` 降级为存量兼容: 只给手机号时用)
  - 建完必过 `assertNodeHasAccount(tx, fid)` (兜脏数据 / 并发停用; 失败即回滚)
  - 三条建节点路径都已接入: `createFranchisee` (老 `POST /api/franchisees`) / 三方确认 `create` / `promote`
- ✅ **注册自愈** (`adoptOrphanNodeForNewAccount`, 在 `registration.ts` 建号事务内):
  新账号手机号命中"没账号的既有节点" → **自动绑上**, 不新建重复节点
- ✅ **巡检 / 处理**: `npx tsx scripts/audit-orphan-nodes.ts`
  (默认只报清单 / `--bind` 补账号 / `--prune` 软删**没有下线**的孤儿; 有下线的必须人工处理)
- ❌ **禁止** 直接 `db.insert(franchisee)` 或绕过 `franchisee-account.ts` 建节点
- ❌ **禁止** seed / 脚本 / 一次性任务 造"先建节点、后不管账号"的数据
  (`scripts/seed-test-data.ts` 2026-09-21 已改: **每个节点先建账号再建节点**;
  历史那 29 个孤儿是这么来的, 已用 `--bind` 补齐)
- ⚠️ **没账号的节点不能被搬**: 既当不了上层, 也上不了「管理员强改上层」—— 逼着先解决账号

## §6.8 加盟树结构改动 (含管理员「强改上层」, 主人 2026-09-21 拍)

> **主人原话**: 「『上层』= 点位父 …… **上层一旦有人不能撤换, 除非联系系统管理员协商处理**」+「给管理员一个『协商处理后强改上层』的后台功能」

- ✅ **用户侧零入口**: 上层 = `placement_path` 去尾段 + 同 `root_id` 推出; 上层一旦有人, 用户自己不能撤换
- ✅ **管理员唯一例外通道** = `POST /api/admin/nodes/[fid]/reparent`
  (仅 `role=admin`; `reason` 必填 2-200 字 → 加密备注 + `audit_log`)
- ✅ **不塞进三方确认状态机** (`placement-requests`): 三方确认的价值 = 三方都点头, 本功能的前提正是三方谈不拢;
  硬塞会给「单方即执行」开分支 (同建根 `POST /api/admin/users/[id]/root` 的理由)
- ✅ **改一次动整棵子树**: `placement_path` / `placement_depth` / `root_id` (+ 顶层节点的
  `placement_parent_id` / `placement_side`) —— 不是只改一行
- ✅ **拆栏终态 (主人 2026-09-21 拍「拆」, migration 0019)**: `referrer_id` = **推荐人** (谁把她拉进来的),
  `placement_parent_id` = **点位父 / 上层点位** (她挂在谁下面) —— 两栏各记各的, **改上层绝不改写推荐人**:
  - 落位算法 (`placeNewFranchisee`) 的占位判定 / BFS 一律读 `placement_parent_id`
  - 「推荐人那侧满了 → BFS 顺延到别人名下」时两栏本来就该不同 (不是 bug)
  - 结构口径 (`countDirectDownline` / `rbac` 直接下线 / `GET /api/me` 的「我的上级」) 都读点位父
  - 巡检: `npx tsx scripts/audit-placement-integrity.ts --strict` (点位父列 ≡ path/side/depth + 同树 path 唯一;
    改过点位/结构代码后必跑)
- ✅ **`franchisee` 表必须有审计触发器** (`drizzle/audit_trigger.sql` 的 `franchisee_audit`;
  2026-09-21 补, 之前这张表一行审计都没有)
- ✅ **两栏分家 (旧「已知取舍」已解决)**: 早先 `franchisee.referrer_id` 一栏干两份活 (推荐人 + 点位父),
  强改上层只能连带改写「谁推荐了她」。主人 2026-09-21 拍「拆」→ 加 `placement_parent_id` 专记上层点位
  (migration 0019, 纯 additive + 回填 + 自检 abort), `referrer_id` 从此只记推荐人。
  - `adminReparentNode` 返回值带 **`referrerTouched: false`** (可断言的不变量), 冒烟已在断言
  - 落位算法开头有**缺列保护**: 本树若有 `path ≠ ''` 却 `placement_parent_id IS NULL` 的活节点 → 当场人话报错
  - ✅ Flutter 一并收口: 详情页「上级加盟商」卡读 `metadata['placementParentId']`
    (relation payload + `Franchisee` model 都加了该字段); 落位预览 `getAvailablePosition` 同口径
  - 详见 ADR-0014 §3.9

## §6.5 系统管理员账号 (长期保留, 主人 2026-09-19 拍)

> **主人原话**: 「长期保留系统管理员账号 admin，生产环境也要保留」

- **定位**: 管理员账号是**永久设施**（不是临时测试账号）—— dev 机器 + 生产环境都必须有 `role='admin'` 账号
- **生产管理员手机号**: `19957347866`（姓名 `管理员`, 主人 2026-09-19 拍; 也写在 `.env.example`）
- **保证**: `pnpm db:ensure-admin`（幂等; `ADMIN_PHONE=... ADMIN_NAME=...` 可配）
  - 不存在 → 新建 (`role='admin'`); 已存在 → 只抬 role, 不动其他字段
- **部署/灾备必跑**: 生产部署后 + 备份恢复后各跑一次（见 `docs/deploy.md §7.5`）
- **业务依赖**: 加盟落位「三方确认」只有**已加盟用户**或**系统管理员**能发起;
  管理员发起**免多方确认**（直接生效, `verified_by='admin'`）且不受「只能自己子树」限制
- **安全**: 生产环境不设 `DEV_SKIP_AUTH` / `DEV_LOGIN_ANY_USER`; 建议管理员账号与业务加盟商身份分离

## §7. 当前进度 (CHARTER §8 路线图)

- [x] 项目骨架 + git init
- [x] 工具链自检 (tools/check-env.sh)
- [x] **vibe / 技术栈拍板** (2026-09-03) ← 本次
- [x] **技术栈定稿** (Next.js + Refine + Postgres) + 自建决策复核
- [x] **学习借鉴清单** (NocoBase / Twenty / Frappe / 等) → `docs/references.md`
- [x] ADR-0001 技术栈选型
- [x] ADR-0002 数据模型
- [x] tech-stack-v0.1.md 完整依赖清单
- [x] Phase 1 MVP 计划文档
- [x] 安全合规方案
- [ ] **W1: 项目骨架 + Docker + Next.js + Drizzle + Auth.js** (等主人"开始" 触发)
- [x] **W1 实施完成** (2026-09-03) — 30+ 文件, 详见 `docs/w1-implementation.md`
- [x] **备份脚手架内置** (2026-09-08) — `deploy/` 完整备份栈 + 6 个 systemd timer 已装已启. 详见 `deploy/README.md` §10 + `dev-domain-backup` SOP
- [x] **项目改名** BBT → 暖客宝 (2026-09-05) — 详见 CHANGELOG [0.2.0]
- [ ] **W2-3: 数据模型 + Flutter 移动端 + 字段加密 + 审计** (web admin 已解冻, 双线同步, CHARTER §4.4 v0.1.5)
  - Drizzle schema 完整化 (CHARTER §3.5 红线)
  - Flutter 12 screen 真机验收 + native 验证 (拍照 / SQLite / 推送)
  - schema / API 改动双线同步 (Flutter + web admin, `pnpm type-check` 必过)
  - ✅ **用量采集模块已落地** (2026-09-22): migration 0023 + `/api/usage/events` + `/admin/usage` + Flutter `core/telemetry/`
- [ ] **W4: Flutter 移动端报表 + 内测** (web admin 报表已解冻, 可并行)
- [ ] W5-6: 部署自有服务器 + 备份 SOP + Flutter APK 销售内测
  - ⏰ 用量数据 (`/admin/usage` + `scripts/usage-report.ts`) 是 W6 拍板的真实依据 (而非回忆)
  - ✅ **web admin 已解冻** (2026-09-22 主人拍板, ADR-0017) — 后续按 §4.4 v0.1.5 双线同步开发
  - ⏰ 回头修订 `docs/CHARTER.md` §4 域边界 (AI 域细化 + 实际边界图),见 CHARTER §10.3.1
- [ ] Phase 2: AI Copilot (MiniMax API) — 销售侧 Flutter 优先; 用量模块提供真实使用数据支撑决策
- [ ] Phase 3: SaaS 化 (多租户) — 解冻后 web 与 Flutter 并行

## §8. 任务级快照 SOP (CHARTER §7 治本 + 借鉴 sales-ai W8)

> **设计源**: `~/.muse/skills/scaffold-task-snapshot/SKILL.md` (canonical 文档, 2026-09-05 v1.0)
> **借鉴实现源**: `sales-ai/scripts/task-snapshot.sh` + `sales-ai/.pi/extensions/auto-task-snapshot.ts`
> **装入时间**: 2026-09-13 (commit f58964d / 757b7fa / f444bc9)

### §8.1 task-snapshot 使用 SOP

#### 8.1.1 何时打 snapshot (强制 / 建议 / 不需要)

| 场景 | 行为 | 备注 |
|---|---|---|
| **改动 ≥ 3 文件 或 跨域** | **强制**先 `task-snapshot.sh start <name>` | agent 自动任务也算 |
| **数据库 migration 改 / 加** | **强制** (CHARTER §3.5 红线) | 配合 `pnpm db:compat` |
| **配置 / 部署文件改 (deploy/ + docker/ + .env.example)** | **强制** | deploy 一改 backup 脚本就受影响 |
| **AGENTS.md / CHARTER.md / ADR 改** | **建议** | 历史治理变更可回滚 |
| 单文件 typo / 注释 / lint fix | 不需要 | 粒度太粗 |
| agent 已经在跑 (turn_start hook 已自动打) | 不需要手动 | extension 自动挡 |

#### 8.1.2 5 subcommand 速查

```bash
# 任务开始前
bash scripts/task-snapshot.sh start <task-name>     # git tag pre-<name>-<sha> + dirty diff 兜底

# 任务中查询
bash scripts/task-snapshot.sh list                  # 最近 10 个 snapshot
bash scripts/task-snapshot.sh find "2 days ago"     # 按时间筛选
bash scripts/task-snapshot.sh diff <tag-or-prefix>  # 预览会改什么

# 错了回滚 (主人拍)
bash scripts/task-snapshot.sh rollback <tag-or-prefix>  # ⚠️ HEAD detached + restart nuankebao-* service
```

**约束** (scaffold-task-snapshot SKILL.md §7):
- task-name 仅允许 `[a-zA-Z0-9._-]`
- snapshot commit 用 `--no-verify` (元提交, 不该被 pre-commit CHARTER 阻拦)
- rollback 前**必看** `cat .git/snapshots/<tag>.diff` 确认 dirty 真正被备份
- 同一任务内连续改动不需要重复 snapshot (粒度是任务, 不是 commit)

#### 8.1.3 auto-snapshot extension (pi hook 自动挡)

`.pi/extensions/auto-task-snapshot.ts` 已注册到 `.pi/settings.json`, 启动 pi 时自动加载。两个 hook 协作:

| Hook | 触发时机 | 行为 |
|---|---|---|
| `turn_start` | session 第一条 user 消息 | 自动打 `pre-auto-<task-slug>-<sha>`, 5 分钟内去重 |
| `agent_end` | agent 说完话 | 自动 commit working tree 改动 (`[pi] <agent 最后一句话前 50 字符>`) |

**前提**: cwd 必须在 git 仓库里, 否则 console.error 警告 (UI notify 提示 `git init`).
**依赖**: `@earendil-works/pi-coding-agent` (pi-coding-agent 全局自带, 不入 nuankebao/package.json, 跟 sales-ai 一致).

#### 8.1.4 与每日全量快照的分工

| 机制 | 触发 | 范围 | 用途 | 脚本 |
|---|---|---|---|---|
| **每日全量备份** (PG + Media) | systemd timer 03:00 | tar 整个项目 | 灾难恢复 (硬盘挂/系统炸) | `deploy/backup.sh` |
| **每日代码快照** (整仓 tar) | systemd timer 04:00 | tar .git + dirty | 每日异地盘 | `deploy/code_snapshot.sh` |
| **任务级快照** (本机制) | 任务开始 (agent 自动 / 手动) | git tag + diff dump | 开发回滚 (agent 改错/想撤销任务) | `scripts/task-snapshot.sh` + `.pi/extensions/auto-task-snapshot.ts` |
| **月度 PG 演练** | systemd timer 月第一周日 04:00 | decrypt → temp PG → 行数比对 | 验证备份可恢复 | `deploy/restore_verify.sh` |

#### 8.1.5 与 nuankebao 现有规范的红线对齐

- ✅ **不改 sales-ai 借鉴策略** — AGENTS §3 原则 8: 借鉴思路不复制代码; 但 `task-snapshot.sh` / `auto-task-snapshot.ts` 是机械化 SDK 包装, 不重写 (重写风险大 + 价值低)
- ✅ **rollback 是 L3 决策** — 必须主人拍, agent 不能擅自 rollback (HEAD detached 危险, 跟 muse-snapshot SKILL.md 一致)
- ✅ **rollback 后需重启 nuankebao-* service** — 当前 dev 机器 systemd --user 实际有 `nuankebao-nextjs.service`; 部署栈启后还会多 `nuankebao-stack.service` 等
- ⚠ **pre-commit hook 与 snapshot 互不干扰** — snapshot commit 用 `--no-verify` 跳过 hook (元提交); 后续 commit (含 feature commit) 走正常 hook 路径 (AGENTS §3 该做项"改了端口必须经过 hook")
- ⚠ **代码快照 vs 任务快照不重叠** — `deploy/code_snapshot.sh` 每日 04:00 全量 tar; `scripts/task-snapshot.sh` 任务粒度 git tag. 两者职责互补 (见 deploy/README.md §10.10)

#### 8.1.6 故障排查

| 症状 | 根因 | 修复 |
|---|---|---|
| `bash scripts/task-snapshot.sh list` exit 1 + "不在 git 仓库内" | cwd 没在 git 仓库 | `git status` 验证; 不在仓库就 `cd <nuankebao-agent>` |
| `auto-snapshot extension` 不触发 | cwd 没在 git 仓库 或 pi 没读 `.pi/settings.json` | `git rev-parse --git-dir` 验证; `ls .pi/settings.json` 验证 |
| `rollback` 后 systemd service 没重启 | SERVICES 数组为空 (systemctl --user 找不到 nuankebao-* + 没 git config 兜底) | `git config task-snapshot.services "nuankebao-nextjs.service"` 显式配置 |
| `.git/snapshots/<tag>.diff` 没生成 | 工作树在打 snapshot 时已干净 (无 dirty 改动) | 正常, 不需要 diff 兜底 |
| `git apply` 失败 (rollback 时) | diff 与 working tree 冲突 | 手动 `less .git/snapshots/<tag>.diff` 看具体冲突; 或 `git checkout HEAD -- .` 强覆盖 |

#### 8.1.7 维护说明

- **canonical 文档**: `~/.muse/skills/scaffold-task-snapshot/SKILL.md` (改这里前先读)
- **sales-ai 实现源**: 同步反映到本项目 (mechanical 镜像, 改 systemd glob + 顶部注释即可)
- **muse-snapshot 替代**: 如果未来想用 Python 封装 (smolagents style), 见 `~/.muse/skills/muse-snapshot/SKILL.md`, 但需加 Python venv 依赖
- **后续 ticket (待补)**:
  - `docs/login-failure-triage.md` 同步加一行引用 §8.1 (login 循环 w14 复盘文档, 现在缺 task-snapshot 引用)
  - `deploy/install-systemd.sh` 是否要追加 task-snapshot 钩子? (systemd 不调 git, 应该是 hooks / 守护进程范畴, 暂不)
  - CHANGELOG.md [unreleased] 段: "v0.1.3 — 加任务级快照机制 (commit f58964d + 757b7fa + f444bc9)"

### §8.2 验收清单 (新装 / 改 / 排错后必看)

- [ ] `bash scripts/task-snapshot.sh list` exit 0
- [ ] `bash scripts/task-snapshot.sh start test-001` 退出 0 + 输出 `✅ 任务快照: pre-test-001-<sha>`
- [ ] `bash scripts/task-snapshot.sh diff test-001` 显示 diff stat
- [ ] `bash scripts/task-snapshot.sh rollback test-001` 干净回滚 (无 dirty 残留)
- [ ] `git tag -l 'pre-*'` 看到 tag 列表
- [ ] `ls .git/snapshots/` 看到对应 .diff 兜底文件 (如有 dirty)
- [ ] `cat .pi/settings.json` 看到 `extensions: ["./extensions/auto-task-snapshot.ts"]`
- [ ] 在 nuankebao-agent cwd 启动 pi, 发第一条 user 消息, 看到 `🔖 Auto-snapshot: auto-...` notify
- [ ] agent 说完话后 `git status` 显示 `nothing to commit, working tree clean`

## §9. 预览框架冻结 (Preview Framework Freeze) (CHARTER §7 反模式沉淀 + ADR-0009)

> **生效**: 2026-09-16 主人拍板 (CHANGELOG [0.5.2], ADR-0009).
> **基线**: `baseline-preview-v0.1.4-280f5fa` (commit `280f5fa`).
> **保护**: `tools/pre-commit-preview-guard.sh` 已装 (`.git/hooks/pre-commit` symlink).
> **测试**: `pnpm test` 跑 `tests/preview-framework-snapshot.test.ts` + `pnpm test:e2e` 跑 `e2e/preview-smoke.spec.ts`.

### §9.1 红线 (一图概览)

```
预览框架 9 个路径 = 冻结 (baseline-preview-v0.1.4-280f5fa):

  src/app/app-preview/             ← 主预览页 (Next.js page + iframe)
  src/app/preview/                 ← /preview → /app-preview 307 redirect 兜底
  src/components/preview/          ← PreviewFrame + FlutterWebLoginBanner (2 个组件)
  tools/build-flutter-web.sh       ← 一键 build + sync (编译产物 → public/app/)
  tools/dev-app-proxy.py           ← Flutter web dev server 反代 (?dev=1 路径核心)
  tools/install-dev-app-proxy.sh   ← dev-app-proxy.py 一键安装 (systemd user)
  tools/install-flutter-dev-tunnel.sh  ← cloudflared path rule 安装
  tools/start-flutter-dev.sh       ← Flutter web dev server 启动器 (后台/前台/stop/status)
  public/app/                      ← Flutter web 编译产物 (git tracked)

不在冻结清单的相邻文件:
  ❌ flutter_app/lib/**           (业务源码, 改业务 ≠ 改 preview)
  ❌ src/app/(admin)/             (已 freeze-keep, 跟本机制独立)
  ❌ src/components/business/     (WEB admin 业务组件)
  ❌ tools/pre-commit-preview-guard.sh  (guard 自身, 改它要走 §9.3 SOP)
  ❌ docs/dev-modules/flutter-preview.md (治理文档, 可演进)
  ❌ tests/preview-framework-snapshot.test.ts + e2e/preview-smoke.spec.ts (测试自身)
```

### §9.2 违规 = 立即阻断

任何 commit 修改上面 9 个路径中**任一**文件, `pre-commit-preview-guard.sh` 立即 **exit 1**:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚫 Preview Framework Guard: 检测到预览框架文件被修改
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  - src/components/preview/preview-frame.tsx

预览框架已冻结 (baseline-preview-v0.1.4-280f5fa).
修改前必读: docs/adr/0009-preview-framework-freeze.md §3 改前 SOP

如确认必要 (主人拍板后), 用 --no-verify bypass:
  git commit --no-verify -m 'fix(preview): ...'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### §9.3 改前 SOP (强约束, 不是禁止)

1. **ask_user 拍板** — 改 preview 框架**不**是 agent 自动决策, 必须主人 ask_user 拍.
   - ❌ 禁止"顺手优化 preview CSS"
   - ❌ 禁止"agent 自动任务改了 preview banner 文案"
   - ✅ 触发场景: 主人显式升级 / W19+ 大版本 / 业务模块深度联动
2. **跑测试看 baseline 状态** — `pnpm test tests/preview-framework-snapshot.test.ts` 必须 pass
3. **现场验证** — `bash tools/check-port.sh 3003` + `pnpm dev` + 浏览器开 `/app-preview` 看 preview 稳
4. **commit 显式声明** — 两种方式选一:
   - `git commit --no-verify -m "fix(preview): ..."` (推荐, 简单)
   - `git commit -m "[preview-bypass] fix(preview): ..."` (留痕)

### §9.4 应急解冻 (preview 已挂, 来不及走 §9.3)

详见 [ADR-0009 §4](../docs/adr/0009-preview-framework-freeze.md#4-应急解冻-emergency-unfreeze).

速查:

```bash
# 单文件回滚
git checkout baseline-preview-v0.1.4-280f5fa -- src/components/preview/preview-frame.tsx
git commit --no-verify -m "fix(preview): 紧急回滚 preview-frame.tsx 到 baseline"

# 整 framework 回滚
git stash push -m "preview-emergency-$(date +%s)"
git checkout baseline-preview-v0.1.4-280f5fa -- src/app/app-preview/ src/app/preview/ src/components/preview/ tools/build-flutter-web.sh tools/dev-app-proxy.py tools/install-dev-app-proxy.sh tools/install-flutter-dev-tunnel.sh tools/start-flutter-dev.sh public/app/
git add -A
git commit --no-verify -m "fix(preview): 紧急回滚整个 preview framework 到 baseline-preview-v0.1.4-280f5fa"
```

**应急解冻后强制**: 24h 内写 `docs/preview-emergency-postmortem-<date>.md` + 主人 review + AGENTS §X 加新反模式条目.

### §9.5 与其他规则的关系

| 机制 | 关系 |
|---|---|
| **task-snapshot** (§8.1) | 改 preview 框架 = 跨域 + ≥3 文件 → 强制先 `task-snapshot.sh start preview-XXX` |
| **CHANGELOG [0.5.2]** | 任何 preview framework bypass commit 必须同时更新 CHANGELOG, 否则 PR 阻断 |
| **CI `pnpm test` / `pnpm test:e2e`** | preview-framework-snapshot.test.ts + preview-smoke.spec.ts 是 gate, fail = 不收 |
| **CHARTER §7 反模式沉淀** | 本机制是 W14 R12 三次复发的"治本沉淀", 写在这里是反模式沉淀的代表案例 |
| **ADR-0005 web admin freeze-keep** | 平行机制 (web admin 冻结 vs preview 冻结), 各自独立 |

### §9.6 验收清单 (新装 / 改 / 排错后必看)

- [ ] `git tag -l 'baseline-preview-*'` 看到 `baseline-preview-v0.1.4-280f5fa`
- [ ] `ls -la .git/hooks/pre-commit` 看到 symlink → `../../tools/pre-commit-preview-guard.sh`
- [ ] `cat tools/pre-commit-preview-guard.sh` 看到 9 个冻结路径 hardcoded
- [ ] 在预览框架文件上 `git add` + `git commit` (无 --no-verify) → 应 exit 1 + 看到阻断 banner
- [ ] 同样 commit 加 `--no-verify` → 应 exit 0 + commit 成功
- [ ] `pnpm test tests/preview-framework-snapshot.test.ts` 应 pass (9 个路径验证 + version.json 一致性)
- [ ] `pnpm test:e2e e2e/preview-smoke.spec.ts` 应 pass (主人 dev server 3003 + 可选 :8080)
- [ ] `cat docs/adr/0009-preview-framework-freeze.md` 阅读 §3 改前 SOP 知晓