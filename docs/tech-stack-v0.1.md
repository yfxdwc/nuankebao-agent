# 暖客宝 v0.1 最优自建技术栈 (2026-09-03 拍板定稿)

> **主人决策**: 自建 (经多轮比较 NocoBase / Twenty / Frappe 后拍板)
> **约束矩阵**: later_saas + only_crm + 高敏感健康数据 + flexible 不赶时间
> **部署**: 主人自有物理服务器 + 国内云备案 + MiniMax AI (国内 endpoint)
> **借鉴来源**: 详见 [`references.md`](./references.md) — 借鉴 NocoBase / Twenty / Frappe 等成熟项目的部分功能实现方法

---

## 核心栈 (主人指定 ✅)

| 组件 | 版本 | 选型理由 |
|---|---|---|
| **Next.js** | 15.x (App Router) | React 生态最成熟, Server Components + Server Actions 简化数据流, Vercel AI SDK 集成最自然 |
| **Refine** | 0.x | 复杂表单 / 列表 hooks + 数据 provider 抽象, 减少 CRUD 样板代码 |
| **PostgreSQL** | 16.x 自托管 | 完全控制, pgcrypto 字段加密, pgvector 向量检索 |

## 必要补充 (不补就跑不起来)

| 组件 | 选型理由 |
|---|---|
| **TypeScript 5.x strict** | 类型安全, 养生记录 JSONB 强需要 (部位/状态/用料/效果 都是 JSONB) |
| **Drizzle ORM 0.30+** | SQL-first, JSONB 友好, Refine 数据 provider 对接干净 |
| **pgcrypto** (Postgres ext) | 字段加密 — 健康数据合规底线 |
| **pgvector** (Postgres ext) | AI Copilot 准备 — 客户画像 / 话术 RAG |
| **shadcn/ui + Tailwind 4** | UI 组件库 + 工具类 CSS, 移动端友好 |
| **Auth.js v5** | 手机号验证码登录 (阿里云 SMS) |

## 强烈推荐 (提升质量)

| 组件 | 选型理由 |
|---|---|
| **Vercel AI SDK** | AI 集成最自然 (流式 / 工具调用 / 模板管理) |
| **MiniMax API** | 国内 endpoint, 数据不出境, 价格友好 |
| **React Hook Form + Zod** | 复杂表单 + schema 校验 (养生记录结构化录入) |
| **Recharts** | 简单图表 (报表够用, 不引入 Tremor 减少学习曲线) |
| **dayjs** | 日期处理 (比 moment 轻量, date-fns 也可以) |

## 运维 + 测试

| 组件 | 选型理由 |
|---|---|
| **Docker Compose** | 容器化, 便于迁移 / 重建 / 备份 |
| **Nginx + Let's Encrypt** | HTTPS 反向代理, 免费 SSL |
| **阿里云 SMS 网关** | 手机号验证码发送 |
| **pnpm** | 包管理 + monorepo workspace 支持 |
| **Vitest** | 单元测试 (Vite 原生, 快) |
| **Playwright** | E2E 测试 (验证登录 / 录入流程) |
| **OpenTelemetry** (Phase 2) | 链路追踪 + 性能监控 |

## Refine 在 Next.js 15 中的角色 (技术提示)

**保留 Refine 是 OK 的**,但实施时建议**混用模式**而非"全 Refine 包揽":

```
┌──────────────────────────────────────────────┐
│            Next.js 15 App Router             │
├──────────────────────────────────────────────┤
│ Server Components  ────► 直接 Drizzle 查询    │  ← 服务端读
│ Server Actions       ────► 直接 Drizzle 写    │  ← 服务端写
│                                                │
│ Refine hooks (客户端)                         │  ← 仅复杂表单/列表
│   - useTable (跟进任务列表)                   │
│   - useForm (养生记录结构化录入)              │
│   - useUpdate (状态切换)                     │
└──────────────────────────────────────────────┘
```

理由:
- Server Components + Server Actions 已覆盖 60% CRUD 样板代码
- Refine 主要价值在**复杂客户端交互**(表单联动 / 乐观更新 / 状态机)
- 全 Refine = 失去 Server Component 性能优势
- 不用 Refine = 复杂表单样板代码爆炸

## 完整依赖清单 (待 W1 实施时填入 package.json)

```json
{
  "dependencies": {
    "next": "^15.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "@refinedev/core": "^4.0.0",
    "@refinedev/nextjs-router": "^1.0.0",
    "@refinedev/antd": "^5.0.0",
    "drizzle-orm": "^0.30.0",
    "postgres": "^3.4.0",
    "next-auth": "^5.0.0-beta",
    "@auth/drizzle-adapter": "^1.0.0",
    "react-hook-form": "^7.50.0",
    "@hookform/resolvers": "^3.3.0",
    "zod": "^3.22.0",
    "ai": "^3.0.0",
    "@ai-sdk/minimax": "^1.0.0",
    "tailwindcss": "^4.0.0",
    "lucide-react": "^0.400.0",
    "dayjs": "^1.11.0",
    "recharts": "^2.10.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "@types/react": "^19.0.0",
    "typescript": "^5.5.0",
    "drizzle-kit": "^0.20.0",
    "vitest": "^2.0.0",
    "@playwright/test": "^1.40.0",
    "eslint": "^9.0.0"
  }
}
```

注: `@refinedev/antd` 是 Refine 的 Ant Design 数据 provider。Ant Design 中文友好 + 移动端成熟。如果主人更偏好 shadcn/ui,可换 `@refinedev/react-router` + 自行接入 shadcn 组件。

## 反向关联

- [`references.md`](./references.md) — 借鉴成熟项目的功能实现方法
- [`adr/0001-tech-stack.md`](./adr/0001-tech-stack.md) — 技术栈选型决策
- [`adr/0002-data-model.md`](./adr/0002-data-model.md) — 数据模型决策
- [`data-model.md`](./data-model.md) — 完整数据模型详细
- [`phase-1-mvp.md`](./phase-1-mvp.md) — Phase 1 实施计划
- [`security-compliance.md`](./security-compliance.md) — 安全合规方案

---

**定稿日期**: 2026-09-03
**下次评审**: W1 实施结束时 (预计 2026-09-15)