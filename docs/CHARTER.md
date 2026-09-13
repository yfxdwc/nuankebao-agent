# CHARTER.md — 暖客宝 项目元宪法 (Meta-Constitution)

**版本**: v0.1.2
**生效日期**: 2026-09-05
**修订日期**: 2026-09-07 (v0.1.2 — Mobile-only 阶段, web admin 冻结, 详见 §4.4 + §10.2)
**维护者**: mm7 主人 (虾王,飞书 ou_b7dc078b75aa76960a16252688dbe6f9)
**变更权**: 主人拍板
**派生层**: 操作层 → [`AGENTS.md`](../../AGENTS.md)

> 本文件是**暖客宝项目的最高纲领**,定义治理哲学、红线、域边界、决策权与法规合规。
>
> **阅读顺序**:
> 1. 本文件 (CHARTER) —— 理解**为何这样做**
> 2. `AGENTS.md` —— 理解**具体怎么做**
> 3. `docs/adr/*` —— 历史决策与上下文 (按需)
>
> **与 sales-ai 关系**: 本 CHARTER **借鉴** sales-ai 的两层结构(元层 + 操作层),**不照搬**其治理工具。nuankebao-agent 是 W2-3 早期 MVP,体量 90 业务源文件(单层 src/),不及 sales-ai 977 文件 / 19 模块的 1/10,**不需要同样重度的 Plan Schema / 5 层决策等级 / 月度审查**等成熟期治理工具 —— 详见 v0.1.1 修订说明。

---

## §1. 项目宗旨 (Vision — Why we exist)

### 1.1 一句话定义

> **暖客宝** —— 大健康行业销售员的 CRM + AI 客户维护 + 养生记录,**让养生销售有尊严地工作**。

### 1.2 服务对象

- **主**: 大健康门店 / 品牌**销售 + 客服人员**(中年女性为主,移动端重度使用)
- **次**: 门店老板 / 店长(看报表 + 团队管理)
- **覆盖细分**: 养生保健 / 健康管理 / 康复养老 / 营养食品 / 健康生活方式

### 1.3 不做什么 (Anti-Vision)

- ❌ 不是通用 CRM(不抄 Salesforce/HubSpot 漏斗)
- ❌ 不是医疗诊断系统(不替代医生,不背医疗事故责任)
- ❌ 不是 SaaS(Phase 3 才考虑,Phase 1-2 私有部署)
- ❌ 不做社交/IM(沟通交给微信/企业微信)
- ❌ 不做电商交易(养生服务是线下为主)

---

## §2. 治理原则 (Principles — How we think)

> 9 条治理哲学。任何 trade-off 决策冲突时,优先级从高到低。

### 原则 1: **数据主权 > 功能丰富**

数据掌握在主人自己物理服务器上。**即使"自己用",也不把客户健康数据放第三方公有云**。

### 原则 2: **温暖 > 强大**

养生行业的销售员(中年女性为主)不需要 SaaS 冷色调 / 销售漏斗 / dashboard 复杂图表。要**简洁 + 温暖**。

### 原则 3: **移动优先 > 桌面优先**

销售员不在工位,在家、在路上、在客户身边。**移动端 > PC 端**。默认推 Flutter APK。

### 原则 4: **结构化 > 自由文本**

养生记录必须**结构化**(部位 / 状态 / 用料 / 效果 分字段),不能塞大文本。
> **理由**: AI 才能用(Phase 2 Copilot),查询才能用,报表才能用。

### 原则 5: **治本 > 凑数**

不写 TODO 占位代码,不做 demo 凑数,不留半截功能。**功能未完工不入 commit**。

### 原则 6: **主人拍板 > agent 自治**

战略决策(技术栈 / 部署方式 / 命名大方向 / 安全 / DB schema)必须 ask_user 拍板。
操作决策(函数命名 / 文件路径 / 实现细节)agent 自治。**详见 §5 决策权**。

### 原则 7: **小步快跑 > 一次大跃**

一次只让 pi 实现 1 个 feature,不堆 10 个。**每步可回滚**。

### 原则 8: **借鉴思路 ≠ 复制代码**

