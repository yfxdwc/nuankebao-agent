# Phase 1 MVP 实施计划 (6 周)

> **目标**:养生行业销售人员的 CRM MVP,具备客户管理 + 养生记录 + 跟进任务 + 字段加密 + 审计日志
> **部署**:主人自有物理服务器
> **验收**:1-2 个销售内测,能日常使用
> **当前阶段** (2026-09-07, CHARTER v0.1.2): **Mobile-Only** — web admin 冻结 (`freeze-keep`), backend 同步走 `flutter-only-sync`, 解冻 `master-decide`。详见 [`ADR-0005`](adr/0005-mobile-only-phase.md)。

---

## 总览 (v0.1.2 mobile-only 调整后)

| 周 | 里程碑 | 验收标准 |
|---|---|---|
| W1 | 项目骨架 + Docker | `pnpm dev` 起得来,Docker Compose 起得来,Auth.js 登录能用 |
| W2-3 | 数据模型 + Flutter 移动端 + 加密 | Drizzle schema 完整化 + Flutter 12 screen 真机验收 + 字段加密 + 审计日志 + flutter-only-sync (web client 暂停) |
| W4 | Flutter 内测 + 移动端基础报表 | Flutter APK 装到手机日常用 1 周,移动端报表可看 |
| W5-6 | 部署 + 备份 + Flutter APK 销售内测 | 部署自有服务器 + 备份 SOP + 销售内测 (Flutter 入口); web admin 报表后补, 等主人解冻 |

---

## W1 — 项目骨架 + Docker

### 任务
- [ ] 初始化 `package.json` + pnpm workspace
- [ ] Next.js 15 初始化 (App Router, TypeScript strict)
- [ ] Tailwind + shadcn/ui 初始化
- [ ] Drizzle ORM 初始化 + Postgres 连接
- [ ] Docker Compose:`postgres` (pgvector + pgcrypto) + `web` (Next.js)
- [ ] Auth.js v5 初始化 + 手机号验证码(阿里云短信)
- [ ] 基础布局:`(auth)/login` + `(admin)/layout` (sidebar + topbar)
- [ ] 健康检查:`/api/health` 返回 DB / Redis 状态

### 产出文件
```
package.json
tsconfig.json
next.config.ts
docker/
  docker-compose.yml
  Dockerfile
  init.sql             # pgvector + pgcrypto
src/
  app/
    layout.tsx
    (auth)/login/page.tsx
    (admin)/layout.tsx
    (admin)/page.tsx   # 仪表盘(空)
    api/health/route.ts
  components/ui/       # shadcn 基础组件
  lib/
    db/index.ts        # Drizzle 实例
    db/schema.ts       # 用户表 (其他表 W2)
    auth/              # Auth.js 配置
  styles/globals.css
.env.example
```

### 验收
```bash
pnpm dev               # Next.js 起得来
docker compose up -d   # Postgres 起得来
curl localhost:3003/api/health  # 返回 { db: "ok" }, 3003 是 暖客宝 默认端口
# 浏览器打开 /login,能看到登录页
```

---

## W2-3 — 数据模型 + Flutter 移动端 + 加密 (v0.1.2 mobile-only)

> **v0.1.2 调整**: 原计划"数据模型 + CRUD + 加密"双线 (Flutter + Web admin), 现在**只做 Flutter 移动端**, web admin 冻结 (CHARTER §4.4.1 freeze-keep)。Backend / API 改动按 flutter-only-sync 同步 (CHARTER §4.4.2)。

### W2 任务
- [ ] 完整 Drizzle schema:`customer`, `wellness_record`, `wellness_record_body_part`, `wellness_record_product`, `interaction`, `follow_up_task`, `body_part`, `service_item`, `product`, `audit_log`, `store`, `staff`
- [ ] Drizzle migration + seed(字典数据) — 严格走 CHARTER §3.5 红线 + ADR-0004 compat check
- [ ] 加密封装 `src/lib/crypto/field.ts`
- [ ] 审计触发器 migration
- [ ] 业务层 CRUD:`src/lib/db/queries/customer.ts`, `wellness-record.ts`
- [ ] API Route Handlers:`/api/customers`, `/api/customers/[id]`, `/api/wellness-records`
- [ ] **Flutter service flutter-only-sync 同步**: 改 backend 后必须同步更新 `flutter_app/lib/services/` + freezed model (web admin client 暂停, 解冻时 catch-up)
- [ ] Drizzle Studio 配置(开发时 GUI)

