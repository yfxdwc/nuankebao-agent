# 暖客宝 — 大健康行业销售人员 CRM

> v0.1.2 — Phase 1 W2-3 进行中 (Mobile-Only 阶段, 2026-09-07)
>
> 📱 **当前策略**: **Mobile-Only** — 接下来开发只做 Flutter 移动端, web admin 冻结 (`freeze-keep`), backend 同步走 `flutter-only-sync`, 解冻条件 `master-decide`。
> 详见 [`docs/CHARTER.md`](docs/CHARTER.md) §4.4 + [`ADR-0005`](docs/adr/0005-mobile-only-phase.md)。

## 这个项目是干嘛的

一个面向**大健康行业销售人员**(养生保健 / 健康管理 / 康复养老 / 营养食品 / 健康生活方式)的轻量级 CRM,核心三件套:

1. **客户管理** — 基础 CRM 能力,客户档案 / 联系记录 / 跟进任务
2. **AI 智能客户关系维护** — 自动汇总客户画像 / 跟进建议 / 话术生成 (Phase 2)
3. **养生记录** — 结构化记录理疗过程(部位 / 状态 / 用料 / 效果),AI 后续做效果分析 + 复购预测

**目标用户**:大健康行业销售 + 客服人员(移动端重度使用),次要:店长 / 老板看报表。

**核心差异**:不是传统 CRM 的销售漏斗,而是"养生档案 + AI 助手"——结构化的养生记录让 AI 真正能帮销售判断"这个客户该不该复购 / 该说什么话"。

## 技术栈

```
- Next.js 15 (App Router) + TypeScript strict
- React 18 + shadcn/ui + Tailwind CSS
- Drizzle ORM (SQL-first)
- PostgreSQL 16 + pgcrypto (字段加密) + pgvector (向量检索)
- Auth.js v5 + 手机号验证码 (开发期 mock 验证码 123456)
- Refine (W3 复杂表单阶段接入)
- MiniMax API (国内, Phase 2 AI Copilot)
- Docker Compose → 主人自有物理服务器
```

详见 [`docs/tech-stack-v0.1.md`](./docs/tech-stack-v0.1.md) 和 [`docs/references.md`](./docs/references.md)。

## Phase 1 状态 (v0.1.2 mobile-only)

| Week | 状态 | 说明 |
|---|---|---|
| W1 | ✅ 完成 (2026-09-03) | 项目骨架 + Docker + Next.js + Drizzle + Auth.js |
| W2-3 | 🔄 进行中 | Flutter 移动端 12 screen + Drizzle schema + 字段加密 + 审计; web admin 冻结 |
| W4 | ⏳ 待开始 | Flutter 报表 + APK 内测; web admin 报表后补 |
| W5-6 | ⏳ 待开始 | 部署 + 备份 + Flutter APK 销售内测; web admin 解冻 master-decide |

### Mobile-Only 阶段要点 (v0.1.2)

- ✅ **Flutter 移动端** = 唯一 active frontend (双线 → 单线, 释放精力)
- ❄ **Web admin** (`/admin/*`) = 冻结但保持运行, 不下线, 不加新 UI, 仅 P0 bug fix
- 🔄 **Backend / API** = 改动只同步 Flutter service (web admin client 类型/调用暂停同步, 解冻时 catch-up)
- 🕐 **Web 解冻** = 主人 ask_user 明确说「移动端 OK, 解冻 web」才触发 (master-decide)

**活跃目录** (可改):
- `flutter_app/lib/**` (主战场)
- `src/app/api/**` (backend, Flutter 消费)
- `src/lib/**` (业务逻辑)
- `src/middleware.ts`
- `src/app/(auth)/login/**`

**冻结目录** (仅 P0 bug fix):
- `src/app/admin/**` (web admin 16 page)
- `src/components/business/**` (web 业务组件 12 个)
- `src/components/admin/**` (sidebar/topbar/bottom-tab)

详见 [`AGENTS.md` §3 同步策略](./AGENTS.md) + [`docs/CHARTER.md` §4.4](./docs/CHARTER.md)。

---

## Phase 1 W1 状态 ✅

W1 完成项:
- ✅ Next.js 15 + TypeScript + Tailwind + shadcn/ui 骨架
- ✅ Docker Compose (Postgres 16 + pgcrypto + pgvector)
- ✅ Drizzle ORM 接入 + user 表 schema
- ✅ Auth.js v5 (开发期 mock 验证码 123456)
- ✅ 登录页 + admin 后台布局 (sidebar + topbar)
- ✅ /api/health 端点 (DB 健康)
- ✅ middleware 路由守卫 (未登录跳 /login)
- ✅ 字段加密封装 (AES-256-CBC)
- ✅ 全套文档 (ADR + tech-stack + data-model + security)

详见 [`docs/w1-implementation.md`](./docs/w1-implementation.md)。