学习 NocoBase / Twenty / Frappe / Vault / Oso / Formily 等成熟项目。
**看懂设计,重新实现**;引用代码片段时注明出处 + 协议允许。

### 原则 9: **AGPL 永不用,OpenAI 永不用**

未来 SaaS 化(Phase 3)时 AGPL 会卡脖子;OpenAI 直连有数据出境风险。
**替代方案**: MiniMax / 通义 / 自建模型 / pgvector + 本地 embedding。

---

## §3. 不可违反的硬约束 (Red Lines)

> 这些**没有商量余地**。任何 AI agent / 人类开发者想"破例",必须**先**主人拍板并在 ADR 留档。

### 3.1 数据安全红线

| 红线 | 触发场景 | 后果 |
|---|---|---|
| 客户健康数据不出境 | 客户手机号 / 疾病史 / 养生记录 字段 | ❌ 永久禁用 OpenAI 直连 / 任何境外公有云 AI |
| 敏感字段必须加密 | 联系方式 / 体检数据 / 病史记事 | ❌ 必须走 pgcrypto,不准明文落盘 |
| 任何 DB 写必须审计 | 增删改 客户/养生记录/跟进任务 | ❌ 必须经 `lib/audit/` 封装 |
| 后端二次校验 | 健康字段前端校验过不算数 | ❌ 任何健康字段 API 必须二次校验 + 加密 |

### 3.2 技术栈红线

| 红线 | 替代方案 | 拍板日期 |
|---|---|---|
| ❌ 不用 Prisma | ✅ Drizzle (SQL-first, JSONB schema 友好) | 2026-09-03 |
| ❌ 不用 AGPL 协议依赖 | ✅ MIT / Apache 2.0 / BSD | 2026-09-03 |
| ❌ 不用 OpenAI API 直连 | ✅ MiniMax / 通义千问 / DeepSeek / pgvector 本地 | 2026-09-03 |
| ❌ 不硬编码默认端口 | ✅ 必须跑 `tools/check-port.sh` | 2026-09-04 |
| ❌ 不 sudo 改系统配置 | ✅ 主人手工操作 / ask_user | 持续 |

### 3.3 部署红线

- **部署必须 Docker Compose**(主人机器环境复杂,裸装 Node.js / Postgres 风险高)
- **数据库强密码 + 不暴露公网端口**(主人机器)
- **每日自动备份 + 异地灾备**(Phase 1 末必须到位)
- **不存任何生产凭证进 git**(`.env.local` 必须 `.gitignore`)

### 3.4 改名红线 (BBT → 暖客宝 强绑定)

> 见 AGENTS.md §6。本节只重申强绑定。

```
[hostname] Cloudflare DNS + tunnel config  (.home/mm7/.cloudflared/config.yml)
    ↓ 验证 / 影响
[AUTH_URL] .env                          (middleware getPublicBaseUrl() 用它做 fallback)
    ↓ 验证 / 影响
[APK base URL] flutter build apk --dart-define=NUANKEBAO_API_BASE=...
```

**只改其一必报错**。切换 SOP 见 CHANGELOG [0.2.0] + 后续 `docs/deploy.md` §6。

### 3.5 Schema 演进红线 (DB migration 必堵)

> **背景**: W3 加列不加默认值 = Flutter 老 APK 崩溃。MVP 早期 schema 频繁变,必须硬约束向后兼容。
> **拍板日期**: 2026-09-05 (W2-3 阶段)
> **配套**: [`ADR-0004`](adr/0004-schema-evolution.md) + `tools/check-migration-compat.sh` (CI 跑)

**绝对禁止 (任一即阻断 migration)**:

| 模式 | 原因 | 替代方案 |
|---|---|---|
| `DROP COLUMN` | 老版本客户端反序列化失败 | 加 `deleted_at TIMESTAMPTZ` 软标记 + 30 天后真删 |
| `DROP TABLE` | 关联代码 / 报表 / 备份全部失效 | 主人拍板 + ADR 留档 + 至少保留备份 1 年 |
| `RENAME COLUMN` / `RENAME TABLE` | Flutter JSON 序列化硬编码字段名 | 不重命名,新增列 + 旧列留 NULL |
| `ALTER COLUMN ... TYPE` 无 `USING` | 隐式转换失败 + 老数据格式不兼容 | 加新列 + 双写 + 后切读 + 最后删旧列 (3 步走) |
| `ALTER COLUMN ... SET NOT NULL` 无 DEFAULT | 旧行无值,UPDATE 锁全表 | 加 DEFAULT 或两步: (1) 填默认 (2) SET NOT NULL |
| `DROP INDEX` 在 customer/wellness_record/follow_up_task | 慢查询回退 | 加新索引 + 验证查询计划后再 DROP |

