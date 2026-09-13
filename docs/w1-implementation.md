# Phase 1 W1 实施日志 (2026-09-03)

> W1 目标: 项目骨架 + Docker + Next.js + Drizzle + Auth.js, 跑出"能登录的空壳"

## ✅ 完成清单

### 配置层 (8 个文件)
- [x] `package.json` — 完整依赖清单
- [x] `tsconfig.json` — TypeScript strict + path alias
- [x] `next.config.ts` — serverExternalPackages
- [x] `tailwind.config.ts` — 养生绿 primary
- [x] `postcss.config.mjs`
- [x] `components.json` — shadcn new-york 风格
- [x] `drizzle.config.ts`
- [x] `.gitignore` — 加 Next.js / Drizzle / backups

### Docker 层 (3 个文件)
- [x] `docker-compose.yml` — Postgres + Web
- [x] `docker/Dockerfile` — 多阶段构建
- [x] `docker/init.sql` — pgcrypto + pgvector

### 业务层 (5 个文件)
- [x] `src/lib/utils.ts` — cn 函数 + 日期格式化
- [x] `src/lib/db/index.ts` — Drizzle 接入 + checkDb
- [x] `src/lib/db/schema.ts` — user 表 (W1 唯一表)
- [x] `src/lib/auth/index.ts` — Auth.js v5 (开发期 mock 验证码 123456)
- [x] `src/lib/crypto/field.ts` — AES-256-CBC 加密封装

### UI 组件层 (4 个 shadcn 文件)
- [x] `src/components/ui/button.tsx`
- [x] `src/components/ui/card.tsx`
- [x] `src/components/ui/input.tsx`
- [x] `src/components/ui/label.tsx`

### 业务组件 (3 个文件)
- [x] `src/components/auth/login-form.tsx` — 手机号 + 验证码两步登录
- [x] `src/components/admin/sidebar.tsx` — 后台导航
- [x] `src/components/admin/topbar.tsx` — 顶栏 + 退出

### App 层 (7 个文件)
- [x] `src/app/layout.tsx` — 根 layout + metadata
- [x] `src/app/page.tsx` — 根路径重定向
- [x] `src/app/(auth)/login/page.tsx` — 登录页
- [x] `src/app/(admin)/layout.tsx` — 后台布局
- [x] `src/app/(admin)/page.tsx` — 仪表盘 (W1 占位, W3 接入数据)
- [x] `src/app/api/health/route.ts` — 健康检查
- [x] `src/app/api/auth/[...nextauth]/route.ts` — Auth.js handlers
- [x] `src/middleware.ts` — 路由守卫 (未登录跳 /login)

### 文档层 (1 个新文件 + 3 个更新)
- [x] `docs/w1-implementation.md` (本文件)
- [x] `README.md` — 加快速开始章节
- [x] `AGENTS.md` — 更新进度
- [x] `.env.example` (已有, 保留)

## 📋 W1 验收清单 (主人跑环境验证)

```bash
# 1. 准备环境变量
cp .env.example .env.local
# 编辑 .env.local:
#   AUTH_SECRET=$(openssl rand -base64 32)
#   PGCRYPTO_KEY=$(openssl rand -hex 32)
#   POSTGRES_PASSWORD=自定义密码
#   DATABASE_URL=postgres://bbt:密码@localhost:5432/bbt

# 2. 安装依赖
pnpm install

# 3. 启动 Postgres (用 Docker)
docker compose up -d postgres

# 4. 验证 Postgres 启动
docker compose ps
# 应看到 nuankebao-postgres healthy

# 5. 数据库初始化 (启用扩展)
docker exec -it nuankebao-postgres psql -U bbt -d bbt -f /docker-entrypoint-initdb.d/init.sql
# 应看到 pgcrypto + vector 已启用

# 6. 启动 Next.js
pnpm dev

# 7. 验证 - 健康检查
curl http://localhost:3003/api/health
# 期望: { "status": "healthy", "checks": { "db": "ok" } }

# 8. 验证 - 登录流程
# 浏览器打开 http://localhost:3003
# 应自动跳转到 /login
# 输入任意 11 位手机号 (例: 13800138000)
# 点击"发送验证码" → 进入验证码步骤
# 输入 123456 (W1 mock 验证码) → 点击登录
# 应跳转到 /admin (仪表盘)

# 9. 验证 - 路由守卫
# 在 admin 页面退出登录后, 访问 http://localhost:3003/admin
# 应跳转到 /login
```

## 🎨 设计选择

### 主题色: 养生绿 (#1f8a4c 系)

```css
:root {
  --primary: 142 60% 35%;  /* 养生绿 hsl */
}
```

不用 SaaS 蓝, 体现养生行业气质(自然 / 健康)。

### UI 框架: shadcn/ui + Tailwind

- 完全可控(代码本地化, 不是 npm 依赖)
- 中文友好
- 移动端响应式天然支持
- 与 Next.js App Router 集成最干净

### Refine 在 W1 暂不深度集成

W1 阶段只装好 Refine 依赖, 不深度使用。W3 复杂表单(养生记录结构化录入)再接入 useTable / useForm hooks。

避免"全 Refine 包揽"失去 Server Components 性能优势。

### Auth.js v5 + JWT session

- W1 用 Credentials provider (mock 验证码)
- W2 替换为真实阿里云 SMS 校验
- W3 接入 Drizzle adapter 查 user 表

## 🔜 W2 任务预览

按 [`docs/phase-1-mvp.md`](./phase-1-mvp.md):

- [ ] 完整 Drizzle schema (10+ 表: customer / wellness_record / interaction / follow_up_task / body_part / service_item / product / audit_log 等)
- [ ] Drizzle migration 脚本 + seed 数据
- [ ] 字段加密在 DB 中真实落地 (pgcrypto 应用层加密已封装)
- [ ] 审计触发器 (audit_trigger 函数)
- [ ] 业务层 CRUD (queries/)
- [ ] API Route Handlers (api/customers, api/wellness-records 等)
- [ ] 客户管理 UI (列表 / 详情 / 编辑)
- [ ] 养生记录 UI (结构化表单! 核心 UI)
- [ ] 跟进任务 UI
- [ ] 联系记录 UI
- [ ] 阿里云 SMS 网关集成 (替换 mock 验证码)
- [ ] 移动端响应式打磨
- [ ] 审计日志查询页面 (admin only)

## 📊 W1 文件统计

```
新增: 30+ 文件
├─ 配置层:    8 个
├─ Docker:    3 个
├─ src/lib:   5 个
├─ src/components: 7 个 (4 shadcn + 3 业务)
├─ src/app:   8 个
├─ middleware: 1 个
└─ docs:      1 个新 + 2 个更新
```

## ⚠️ 已知 TODO (W2/W3 处理)

W1 文件里有明确注释标记的"占位":

| 文件 | 占位说明 | W? |
|---|---|---|
| `src/lib/auth/index.ts` | authorize() 返回 mock user | W3 |
| `src/lib/db/index.ts` | withAuditContext() stub | W2 |
| `src/components/auth/login-form.tsx` | sendCode() 走 setTimeout | W2 |

不算反 vibe 的 "TODO 占位", 是显式的 W 阶段标记, 主人 review 时可追溯。

---

**记录日期**: 2026-09-03
**下次评审**: W2 开始前