## 快速开始

### 前置要求

```bash
node --version   # >= 20.0.0
pnpm --version   # >= 9.0.0
docker --version # >= 24.0.0
```

### 本地开发 (无 Docker)

```bash
# 1. 安装依赖
pnpm install

# 2. 准备 .env.local
cp .env.example .env.local
# 编辑 .env.local,至少填入:
#   DATABASE_URL=postgres://nuankebao:nuankebao_password@localhost:5432/nuankebao
#   AUTH_SECRET=<openssl rand -base64 32>
#   PGCRYPTO_KEY=<openssl rand -hex 32>

# 3. 启动 Postgres (可选 - 也可以用 Docker)
docker compose up -d postgres

# 4. 数据库迁移
pnpm db:migrate

# 5. 启动 Next.js
pnpm dev

# 6. 浏览器打开
open http://localhost:3003   # 暖客宝 默认 3003, 避开 sales ai 占用的 3000 / 3002
```

### Docker Compose 全栈启动

```bash
# 1. 准备环境变量
cp .env.example .env
# 编辑 .env: AUTH_SECRET / PGCRYPTO_KEY / POSTGRES_PASSWORD

# 2. 启动
docker compose up -d

# 3. 验证
curl http://localhost:3003/api/health
# 应返回 { "status": "healthy", "checks": { "db": "ok" } }
```

### 开发期登录

W1 阶段验证码硬编码为 **`123456`**(任意 11 位手机号 + 123456 都能登录)。

W2 接入阿里云 SMS 网关后替换为真实短信。

### 端口说明

主人已有 `sales ai` 项目占用 `localhost:3000`,`localhost:3001` (python3) 和 `localhost:3002` 也被占用。暖客宝 默认使用 **`localhost:3003`**(已实测空闲):

- Docker 端口映射: `${APP_PORT:-3003}:3000`
- Dev server: `pnpm dev`(已写入 package.json script,默认 3003)
- 自定义: `APP_PORT=3005 pnpm dev`
- 验证: `./tools/check-port.sh 3003`(应显示 ✓ 空闲)

## 目录结构

```
nuankebao-agent/
├── README.md                    ← 本文件
├── AGENTS.md                    ← pi 协作约定
├── package.json                 ← 依赖 + scripts
├── tsconfig.json
├── next.config.ts
├── tailwind.config.ts
├── postcss.config.mjs
├── components.json              ← shadcn 配置
├── drizzle.config.ts
├── docker-compose.yml
├── docker/
│   ├── Dockerfile               ← 多阶段构建
│   └── init.sql                 ← pgcrypto + pgvector
├── public/
├── src/
│   ├── app/
│   │   ├── layout.tsx           ← 根 layout
│   │   ├── page.tsx             ← 根路径 → 重定向 /admin
│   │   ├── (auth)/login/        ← 登录页
│   │   ├── (admin)/             ← 后台主区域
│   │   │   ├── layout.tsx       ← sidebar + topbar
│   │   │   └── page.tsx         ← 仪表盘 (W1 占位)
│   │   ├── api/
│   │   │   ├── health/route.ts  ← 健康检查
│   │   │   └── auth/[...nextauth]/route.ts
│   ├── components/
│   │   ├── ui/                  ← shadcn 基础组件
│   │   ├── auth/login-form.tsx
│   │   └── admin/
│   │       ├── sidebar.tsx
│   │       └── topbar.tsx
│   ├── lib/
│   │   ├── db/                  ← Drizzle 接入 + schema
│   │   ├── auth/                ← Auth.js v5
│   │   ├── crypto/              ← 字段加密封装
│   │   └── utils.ts             ← cn 等工具
│   └── styles/globals.css       ← Tailwind + 养生绿主题
├── middleware.ts                ← 路由守卫
├── docs/                        ← 设计文档 + ADR
│   ├── tech-stack-v0.1.md
│   ├── references.md
│   ├── data-model.md
│   ├── phase-1-mvp.md
│   ├── security-compliance.md
│   ├── w1-implementation.md
│   └── adr/
└── tools/
    └── check-env.sh
```

## 实施路线图 (v0.1.2 mobile-only)

| 阶段 | 时间 | 内容 |
|---|---|---|
| **Phase 1 MVP** | W1-W6 | Flutter 移动端主 + 1-2 销售 APK 内测; web admin 冻结 (后补, 解冻 master-decide) |
| Phase 2 AI Copilot | W7-W10 | MiniMax 接入 + 客户画像 + 跟进话术 (Flutter 优先) |
| Phase 3 SaaS 化 | W11+ | 多租户 + 计费; web admin 解冻后双线推进 |

详见 [`docs/phase-1-mvp.md`](./docs/phase-1-mvp.md)。

## License

MIT (业务代码) + 数据合规(健康数据处理遵守《个人信息保护法》)