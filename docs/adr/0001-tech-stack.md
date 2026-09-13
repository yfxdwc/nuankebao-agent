# ADR-0001: 技术栈选型

**日期**: 2026-09-03
**状态**: 已采纳
**影响范围**: 全栈
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §3.1 数据安全红线 + §3.2 技术栈红线 + §3.3 部署红线

## 上下文

本决策对应元宪法:
- [`CHARTER.md`](../CHARTER.md) **§2 治理原则 1** (数据主权 > 功能丰富) — 决定自有服务器 + 字段加密
- [`CHARTER.md`](../CHARTER.md) **§2 治理原则 9** (AGPL 永不用) — 排除 NocoBase / Twenty
- [`CHARTER.md`](../CHARTER.md) **§2 治理原则 8** (借鉴思路 ≠ 复制代码) — 借鉴 NocoBase 数据模型驱动 + Frappe 自托管 + pgvector AI
- [`CHARTER.md`](../CHARTER.md) **§3.1** (敏感字段加密 + 不出境) — 决定 pgcrypto + 自托管 + MiniMax 国内 endpoint
- [`CHARTER.md`](../CHARTER.md) **§3.2** (技术栈红线: 不用 Prisma / 不用 AGPL / 不用 OpenAI 直连) — 选 Drizzle + MIT/Apache 协议栈 + MiniMax
- [`CHARTER.md`](../CHARTER.md) **§3.3** (部署必须 Docker Compose + 自有服务器) — 决定部署方式
- [`CHARTER.md`](../CHARTER.md) **§5.2 必须 ask_user** (技术栈 L1 战略) — 本决策由主人 2026-09-03 拍板

---

主人要做一个"养生行业销售人员的 CRM + AI 客户维护 + 养生记录"app。三个基础模块先打牢,再扩。

4 个关键决策点(2026-09-03 拍板):

1. **business_model**: 先内部用,后期考虑 SaaS(意味着不能用 AGPL 强 copyleft)
2. **erp_future**: 只做 CRM,不做门店 ERP(意味着 Frappe 生态优势用不上)
3. **data_compliance**: 高敏感(健康状态 / 疾病史 / 医疗记录)
4. **mvp_horizon**: flexible,不赶时间,先验证方向

3 个落地决策:

- **hosting**: 国内云(合规)
- **ai_model**: MiniMax(待主人最终确认 custom "minimax" 是否指 MiniMax API)
- **deploy_style**: 自有物理服务器(数据完全自有)

## 候选评估

### 候选 A: NocoBase(ChatGPT 第一推荐)

- ✅ 数据模型驱动,行业系统搭建灵活
- ✅ 中文文档/社区/插件齐
- ❌ **AGPL-3.0 协议** —— SaaS 时必须开源所有定制或买商业 license
- ❌ 高敏感数据 + 国内开源项目 = 风险叠加
- ❌ "后期 SaaS" 决策与此冲突

**结论**: ❌ 排除

### 候选 B: Twenty(现代 CRM)

- ✅ 第一天就有 CRM UI,React + NestJS + GraphQL
- ✅ 自定义对象支持养生档案扩展
- ❌ **AGPL-3.0 协议**(同上)
- ❌ "只做 CRM 不扩 ERP" 时,Twenty 的优势被浪费

**结论**: ❌ 排除

### 候选 C: Frappe CRM

- ✅ **MIT 协议干净**,后期 SaaS 零授权成本
- ✅ 自托管,健康数据安全可控
- ✅ Python 生态
- ❌ "不扩 ERP" = Frappe 最擅长的生态用不上
- ❌ UI 老气,AI 集成不如 JS 栈自然
- ❌ 开发体验笨重(框架约定多)

**结论**: ⚠️ 可选但不优

### 候选 D: 自建 JS 栈(本决策)

- ✅ **MIT/Apache 协议栈**(Next.js / Drizzle / Postgres / Auth.js),SaaS 零成本
- ✅ 完全自托管 + pgcrypto 字段加密 + 审计日志 = 健康数据完全可控
- ✅ pgvector 原生,后续 AI Copilot 零额外组件
- ✅ "flexible 不赶时间" 允许走这条路
- ❌ 起步代码量比 NocoBase 多 2-3 倍(MVP 6 周计划)
- ❌ 需要养前端 + 后端能力

**结论**: ⭐⭐⭐⭐⭐ 采纳

## 决策

**采用自建 JS 栈**:

```
前端:     Next.js 15 (App Router) + shadcn/ui + Tailwind CSS
后端:     Next.js Route Handlers (单体仓库,后期可拆 NestJS)
ORM:      Drizzle (SQL-first,JSONB 友好)
数据库:   PostgreSQL 16 + pgcrypto + pgvector
认证:     Auth.js v5 + 手机号验证码 (阿里云)
AI:       MiniMax API (国内 endpoint)
部署:     Docker Compose → 主人自有物理服务器
监控:     Postgres 触发器审计 + OpenTelemetry
```

## 关键设计决策

### 1. 协议策略:全栈 MIT/Apache

不允许引入任何 AGPL/GPL 强 copyleft 依赖,确保未来 SaaS 时零授权成本。

### 2. 数据策略:全部自托管 + 字段级加密

- 客户手机号 / 健康状态 / 疾病史 → 走 pgcrypto 加密列
- 任何数据库写操作 → 触发器写 audit_log 表
- 备份 → 加密 + 异地(不依赖公有云)

### 3. AI 策略:MiniMax 国内 API

- 数据不出境(国内 endpoint)
- 不接 OpenAI / Claude / Gemini 等境外 API
- prompt 模板版本管理(便于回滚 + 优化)

### 4. 部署策略:Docker Compose + 自有服务器

- 单台物理服务器起步,Docker Compose 编排
- 后期扩多台可改 K8s(暂不实施)
- 不依赖公有云,数据完全物理隔离

## 影响

- ✅ MVP 阶段可以快速搭起来,React/TS 全栈生态最丰富
- ✅ AI Copilot 阶段,pgvector + MiniMax 集成零额外组件
- ✅ SaaS 阶段,协议栈零阻力
- ⚠️ 主人需要养前端 + 后端能力,或外包给 pi / Codex
- ⚠️ 自有服务器运维成本(备份 / 监控 / 故障恢复)

## 后续行动

- [ ] W1: 初始化 monorepo 骨架(实际是单层 src/,符合 AGENTS.md §4)
- [ ] 写 Phase 1 任务清单 → `docs/phase-1-mvp.md`
- [ ] 写数据模型详细 → `docs/data-model.md`
- [ ] 写安全合规方案 → `docs/security-compliance.md`