**推荐 (警告, 不阻断)**:

| 模式 | 备注 |
|---|---|
| `ADD COLUMN` 无 DEFAULT | 强烈推荐 `DEFAULT 'xxx'::类型` (避免老 APK INSERT 失败) |
| 大表 (>100k 行) `ALTER TABLE` | 必须 `CONCURRENTLY` (避免锁表) |
| `CREATE INDEX` (非 CONCURRENTLY) | 锁表,小表可,大表必须 `CONCURRENTLY` |

**回滚支持**:

- **破坏性 migration** (上述绝对禁止列出的) 必须配 `drizzle/down/<同名>.sql` 文件
- 加表 / 加列 (纯加性) 不强求 down
- `pnpm db:migrate:down <idx>` 触发单步回滚

**强制 CI**:
- `tools/check-migration-compat.sh` 在 `pnpm db:migrate` 前自动跑
- PR 阻断: ❌ 任一即失败
- 警告不阻断: ⚠️ 主人 review 决定是否改

### 3.6 RBAC 扩展预留 (W5 内测前必就位)

> **背景**: W5 销售内测时,店长 vs 销售员必须看不同范围的数据。本节约束 W2-W4 期间 schema 演进必须**为 RBAC 预留 hook**,不要求现在实现 RBAC。
> **拍板日期**: 2026-09-05 (W2-3 阶段)
> **配套**: W5 触发时写 ADR-0005 (RBAC 实施)

**schema 必带 (W2 起所有表)**:
- `created_by` 字段 (bigint, NOT NULL) — **已就位** ✅ (见 customer / wellness_record / interaction / follow_up_task)
- `store_id` 字段 (bigint, nullable) — 用于行级过滤;**已部分就位** (wellness_record 有 store_id, customer 表缺)
- `deleted_at` 字段 (timestamptz, nullable) — 软删;**已就位** ✅ (customer 表)
- `user_role` enum (admin/manager/sales) — **已就位** ✅ (user 表 user_role_enum)

**W4 之前必须补 (不补则 W5 RBAC 落地时回头改 schema)**:
- [ ] `customer.store_id` 加列 + backfill (从创建人推断)
- [ ] 所有表加 `store_id` 索引 (供 W5 middleware 行级过滤用)
- [ ] user 表加 `default_store_id` (sales 默认门店)

**W5 不允许** (本红线):
- ❌ 直接 `WHERE 1=1` 返回所有客户给前端 (必须有 store_id 过滤)
- ❌ 销售员能查 `follow_up_task` 中 `assigned_to != self.id` 的任务
- ❌ 店长跨店查 (manager.role 只能看 own_store)

---

## §4. 域划分 (Domain Boundaries)

> 暖客宝项目按**业务域**切分。MVP 早期(W2-3),域边界**软约束**:有架构意图,不强求形式化 API 边界 —— 等 W4 实测后再升级硬约束。

### 4.1 五大业务域

```
┌────────────────────────────────────────────┐
│              暖客宝 (NuankeBao)              │
├─────────┬─────────┬──────────┬──────┬───────┤
│ 客户域  │ 养生域  │ 跟进域   │ AI域 │ 部署域 │
│Customer │Wellness │ Follow-up│  AI  │ Deploy │
├─────────┴─────────┴──────────┴──────┴───────┤
│              认证域 (Auth)  ← 跨域基础        │
├────────────────────────────────────────────┤
│              基础设施 (Infra)                 │
└────────────────────────────────────────────┘
```

