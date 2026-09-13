# 学习借鉴成熟项目 (2026-09-03 拍板)

> **主人决策**: 自建, 但可以借鉴其他成熟项目的部分功能实现方法
> **核心原则**: **借鉴思路 ≠ 复制代码** — 看懂设计, 重新实现

**借鉴结构**: 本项目的两层宪法架构 (`CHARTER.md` 元层 + `AGENTS.md` 操作层) 借鉴自 [sales-ai 项目](https://github.com/sales-ai/sales-ai) 的同款两层治理结构 (alignment by design, not copy-paste, 见 `CHARTER.md` §10.3 + `AGENTS.md` 顶部「阅读顺序」约定)。

---

## 借鉴的边界 (重要)

| 方式 | 含义 | 我们采用? |
|---|---|---|
| ✅ **借鉴** | 看懂思路 + 自己重新实现(API/UI/数据流可以完全不同) | **是, 主线** |
| ⚠️ **复用** | 引入包 / 直接用代码片段 (需协议允许) | **偶尔, 注明出处** |
| ❌ **复制** | 直接 fork / clone 整个项目 | **不采用** |

## 借鉴清单(按 BB T 项目实际功能)

#### 1. 数据建模设计模式 (借鉴 NocoBase / Twenty / Frappe)

**借鉴内容**:
- 实体定义 + 字段类型 + 关联配置的可视化思想
- 字段元数据设计 (`field_meta` 表记录字段类型 / 校验 / 显示规则)
- 关联关系类型: 一对一 / 一对多 / 多对多
- "数据模型驱动 UI" 的核心理念

**我们的实现**:
- Drizzle schema 落地 (代码式而非配置式, 但**设计哲学**借鉴)
- `field_meta` JSONB 字段存字段级元数据(便于动态展示 / Phase 2 字段级权限)
- 关联表: `wellness_record_body_part`, `wellness_record_product` 等中间表
- **不直接用** NocoBase 的可视化建模,但借鉴"模型先于 UI" 的思想

**为什么不直接用 NocoBase**:
- AGPL 协议限制 SaaS
- 主人要完全控制代码
- 自建虽然慢, 但数据模型 / 业务逻辑完全自主

#### 2. 字段加密 + 查询索引模式 (借鉴 HashiCorp Vault / pgcrypto 文档)

**借鉴内容**:
- 双字段模式: `phone_encrypted` (加密字段) + `phone_hash` (查询索引)
- 应用层加密 + 数据库加密分层
- 密钥管理与轮换策略

**我们的实现**:
- `src/lib/crypto/field.ts` 应用层 AES-256-CBC
- pgcrypto 作为额外一层 (可选, Phase 2)
- 密钥从 Docker secrets 读取, 不进 git
- 详见 [`security-compliance.md`](./security-compliance.md)

#### 3. 审计日志 + 触发器 (借鉴企业级 CRM / PostgreSQL 文档)

**借鉴内容**:
- 触发器自动写审计 (应用层不漏写)
- Session 变量传用户上下文 (`SET LOCAL app.current_user_id`)
- changed_fields JSONB 字段记录具体变更

**我们的实现**:
- `audit_trigger()` 函数 + 触发器挂载在敏感表
- `withAuditContext()` 包装 DB 操作
- 详见 [`adr/0002-data-model.md`](./adr/0002-data-model.md) §审计策略

#### 4. AI Builder / 工作流嵌入 (借鉴 NocoBase AI Builder / AI Employee / LangChain)

**借鉴内容**:
- 工作流节点化设计 (LLM 节点 / 数据节点 / 条件节点 / 工具调用)
- Prompt 模板版本管理(便于回滚 + A/B 测试)
- AI 嵌入业务流程(而不是单独的 ChatGPT 弹窗)
- Function calling / Tools 模式

**我们的实现** (Phase 2):
- `src/lib/ai/` 封装 MiniMax API
- `docs/ai-prompts/` 版本化 prompt 模板
- AI 嵌入养生记录 / 跟进任务生成(而非独立聊天界面)
- 借鉴 LangChain 的 LCEL 思路,但**不引入 LangChain**(过度设计)

#### 5. 权限系统设计 (借鉴 Oso / Auth0 / Casbin / NocoBase 权限)

**借鉴内容**:
- RBAC + ABAC 混合(角色 + 属性 + 上下文)
- 行级权限(RLS)
- 字段级权限
- 权限策略声明式定义(Policy)

**我们的实现** (MVP 应用层, Phase 2 加固):
- 角色枚举: `admin / manager / sales`
- 应用层 `canAccess(user, resource, action)` 函数
- Phase 2 加 Postgres RLS(行级)
- **不引入** Casbin / Oso(增加学习曲线,我们的需求 MVP 阶段不重)

#### 6. 工作流引擎简化版 (借鉴 NocoBase 工作流 / Temporal 思路)

**借鉴内容**:
- 节点化流程定义(触发器 → 条件 → 动作)
- 跟进任务自动生成(基于复购周期)
- 异步任务处理

**我们的实现** (Phase 2):
- 简单 cron + BullMQ 任务队列
- **不引入** Temporal / Camunda(过度设计,养生 CRM 工作流很有限)

#### 8. 表单动态生成 (借鉴 Formily / NocoBase 可视化表单 / react-jsonschema-form)

**借鉴内容**:
- JSON Schema → 表单渲染
- 字段联动(部位 → 推荐耗材)
- 字段级校验规则

**我们的实现**:
- React Hook Form + Zod schema(代码式,养生记录结构化录入)
- Phase 2 可加 JSON Schema 动态表单(便于非技术用户配置)
- **不引入** Formily(我们需求 MVP 阶段不需要那么动态)

#### 9. 移动端 PWA (借鉴 Twenty 移动端 / Workbox / Next.js PWA)

**借鉴内容**:
- PWA 配置(manifest.json + service worker)
- 离线缓存策略(Network First for API, Cache First for assets)
- "Add to Home Screen" 引导

**我们的实现** (Phase 3):
- Next.js PWA + Workbox 集成
- 不引入 React Native / Expo(MVP 阶段过度设计)

#### 10. 数据导入 / 导出 (借鉴 NocoBase 数据迁移 / Frappe Data Import)

**借鉴内容**:
- Excel 导入(用户友好,字段映射 UI)
- 数据校验(必填 / 重复 / 格式)
- 错误报告 + 预览
- 导出 JSON / CSV

**我们的实现** (W4):
- `xlsx` 库解析 Excel
- Zod schema 校验
- 错误报告 UI
- **不引入** 复杂的 ETL 工具

#### 11. 报表 / 仪表盘 (借鉴 Recharts / Tremor / Metabase 思路)

**借鉴内容**:
- 简单图表(折线 / 柱状 / 饼图)
- 时间范围过滤
- 同比 / 环比计算

**我们的实现**:
- Recharts(简单够用)
- **不引入** Tremor / Metabase(我们需求轻)

---

## 借鉴的项目汇总

| 项目 | 借鉴内容 | URL | 协议 |
|---|---|---|---|
| **NocoBase** | 数据建模 / 工作流 / AI Builder / 权限 | https://github.com/nocobase/nocobase | AGPL-3.0 (借鉴思路不复用代码) |
| **Twenty** | 现代 CRM 架构 / PWA / GraphQL 数据流 | https://github.com/twentyhq/twenty | AGPL-3.0 (借鉴思路不复用代码) |
| **Frappe / ERPNext** | 文档结构 / 字段元数据 / DocType 思路 | https://github.com/frappe/frappe | MIT (可少量借鉴代码片段) |
| **EspoCRM** | 字段类型 / 表单动态 | https://github.com/espocrm/espocrm | GPLv3 (仅借鉴思路) |
| **HashiCorp Vault** | 加密策略 / 密钥轮换 | https://www.vaultproject.io/ | MPL-2.0 |
| **Oso** | 权限模型 | https://github.com/osohq/oso | Apache-2.0 |
| **Auth0** | 认证架构 | https://github.com/auth0 | MIT |
| **Casbin** | RBAC / ABAC 模型 | https://github.com/casbin/casbin | Apache-2.0 |
| **Formily** | 动态表单 | https://github.com/alibaba/formily | MIT |
| **react-jsonschema-form** | JSON Schema → Form | https://github.com/rjsf-team/react-jsonschema-form | Apache-2.0 |
| **Temporal** | 工作流引擎思路 | https://github.com/temporalio/temporal | MIT |
| **BullMQ** | 任务队列 | https://github.com/taskforcesh/bullmq | MIT |
| **Vercel AI SDK** | AI 集成 | https://github.com/vercel/ai | Apache-2.0 |
| **LangChain** | LCEL / Agent 思路 | https://github.com/langchain-ai/langchain | MIT |
| **LlamaIndex** | RAG 思路 | https://github.com/run-llama/llama_index | MIT |
| **Workbox** | PWA 离线策略 | https://github.com/GoogleChrome/workbox | MIT |
| **Drizzle ORM** | ORM 设计 / Migration | https://github.com/drizzle-team/drizzle-orm | Apache-2.0 |
| **PostgreSQL 官方文档** | 触发器 / RLS / pgcrypto / pgvector | https://www.postgresql.org/docs/ | PostgreSQL License |

---

## 借鉴原则 (硬约束)

1. **先看懂再写**: 不要没看懂就借鉴, 容易把错误的设计也学来。读官方文档 + 至少 1 篇深度文章
2. **注明出处**: 借鉴的地方在代码注释里写明 `// 参考 NocoBase 的 X 模式` 或 ADR 引用
3. **MIT/Apache 优先**: 借鉴代码片段时优先选 MIT/Apache 协议的项目, GPL/AGPL 仅借鉴思路
4. **不直接 fork**: 我们要的是思路, 不是整个项目
5. **测试覆盖**: 借鉴的实现必须经过单元测试覆盖
6. **记录 ADR**: 重大借鉴(架构级)写 ADR, 小借鉴(单函数)写注释

## 借鉴与原始决策的关系

- 自建 ≠ 从零造轮子
- 自建 = 完全控制 + 协议干净 + 借鉴成熟经验
- NocoBase / Twenty / Frappe 仍然是**重要的参考对象**, 主人后续可读它们的源码 / 文档, 作为决策参考

---

**记录日期**: 2026-09-03
**下次评审**: W3 末 (Phase 1 中期, 2026-09-29 预计)