### W3 任务 (mobile-only 主战场)
- [ ] **Flutter 12 screen 真机验收 + native 验证** (主):
  - auth/login → customers (列表/详情/编辑) → wellness_records (列表/详情/结构化表单) → follow_ups → interactions → ai/reports → dashboard
  - 真机拍照 / SQLite 离线缓存 / 推送 / 二维码 等 native 功能验证
  - Web + Phone 并行开发 (`ADR-0003`)
- [ ] **字段加密 UI 层** (用户输入正常,底层加密) — Flutter service 层封装 + UI 层无感
- [ ] 错误处理 + Loading 状态 + 表单校验 — Flutter 优先
- [ ] ❄ web admin UI 不动 (CHARTER §4.4 freeze-keep, 仅 P0 bug fix)
- [ ] ❄ Refine / 复杂 web admin 表单组件 — 推迟到 web 解冻后再评估

### 产出文件
```
src/
  app/(admin)/
    customers/
      page.tsx              # 列表
      [id]/page.tsx         # 详情
      [id]/edit/page.tsx
      new/page.tsx
    wellness-records/
      page.tsx
      [id]/page.tsx
      new/page.tsx          # 结构化表单(重点!)
    follow-ups/
      page.tsx
    interactions/
      page.tsx
    audit-log/              # 仅 admin
      page.tsx
    api/
      customers/route.ts
      customers/[id]/route.ts
      wellness-records/route.ts
      wellness-records/[id]/route.ts
      follow-ups/route.ts
      interactions/route.ts
  components/business/
    customer-card.tsx
    customer-form.tsx
    wellness-record-form.tsx     # 结构化表单,核心 UI
    wellness-record-detail.tsx
    follow-up-card.tsx
  lib/
    crypto/field.ts         # 加密封装
    db/schema.ts            # 完整 schema
    db/queries/             # 业务查询
    audit/                  # 审计封装
  drizzle/
    migrations/             # 自动生成
```

### 验收
- 客户增删改查 ✅
- 养生记录结构化录入(部位多选 / 状态 JSONB / 用料多选 / 效果 JSONB)✅
- 跟进任务能建能完成 ✅
- 所有敏感字段在 DB 看是加密的 ✅
- audit_log 有写入记录 ✅
- 手机打开能用(响应式)✅

---

## W4 — Flutter 内测 + 移动端报表 (v0.1.2 mobile-only)

> **v0.1.2 调整**: 原计划"数据导入 + 报表 + 内测"包含 web admin 报表 UI, 现在 web admin 报表**后补** (等主人解冻)。本阶段专注 Flutter 移动端报表 + 内测。

### 任务
- [ ] **Flutter 移动端报表** (主):
  - 客户总数 / 活跃客户数 (dashboard 上)
  - 月度到店次数 (跟进完成统计)
  - 项目分布(肩颈 / 艾灸 / 拔罐 各占多少) — fl_chart
  - 客户复购周期分布 — fl_chart
- [ ] 报表 UI (Flutter):fl_chart 图表 (`flutter_app/lib/screens/reports/`)
- [ ] Excel 导入工具:把旧系统的客户 / 历史记录导入新表 (data 层; UI 在 Flutter 做基础, web admin 后续补)
- [ ] 数据校验:导入时检查重复 + 不完整字段 (backend + Flutter 校验)
- [ ] **内部 Flutter 内测**:邀请 1 个销售试用 1 周 (装 APK 到手机)
- [ ] 收集反馈 → 修复 bug → 优化体验
- [ ] ❄ web admin 报表 UI **不做** (CHARTER §4.4 freeze-keep)

### 验收
- Flutter 12 screen + 报表页在手机跑过 ✅
- 4 个基础报表在 Flutter 上可看 ✅
- 1 个销售试用 1 周没遇到严重 bug ✅
- ❄ web admin 报表验收跳过 (冻结期)