| 域 | 职责 | 关键表 (Drizzle) | API 入口 |
|---|---|---|---|
| **客户域** | 客户档案 / 标签 / 画像 | `customers`, `customer_tags` | `/api/customers/*` |
| **养生域** | 养生记录 / 用料 / 效果 | `wellness_records`, `wellness_items` | `/api/wellness-records/*` |
| **跟进域** | 跟进任务 / 话术 / 提醒 | `follow_ups`, `reminders` | `/api/follow-ups/*` |
| **AI 域** | Copilot / 跟进建议 / 话术生成 | `ai_prompts`, `ai_runs` | `/api/ai/*` |
| **部署域** | 备份 / 监控 / 部署脚本 | (文件系统) | (脚本) |
| **认证域** | 手机号验证码 / 角色 | `auth_users`, `auth_sessions` | `/api/auth/*` |

### 4.2 域边界软建议 (W2-3 MVP 早期)

- **跨域调用走 API**(Route Handler),不准 `lib/customer/db.ts` 直接 join `wellness_records` —— 但同 process 内不强求 DTO 隔离
- **域内表可以 JOIN**,跨域表走 API 或应用层 join
- W6 销售内测后,**根据实测违规案例**升级为硬规则(详见 §10.3.1)

### 4.3 前端策略 (apk-first, 2026-09-04 主人拍)

| 功能类型 | 入口 | 同步策略 |
|---|---|---|
| 销售侧 (录入/拍照/跟进/客户详情) | **Flutter APK** (`flutter_app/`) | 主 |
| 后端 / API 改动 | **flutter-only-sync** (v0.1.2 起, 详见 §4.4) | Flutter service 必同步; web admin client 暂停 |
| 纯管理 (报表/导入/审计/团队管理) | **Next.js admin web** (`src/app/admin/`) | 次 |

> **当前阶段**: Mobile-only (v0.1.2 起)。§4.4 定义冻结 / 解冻规则。

### 4.4 Mobile-Only 阶段章程 (v0.1.2 拍板)

> **背景**: W2-3 阶段 Flutter 移动端 + Next.js admin web 双线并行, 但主人 2026-09-07 拍板: **接下来开发只做移动端, web 端服务等移动端开发完成后再补**。
> **配套**: [`ADR-0005`](adr/0005-mobile-only-phase.md) + AGENTS.md §3 同步策略

**4.4.1 web admin 状态 — freeze-keep (冻结但保持运行)**

| 状态项 | 规则 |
|---|---|
| 代码 | 保留, 不删除 (`src/app/admin/` 全部保留) |
| 部署 | 照常运行, 不下线 (现有 `/admin/*` 路由继续服务) |
| 新 UI 功能 | ❌ **冻结** — 不加新页面 / 新交互 / 新组件 |
| 修 bug | ⚠️ **仅 P0** (登录失败 / 数据丢失 / 安全洞) — P1/P2 推迟到 web 解冻后 |
| Schema-driven UI 改动 | ✅ 允许 — 例如 backend API 改了, web admin 调用失败的修, 不算新功能 |
| git commit | 默认应只动 Flutter 目录; web admin 改动只允许出现在 P0 fix commit |

**4.4.2 backend / schema 同步策略 — flutter-only-sync**

| 改动类型 | Flutter service 必同步 | web admin client |
|---|---|---|
| Drizzle schema 变更 (CHARTER §3.5 红线) | ✅ 必同步 (生成 freezed model + service 方法) | ⏸️ 暂停, 解冻时一次性 catch-up |
| API endpoint 新增 / 修改 | ✅ 必同步 (Dio API client + service) | ⏸️ 暂停, 解冻时一次性 catch-up |
| 字段加密规则变化 | ✅ 必同步 (service 层加解密) | ⏸️ 暂停 (web 解冻时同步) |
| API 错误格式变化 | ✅ 必同步 | ⏸️ 暂停 |
| AI / 业务逻辑层 | ✅ 必同步 (如有 Flutter 调用) | ⏸️ 暂停 |

**注意**: "暂停"≠ "永远不同步"。web 解冻时, web admin client (含类型 / 调用) 需做一次性 catch-up sync (主人拍板时间 + 工作量估时另开)。

**4.4.3 解冻条件 — master-decide**

