# BBT v0.1.0 Release Notes

> **发布日期**: 2026-09-04
> **代号**: "养生绿" (Wellness Green)
> **状态**: Phase 1 MVP + Phase 1.5 (Flutter 移动端) 完成,待 W6 上架 + 销售内测

## 🎯 这个版本是什么

BBT (Bu Bu Tang 简称, 补补堂) 是**养生行业销售人员的移动 CRM**:
- 客户档案 + 标签
- **结构化养生记录** (部位/状态/用料/效果 + 拍照)
- 跟进任务 + AI 智能建议
- 数据自托管 + 字段加密

**不是**: 传统 CRM 销售漏斗 / 复杂 dashboard / SaaS 黑洞

## ✨ 核心功能

### 销售端 (Flutter App)
- 📱 移动端 native 体验 (iOS + Android, 跨平台像素级一致)
- 🔐 手机号 + 验证码登录 (开发期 mock 123456)
- 👤 客户管理 (增/查/改/删, 健康标签多选)
- 💆 养生记录结构化表单 (9 部位 + 8 项目 + 8 耗材 + 状态评分 + 拍照)
- 🔔 跟进任务 (按到期时间分组: 逾期/今天/本周/更晚, 过期红色高亮)
- 🤖 AI 客户画像 + 跟进话术 (MiniMax API, 无 key 时走 mock)
- 📷 拍照 (image_picker, base64 上传, 最多 9 张)
- 📊 仪表盘 (4 统计 + 项目分布饼图)

### 管理端 (Next.js Web)
- 🖥️ 老板/店长用 PC 管理
- 📋 报表中心 (月度趋势 + 复购周期 + 客户活跃度)
- 📥 Excel 客户导入 (字段校验 + 去重 + 模板下载)
- 🛡️ 审计日志查询 (谁改了什么)

### 后端 (Next.js API + Postgres)
- 🔐 AES-256-CBC 字段加密 (手机号/健康/疾病/记录摘要/反馈)
- 📋 5 个审计触发器 (INSERT/UPDATE/DELETE 全记录 + user_id + IP)
- 🤖 MiniMax AI 集成 (mock fallback 永远能跑)
- 💾 16 个 API 端点 (REST + Zod 验证)
- 📤 照片上传 (5MB 限制, jpeg/png/webp)
- 📊 完整查询 (含分桶复购周期 + 月度连续 6 月)

### 部署
- 🐳 Docker Compose 一键起 (Postgres + Web)
- 🔒 Nginx + Let's Encrypt HTTPS
- 💾 自动备份 (gpg 加密 + 30 天保留 + rclone 异地)
- 🔄 灾难恢复 (5 分钟可恢复)
- 📊 36 个测试 (29 Vitest + 7 Playwright E2E)
- 🛠️ 完整运维 SOP (故障排查 5 个常见场景)

## 🔢 数据规模

| 实体 | 数量 | 加密 |
|---|---|---|
| 用户 (user) | 1+ | - |
| 客户 (customer) | ∞ | phone / healthTags / diseaseHistory / notes |
| 养生记录 (wellness_record) | ∞ | pre/postCondition / processNote / feedback |
| 跟进任务 (follow_up_task) | ∞ | aiSuggestion / completedNotes |
| 联系记录 (interaction) | ∞ | summary |
| 审计日志 (audit_log) | 自动 | - |

**字典数据** (seed):
- 9 个身体部位 (肩颈/腰部/膝盖 等)
- 8 个服务项目 (肩颈经络/艾灸/拔罐/推拿 等)
- 8 个耗材 (艾草精油/生姜精油/热敷包/艾条 等)

## 🚀 快速开始

### 后端
```bash
pnpm install
cp .env.example .env.local
# 编辑 .env.local: POSTGRES_PASSWORD / AUTH_SECRET / PGCRYPTO_KEY
docker compose up -d postgres
pnpm db:migrate
pnpm db:seed
pnpm dev
# → http://localhost:3003
```

### Flutter App
```bash
# 装 Flutter SDK (主人首次需要, ~700MB)
# 见 flutter_app/README.md

cd flutter_app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run  # 需要 Android emulator 或真机
```

### 部署到生产
详见 `docs/deploy.md`:
- 8 章完整指南 (准备 → 部署 → Nginx → 备份 → 监控 → 升级 → 灾难恢复 → 勾选清单)
- `tools/SOP.md` 日常运维
- `tools/backup.sh` + `tools/restore.sh` 自动化脚本

## 🚧 已知限制 (v0.1.0)

- ⚠️ Flutter 端 W6 才能跑 (主人需装 SDK)
- ⚠️ AI 走 mock 模式 (主人需申请 MINIMAX_API_KEY)
- ⚠️ 短信验证码 mock 123456 (W2 接入阿里云 SMS)
- ⚠️ 离线缓存 / 推送通知 (W4 Flutter, 待装 SDK)
- ⚠️ 部署到自有服务器 (W5 物理操作)

## 📊 技术栈

| 层 | 选型 | 理由 |
|---|---|---|
| 后端 | Next.js 15 (Route Handlers) | 单一仓库, API + Admin web 复用 |
| ORM | Drizzle | SQL-first, JSONB 友好 |
| DB | PostgreSQL 16 + pgcrypto + pgvector | 自托管, 字段加密, AI 向量预留 |
| 移动 | Flutter 3.x | 跨平台一致, 性能, 包小 |
| 状态 | Riverpod | 简洁, 类型安全 |
| HTTP | dio | 拦截器支持好 |
| AI | MiniMax (国内) | 数据不出境, 便宜 |
| 测试 | Vitest + Playwright | 单元 + 集成 + E2E |

## 🛡️ 安全合规

- 字段级加密 (AES-256-CBC, 密钥 32 bytes hex)
- 审计触发器 (5 个表, INSERT/UPDATE/DELETE 全记录)
- 自托管 (无第三方数据出境)
- 密钥轮换 SOP (docs/deploy.md §7.3)
- 备份加密 (gpg AES-256)
- SSL/HTTPS (Let's Encrypt)
- 防火墙 (只开 22/80/443)
- PIPL 合规 (用户可导出/删除自己的数据 — W6 完善)

## 📞 反馈

- 觉得功能不够用? 联系店长排进下一版本
- 遇到 bug? 截图 + 文字给店长
- 部署遇到问题? 看 `docs/deploy.md` + `tools/SOP.md`

BBT v0.1.0 — 一切从简, 一切为养生销售 🌿