---

## W5-6 — 部署 + 备份 + Flutter APK 销售内测 (v0.1.2 mobile-only)

### W5 任务
- [ ] 部署到主人自有物理服务器
- [ ] Nginx 反向代理 + HTTPS (Let's Encrypt)
- [ ] 域名解析(可选)
- [ ] 部署文档 `docs/deploy.md`
- [ ] 备份脚本 `tools/backup.sh`(每日全量 + 加密)
- [ ] 备份恢复演练
- [ ] 监控:Postgres 健康 + 磁盘空间 + 服务存活
- [ ] ❄ Web admin 部署照常, 不下线, 不加新功能

### W6 任务 (mobile-only)
- [ ] **邀请 1-2 个销售真用户装 Flutter APK** (主入口)
- [ ] 收集反馈 + bug 修复 (Flutter 优先; web admin 仅 P0 fix)
- [ ] 性能优化:慢查询索引 + 加密字段缓存
- [ ] 写运维 SOP:`tools/SOP.md`
- [ ] 用户手册 `docs/user-manual.md` — Flutter 优先
- [ ] Phase 1 总结 → 决定是否进 Phase 2

### 解冻检查 (master-decide, §4.4.3)

W6 销售内测通过**不强制触发** web 解冻。解冻需主人 ask_user 明确说「移动端 OK, 解冻 web」。解冻前参考检查:

- [ ] Flutter 12 screen 真机跑过
- [ ] 销售愿意用 (1-2 真用户日常)
- [ ] AI Copilot (Phase 2) 可用

### 验收
- 自有服务器 7x24 稳定运行 ✅
- 备份恢复演练成功 ✅
- **1-2 个销售能日常用 Flutter APK** (录入养生记录 / 跟进客户) ✅
- ❄ Web admin 内测验收跳过 (冻结期)

---

## 每周仪式

- **周一**:周计划在 pi 里描述 + 主人 OK → 开始
- **周三**:中期检查点
- **周五**:周验收 + git commit + 汇报主人

## 风险 & 兜底

| 风险 | 兜底 |
|---|---|
| Drizzle + 复杂 JSONB schema 不顺 | 降级到 Prisma |
| 手机验证码阿里云集成出问题 | 降级到邮箱 + 临时密码 |
| 字段加密影响性能太重 | 减少加密字段(只加密最高敏感的) |
| 自有服务器硬件故障 | 双机热备(Phase 2) / 每日异地备份 |
| 销售不愿用 | 现场陪跑 1 周 + 简化录入流程 |

## 不在 Phase 1 范围(明确排除)

- ❌ AI Copilot (Phase 2, 主公 Flutter)
- ❌ 多门店管理 (Phase 2)
- ❌ 多租户 SaaS (Phase 3)
- ❌ **Web admin 新 UI 功能** (v0.1.2 freeze-keep, CHARTER §4.4.1, 后续 web 解冻后恢复)
- ❌ 收银 / 库存 / 财务 (不做 ERP)
- ❌ 微信集成(Phase 2 或后期)

> **v0.1.2 变更说明**: 原计划"移动 App (PWA, Phase 3)"已调整为 **Flutter APK 主战场** (W2-3 已交付 12 screen 骨架, W3-W6 重点修). Phase 3 不再需要 PWA.

## 决策点

W3 末:是否进 W4(Flutter 内测 + 移动端报表)?
- 如果 Flutter 移动端不愿用 → 推迟,先优化 UX
- 如果能用但慢 → 优化后再进 W4
- 如果一切顺利 → 进 W4

W6 末:是否进 Phase 2 (AI Copilot)?
- 取决于销售是否形成使用习惯 + AI 是否真能帮上忙
- 拍板:主人

W6 末:是否解冻 web admin (master-decide, §4.4.3)?
- 主人 ask_user 中明确说「移动端 OK, 解冻 web」才解冻
- 解冻后: CHARTER v0.2.x (移除 §4.4 freeze 段) + ADR-0006 写解冻执行计划 + web admin client 一次性 catch-up sync
- 拍板:主人