- **无预定义里程碑**: 不绑定 W6 / 功能对齐 / 测试通过
- **解冻触发**: 主人在某次 ask_user 中明确说「移动端 OK, 解冻 web」才解冻
- **解冻前检查清单** (主人 / agent 共解, 不强制): Flutter 12 screen 在真机跑过 / 销售愿意用 / AI Copilot 可用

**4.4.4 当前 active 的目录**

```
✅ 活跃 (可改):
  - flutter_app/lib/**          ← Flutter 移动端 (主战场)
  - src/app/api/**              ← Backend Route Handlers (Flutter 消费; web client 同步暂停 §4.4.2)
  - src/lib/**                  ← 业务逻辑 / 加密 / 审计 / DB
  - src/middleware.ts
  - src/app/(auth)/login/**     ← 登录页 (Flutter + Web 共用, 改需 Flutter 同步)

❄ 冻结 (仅 P0 bug fix):
  - src/app/admin/**            ← Web admin 16 个页面
  - src/components/business/**  ← Web admin 业务组件 (12 个)
  - src/components/admin/**     ← Sidebar / topbar / bottom-tab
  - src/app/admin/download/**   ← APK 下载页 (依赖 Flutter 构建产物, 仅维护)
```

**4.4.5 误判处理**

| 误判场景 | 处理 |
|---|---|
| 「这个表单 web 改下很快」 | ❌ 拒绝. 改 Flutter, 即使 web 同步停更 |
| 「这个 bug 只有 web 触发」 | ⚠️ 评估 P0 级别. P0 改, 其他攒到解冻 |
| 「这个新功能 web 加了, Flutter 也加」 | ❌ 拒绝. 只加 Flutter |
| 「API 改了, web 那边类型不匹配编译挂了」 | ⚠️ **这个要修**. 算 schema-driven UI 改动, 不算新功能 |
| 主人明确说「这个 web 也要」 | ✅ 听主人的. 但 commit message 标注「override §4.4 freeze」 |

---

## §5. 决策权与拍板 (Decision Authority)

### 5.1 决策等级 (3 层)

> 简化自 sales-ai 5 层(nuankebao-agent 是单 owner 个人项目,不需要 L3/L4 即时层)。

| 等级 | 决策类型 | 拍板人 | 留档位置 |
|---|---|---|---|
| **L0 元决策** | 项目宗旨 / 治理哲学 / 红线变更 | 主人 | CHARTER (本文件) |
| **L1 战略决策** | 技术栈 / 部署方式 / 协议 / 安全 / DB schema 大改 | 主人 | ADR (`docs/adr/`) + ask_user |
| **L2 操作决策** | 函数命名 / 文件路径 / API 路径 / 包选型 / 端口 / 实现细节 | **agent 自治** | git commit |

### 5.2 必须 ask_user 的场景 (3 条)

> 比 sales-ai 7 条强制清单**大幅精简**。nuankebao-agent 主人是个人开发者,被琐碎问题打扰反而拖慢迭代。

| # | 触发 | 典型场景 | 不需要 ask 的边界 |
|---|---|---|---|
| 1 | **L1 战略决策** | 换技术栈 / 换部署方式 / 换协议 / 改认证方式 | 同栈升级 patch 版不 ask |
| 2 | **DB schema 大改** | 加新表 / 删字段 / 改 3 个表以上 / 加新域 | 字段注释 / 类型扩展不 ask |
| 3 | **安全相关** | 加密算法变更 / 权限模型调整 / 客户数据流向变更 | 加日志 / 加审计字段不 ask |

**port / 命名 / 函数签名 / 单文件重构** = L2 操作决策,agent 自治,**不 ask**。

### 5.3 Plan Schema (软建议,非强制)

> **简化自 sales-ai 强制 5 段式**。MVP 早期绝大多数任务是单域/单文件,强制 Plan = 拖节奏。

**触发条件**(满足任一即建议写 Plan):
- 改动 ≥ 3 个文件
- 跨域(例如客户域 + 跟进域)
- 引入新依赖 / 新表 / 新 API
- 治本重构(替代旧抽象)

**Plan 模板(3 段,够用就好)**:

```markdown
## Plan: <标题>

### 1. 目标 (Why)
<解决什么问题 / 满足什么原则,引用 CHARTER §X / AGENTS.md §Y>

### 2. 范围 (What)
<触碰的域/表/文件 + 不在范围内的事>

### 3. 验证 (How)
<单测 / E2E / 手动验收 / audit log 落档 — 取舍即可,不必全勾>
```

**不强制**:单文件修改 / 单函数调整 / 调试 / 重命名不写 Plan。

---

## §6. 法规合规 (Compliance)

### 6.1 中国法规清单 (3 条)

> 简化自 sales-ai 5 条法规。nuankebao-agent 私有部署 + 单门店主人,**GDPR / 等保 2 级 是 Phase 3 SaaS 化才需要**(详见 §10.3 待办)。

| 法规 | 影响 | 实施 |
|---|---|---|
| **PIPL** (个人信息保护法) | 客户手机号 / 姓名 / 健康数据 | 必须告知 + 同意 + 加密 + 可删除 |
| **网络安全法** | 客户数据出境 / 等保 | 自有服务器 = 不出境;等保 Phase 3 考虑 |
| **数据安全法** | 客户数据分类分级 | 健康数据 = 重要数据,加密 + 审计 |

### 6.2 健康数据特殊要求

- **不诊断**: 系统不出具"是否健康""是否患病"判断,只记录用户自述
- **建议免责**: 所有"养生建议"必须带"咨询专业人士"提示
- **不存诊疗记录**: 医院的诊疗记录 / 处方不进系统,只存客户自述的养生行为
- **离职交接**: 员工离职时,其负责的客户数据按主人拍板处理(转让/保留/删除)

### 6.3 合规失效升级路径

```
发现合规问题 → 立即停手 → ask_user 拍板 → 写入 ADR → git commit + 飞书通知主人
```

---

## §7. 路线图 (Roadmap Charter)

> **本节只列 Phase 1 已完成/进行中 + 下一 Phase 的轮廓**。Phase 2/3 详细功能等启动时再补,避免过早具体化未拍板事项。
>
> 详细计划见 `docs/phase-1-mvp.md` / `docs/phase-3-saas.md` / `AGENTS.md §7`。

### Phase 1: MVP (Week 1-6)

| Week | 状态 | 产出 |
|---|---|---|
| W1 | ✅ 完成 (2026-09-03) | 项目骨架 + Docker + Next.js + Drizzle + Auth.js |
| W2-3 | 🔄 进行中 (Mobile-only, §4.4) | Flutter 移动端 12 screen + Drizzle schema + 字段加密 + 审计 + flutter-only-sync |
| W4 | ⏳ 待开始 | **移动端报表 + Flutter 内测**; web admin 报表**后补** (§4.4 freeze) |
| W5-6 | ⏳ 待开始 | 部署自有服务器 + 备份 SOP + Flutter APK 销售内测; web admin 解冻条件见 §4.4.3 |

> **W2-3 重点调整 (v0.1.2)**: 原来"数据模型 + CRUD + 字段加密 + 审计 + 移动端"是双线 (Flutter + Web admin), 现在 Flutter 单线. 释放的精力 → Flutter 真机体验打磨 + native 功能验证 (拍照 / SQLite / 推送).

### Phase 2 / Phase 3 (轮廓,未拍板)

- **Phase 2**: AI Copilot (MiniMax API)
- **Phase 3**: SaaS 化 (多租户 / 计费)

> 启动时拍板拍,Phase 1 期间不在本 CHARTER 展开。

---

## §8. 文档维护责任

> **简化自 sales-ai 4 层维护 + 月度审查**。nuankebao-agent 单 owner,月度审查**没人会真做**,删除。

### 8.1 文档分层 (谁写谁改)

| 层 | 文档 | 谁写 | 谁改 |
|---|---|---|---|
| L0 元层 | `docs/CHARTER.md` (本文件) | 主人 | 主人拍板 |
| L1 战略层 | `docs/adr/*` / `tech-stack-v0.1.md` / `data-model.md` | agent 提案 + 主人拍板 | 同上 |
| L2 操作层 | `AGENTS.md` / `docs/deploy.md` / `api.md` / `user-manual.md` | agent | 主人审 |
| L3 实现层 | 代码注释 / docstring | agent | agent |

### 8.2 文档更新触发 (按事件,不按周期)

- ✅ **每次架构变更** → 更新 ADR
- ✅ **每次技术栈变更** → 更新 `tech-stack-v0.1.md`
- ✅ **每次改名 / 大重构** → 更新 `AGENTS.md` §6 + `CHANGELOG.md`
- ✅ **每次发现反模式** → 更新 `AGENTS.md` §5
- ✅ **CHARTER 修订** → 更新本文件 + 在 §10.2 变更记录留档

---

## §9. 操作层引用 (Operational Layer)

> 本节定义"本宪法如何被下游执行层消费"。**简化自 sales-ai 3 层引用**(去掉代码层 docstring 强制引用,nuankebao-agent 早期不需要)。

### 9.1 AGENTS.md 引用约定

`AGENTS.md` 在每个章节标题后**必须**标注 `(CHARTER §X)`,例如:

```markdown
## §3. pi 协作规则 (CHARTER §2 治理原则 + §5 决策权)
```

不允许:
- ❌ 章节内容与 CHARTER 矛盾
- ❌ 章节内容超出 CHARTER 授权范围(L1 决策必须回到 CHARTER 拍板)

### 9.2 ADR 引用约定

每份 ADR 必须在 `## 上下文` 段引用:

```markdown
## 上下文

本决策对应:
- CHARTER §X (治理原则)
- CHARTER §3 红线 (如涉及)
```

---

## §10. 元数据与变更史

### 10.1 版本

| 版本 | 日期 | 状态 | 备注 |
|---|---|---|---|
| v0.1.0 | 2026-09-05 | 已废 | 首次拍板,主人 add-charter 选项拍板 |
| v0.1.1 | 2026-09-05 | 已废 | 去除 sales-ai 过度借鉴 (8 项),见 §10.2 |
| v0.1.2 | 2026-09-07 | **生效** | Mobile-only 阶段: web admin freeze-keep + flutter-only-sync + master-decide 解冻,见 §4.4 + ADR-0005 |

### 10.2 变更记录

| 日期 | 版本 | 变更类型 | 变更人 | 摘要 |
|---|---|---|---|---|
| 2026-09-05 | v0.1.0 | 新增 | mm7 主人拍板 | 首次创建,补齐 AGENTS.md 之上无元宪法 |
| 2026-09-05 | v0.1.1 | 修订 | mm7 主人拍板 | 8 项去过度借鉴: §5.1 决策 5→3 层 / §5.2 ask 7→3 条 / §5.3 Plan 5→3 段(软建议) / §6.1 法规 5→3 条 / §7 反模式三大根因删除 / §8 Phase 2/3 列表删除 / §9 文档审查频率删除 / §10.3 代码引用删除 |
| 2026-09-07 | v0.1.2 | 修订 | mm7 主人拍板 | Mobile-only 阶段: §4.3 后端同步 auto-both → flutter-only-sync / 新增 §4.4 freeze-keep + master-decide 解冻 / §7 W2-3 / W4 重点调整; 配套 ADR-0005 |

### 10.3 待办

- [ ] 等 W6 销售内测通过后,回头修订 §4 域边界(AI 域细化 + 实际边界图,见 §10.3.1)
- [ ] 等 Phase 1 完成后补 §6.2 健康数据实际合规清单
- [ ] Phase 3 SaaS 化前补 GDPR + 等保 2 级(回到 §6.1)

#### 10.3.1 Phase 1 完成后 §4 修订触发清单 (W6)

> Phase 1 收尾时 (W6 销售内测通过后) 必须执行。从原 5 项缩到 2 项关键。

- [ ] §4.1 五大业务域 → 实际跑通后,补**域内子模块清单**
- [ ] §4 末尾加一节 **§4.4 Phase 1 实际边界图**(替代当前文字版架构图)

**提醒机制**: AGENTS.md §7 路线图段 W6 行加 ⏰ 提醒标,完工时由 agent 主动重读 §4.

---

**本文件结束。下一个应读**: [`AGENTS.md`](../../AGENTS.md) (操作层) → [`docs/adr/0001-tech-stack.md`](adr/0001-tech-stack.md) (L1 战略层)