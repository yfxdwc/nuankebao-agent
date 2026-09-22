# ADR-0008: APK 域 + WEB 域功能清单与协作关系

**日期**: 2026-09-13
**状态**: ✅ Accepted (主人 2026-09-13 ask 澄清)
**决策者**: 主人 (虾王)
**影响范围**: 双域定位 + 功能边界 + 协作流程 + 部署策略
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §4 (待 v0.1.4 同步更新)

---

## 上下文

本决策对应元宪法:

- [`CHARTER.md`](../CHARTER.md) §4 域划分 (v0.1.3 抽象版)
- [ADR-0007 底座 + 模块化插件架构](0007-modular-architecture.md) (APK 域内模块结构)
- [ADR-0005 mobile-only 阶段](0005-mobile-only-phase.md) (web admin freeze-keep 历史)

---

## 问题

v0.1.3 [CHARTER §4](../CHARTER.md) 写的是**抽象**双域定位（"APK 域 = 主产品" vs "WEB 域 = 脚手架"），但:

1. **功能清单模糊**——不知道每个域具体做什么
2. **关系不明确**——两域怎么交互？通过什么？边界在哪？
3. **部署策略模糊**——APK 域在主人机器跑吗？WEB 域呢？
4. **主人 2026-09-13 ask 澄清**："不是模式不同，开发域 (web) 和生产域 (apk) 是共存同时的"——意味着**两域不是切换**，而是**永远共存**

本 ADR 把 v0.1.3 抽象的双域定位**细化到具体功能 + 关系 + 边界**。

---

## 决策

### 主人 2026-09-13 拍板澄清:

| 边界 | 拍板 | 含义 |
|---|---|---|
| **APK 域 = 生产域** | ✅ 明确 | 销售员日常用的 Flutter app, 独立 native dev cycle |
| **WEB 域 = 开发域** | ✅ 明确 | 主人自用脚手架 (admin / dev / app-preview), 跑 production mode 永久 |
| **两域共存** | ✅ 明确 | 不是 dev↔prod 切换, 是同一台机器同时跑两个域 |
| **共享后端 API** | ✅ 隐含 | 两域都通过 Drizzle schema + Next.js Route Handlers 拿数据 |

---

## 1. 双域定位 (一图概览)

```
┌─────────────────────────── 主人机器 (tc) ───────────────────────────┐
│                                                                       │
│  ┌─ 生产域 = APK (Flutter app) ─────────────────────────────────┐  │
│  │  • 用户: 销售员 + 客服 (中年女性为主, 移动端重度)               │  │
│  │  • 入口: Flutter app 安装到手机 (nuankebao-v0.1.0.apk)         │  │
│  │  • 角色: 主人 OWNED 的"用户面"产品                              │  │
│  │  • dev cycle: Android Studio + flutter run (USB 真机)            │  │
│  │  • 不跑在主人 web server, 独立 .apk 安装                         │  │
│  │  • 通过 HTTP API (3003) 跟后端交互                               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─ 开发域 = WEB 端 (主人自用脚手架) ─────────────────────────────┐  │
│  │  • 用户: 主人 / agent (查 / 看 / 监控 / 开发)                   │  │
│  │  • 入口: 浏览器 → https://nuankebao.tooyang.top/             │  │
│  │  • 角色: 主人 OWNED 的"开发面"工具                              │  │
│  │  • dev cycle: 改代码 → pnpm dev (hot reload) → pnpm build && pnpm start │  │
│  │  • 跑在主人机器 Next.js server (production mode 永久)            │  │
│  │  • ⚠ 应该永久 production (脚手架稳定, 不需 hot reload)         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─ 共享后端 API (Next.js Route Handlers + Drizzle) ─────────────┐  │
│  │  • /api/auth, /api/customers, /api/wellness-records, ...        │  │
│  │  • Drizzle schema (13 表) → PostgreSQL 16                       │  │
│  │  • 字段加密 (pgcrypto) + 审计 (5 触发器)                        │  │
│  │  • 两个域都通过这层拿数据 (真理源)                               │  │
│  └────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 2. APK 域功能清单 (生产域 = 销售员 Flutter app)

### 2.1 用户画像

- **主**: 销售员 + 客服 (中年女性为主, 移动端重度使用)
- **次**: 门店老板 / 店长 (看报表 + 团队管理)
- **场景**: 在家 / 在路上 / 在客户身边 (不在工位)

### 2.2 功能清单 (7 业务模块)

| # | 模块 | 入口 screen | 核心交互 |
|---|---|---|---|
| 1 | **auth** (登录) | `modules/auth/screens/login_screen.dart` | 手机号 + 验证码 (W1 mock, W2+ 真实 SMS) |
| 2 | **customer** (客户档案) | `modules/customer/screens/customers_page.dart` + `customer_detail_page.dart` + `customer_form_page.dart` | 列表 + 搜索 + 详情时间线 + 新增/编辑 |
| 3 | **wellness** (养生记录) | `modules/wellness/screens/wellness_record_form_page.dart` + `wellness_record_detail_page.dart` | 结构化表单 (部位/状态/用料/效果) + 拍照 + 详情 |
| 4 | **follow_up** (跟进任务) | (集成在 customer_detail_page 时间线, 占位) | 按到期时间分组 (W4 抽独立模块) |
| 5 | **presentation** (图谱 + 列表) | graph 渲染 + list 组件 (跨模块复用) | CustomPainter 画加盟树 + 通用列表组件 |
| 6 | **relation** ★ (客户/加盟关系) | `modules/relation/screens/franchise_tree_page.dart` + `franchisee_detail_page.dart` + `add_franchisee_page.dart` | 二叉树图谱 + 节点详情 + 新增加盟商 + ⚠ RelationSystem 接口 |
| 7 | **meeting** (会议组织) | (占位, 未实施) | W4+ 启动时拍板 |

### 2.3 技术栈

```
- Flutter 3.24+ / Dart 3.4+
- 状态管理: flutter_riverpod 2.5
- 路由: go_router 14.6
- HTTP: dio 5.7 + dio 拦截器 (auto cookie)
- 数据类: freezed 2.4 + json_serializable
- 安全存储: flutter_secure_storage 9.2
- 拍照: image_picker 1.1
- 图表: fl_chart 0.69
- 主题: Material 3 养生绿
```

### 2.4 APK 域目录结构 (v0.1.3 落地)

```
flutter_app/lib/
├── core/                          ← ★ APK 底座 (不可替换)
│   ├── router/ providers/ http/ services/ theme/ models/ widgets/
└── modules/                       ← ★ 业务模块 (可独立替换/改进)
    ├── auth/ customer/ wellness/ follow_up/ (占位)
    ├── presentation/ relation/ ★ meeting/ (占位)
```

---

## 3. WEB 域功能清单 (开发域 = 主人自用脚手架)

### 3.1 用户画像

- **主**: 主人 (开发 / 监控 / 部署 / 调试)
- **次**: agent (接 pi / Codex / future agent)
- **场景**: 主人 SSH 到机器后浏览器访问, 或远程调试

### 3.2 功能清单 (按路径分组)

| # | 路径 | 状态 | 用途 | 用户 |
|---|---|---|---|---|
| 1 | **`/admin/*`** (16 页) | ❄ **冻结** (v0.1.2 freeze-keep) | 销售员产品 web admin (仪表盘 + 客户管理 + 养生记录 + 跟进 + 联系 + 报表 + 导入 + AI + App 下载) | 主人 (历史遗留) |
| 2 | **`/admin/dev`** (v0.1.3 新, v0.1.4 迁入 admin) | ✅ 活跃 | 主人开发工具门户 (3 卡片: architecture / deploy / snapshot), 老 /dev URL 重定向到此 | 主人 |
| 3 | **`/admin/dev/architecture`** | ✅ 活跃 (v0.1.3 新) | 渲染 CHARTER §4.1 文字图为 mermaid SVG | 主人 |
| 4 | **`/admin/dev/deploy`** | ✅ 活跃 (v0.1.3 新) | 读取 backup-health/*.json 显示备份状态 + PG 备份列表 + 日志 | 主人 |
| 5 | **`/admin/dev/snapshot`** + `[tag]` | ✅ 活跃 (v0.1.3 新) | 任务快照列表 + 详情 + rollback | 主人 |
| 6 | **`/app-preview`** | ✅ 活跃 (v0.1.3 维护) | Flutter web 编译产物 iframe 嵌入 (手机端预览) | 主人 |
| 7 | **`/login`** | ✅ 活跃 | Flutter web + Web 共用登录页 | 销售员 (web 罕见) |
| 8 | **`/`** (根) | ✅ 重定向 | 重定向到 /admin (或 /login 未登录) | — |
| 9 | **`/download`** | ✅ 活跃 | APK 下载页 (销售员装机) | 销售员 |

### 3.3 技术栈

```
- Next.js 15 (App Router) + React 18.3
- UI: shadcn/ui (Radix UI Primitives + Tailwind CSS)
- 样式: Tailwind CSS 3.4 + tailwindcss-animate
- 数据: Drizzle ORM 0.36 + PostgreSQL 16
- 认证: Auth.js v5 (beta) + 手机号验证码 (W2+ 阿里云)
- AI: Vercel AI SDK 3.4 + MiniMax provider
- 加密: pgcrypto (字段) + AES-256-CBC (应用层)
- 部署: Docker Compose (postgres + next.js + nginx)
```

### 3.4 WEB 域目录结构

```
src/
├── app/
│   ├── api/                      ← Route Handlers (共享后端)
│   ├── (auth)/login/             ← /login (Flutter + Web 共用)
│   ├── app-preview/              ← /app-preview (Flutter web iframe)
│   ├── preview/                  ← /preview (旧路径, 待并入)
│   ├── admin/                    ← /admin (❄ 冻结, freeze-keep)
│   ├── dev/                      ← /dev (✅ 活跃, 主人自用)
│   │   ├── architecture/
│   │   ├── deploy/
│   │   └── snapshot/
│   └── download/                 ← /download (APK 下载)
├── components/
│   ├── ui/                       ← shadcn 组件 (活跃)
│   ├── admin/                    ← ❄ 冻结
│   ├── business/                 ← ❄ 冻结
│   ├── auth/                     ← 活跃 (login-form)
│   └── preview/                  ← /app-preview 用的
├── lib/                          ← 业务逻辑 (共享后端)
│   ├── db/ ai/ crypto/ auth/ audit/
├── hooks/ styles/
└── middleware.ts
```

---

## 4. 两域关系 (核心)

### 4.1 数据共享 (通过后端 API)

```
[APK Flutter app]  ──HTTP+cookie──>  [Next.js Route Handlers /api/*]
[WEB /admin /dev]  ──HTTP+cookie──>  [同上]
                                            ↓ Drizzle ORM
                                    [PostgreSQL 16]
                                    (Drizzle schema 是真理源)
```

**关键**: 两域**不直接互相调用**，都通过**共享后端 API**。

### 4.2 边界规则 (AGENTS §4.5 + CHARTER §4.3)

| 边界 | 规则 |
|---|---|
| APK 域 ↔ WEB 域 | ❌ **不直接互调** — 都通过 /api/* 后端 |
| WEB 域 /admin/* ↔ /admin/dev/* | ✅ **同域** — /admin/dev 物理位置在 /admin 下, 侧栏统一导航 (v0.1.4 master-decide 集成); 老 /dev URL 重定向到 /admin/dev |
| WEB 域 /admin ↔ /app-preview | ❌ **不互调** — admin 是产品, app-preview 是 Flutter web 预览 |
| WEB 域 /dev ↔ /app-preview | ❌ **不互调** — dev 是工具, app-preview 是预览 |
| 共享后端 /api/* ↔ 任何域 | ✅ **两域都调** — 这是唯一共享层 |
| APK 域内部 modules/ | ✅ **跨模块通过 core/ 底座** (per AGENTS §4.5) |
| WEB 域跨 process | ❌ **禁止直接 import** — 都通过 /api/* 共享层 |

### 4.3 认证共享

- 两域共用 **Auth.js v5 session cookie**
- 登录后 cookie 自动跨域共享 (同源同站)
- 销售员 APK 登录后, 主人浏览器同站访问 /admin 也已登录

### 4.4 部署关系 (关键)

```
主人机器 (tc):
  ┌─ Next.js server (3003, production mode 永久) ─────────┐
  │  • Next.js 15 (master + 6 systemd 重启备)               │
  │  • 含 /api/* + /admin + /dev + /app-preview            │
  │  • 跑 production mode (主人自用, 秒开)                  │
  └────────────────────────────────────────────────────────┘
                ↑ HTTP (3003)
                │
  ┌─ PostgreSQL 16 (5432) ──────────────────────────────────┐
  │  • Drizzle schema (13 表)                              │
  │  • 字段加密 + 审计触发器                                │
  └────────────────────────────────────────────────────────┘
                ↑ SQL
                │
  ┌─ Flutter SDK (本地, W4+ 主人装) ────────────────────────┐
  │  • flutter run (USB 真机调试)                          │
  │  • flutter build apk (出 .apk 给销售员)                  │
  └────────────────────────────────────────────────────────┘
                ↑
                │ 销售员手机装机
                │
  ┌─ 销售员 APK (生产域用户面) ─────────────────────────────┐
  │  • Flutter app (.apk 安装)                              │
  │  • 通过 cloudflared tunnel 访问 nuankebao.tooyang.top │
  │  • HTTP API 拿数据                                      │
  └────────────────────────────────────────────────────────┘
```

---

## 5. 协作场景 (典型流程)

### 5.1 主人开发 Flutter 功能 (APK 域)

```
1. 主人 VSCode / Android Studio 改 flutter_app/lib/modules/<module>/*.dart
2. flutter run (USB 真机) → 主人手机看 hot reload 效果
3. 主人满意 → flutter build apk → 出 .apk
4. 主人 cp .apk 到 /tmp/NUANKEBAO-release.apk + 更新 /admin/download
5. 主人 git commit + push
6. 销售员扫码装机
```

**APK 域 dev cycle 独立**，不影响 WEB 域 server。

### 5.2 主人开发 WEB 功能 (WEB 域)

```
1. 主人 VSCode 改 src/app/<page>/*.tsx + src/components/**/*.tsx
2. pnpm dev (临时 hot reload, 主人自己用) → 浏览器刷看效果
3. 主人满意 → git commit
4. pnpm build && pnpm start (production mode 永久跑)
5. (或者) systemctl --user restart nuankebao-nextjs.service
6. 主人浏览器刷公网 https://nuankebao.tooyang.top/dev 看效果
```

**WEB 域 dev cycle** 是临时 (主人改代码时) → production 永久。

### 5.3 主人监控备份

```
1. 主人浏览器开 https://nuankebao.tooyang.top/admin/dev/deploy
2. 看 backup-health/*.json → 上次备份时间 / 状态 / GFS 副本数
3. 看 backup.log 最近 20 行 → 排错
4. 不需要登录 ssh
```

**WEB 域 /dev 永远 production mode 跑**，主人随时访问。

### 5.4 销售员使用 APK (生产域用户)

```
1. 销售员扫码装 APK 到手机
2. 启动 app → 登录 (手机号 + 验证码)
3. 客户列表 → 详情 → 录养生 → 拍照
4. HTTP API (3003) → cloudflared tunnel → 主人机器 Next.js → Drizzle → Postgres
5. 数据落 PostgreSQL + 审计触发器 + 备份 (deploy/backup.sh 日 03:00)
```

**APK 域用户**不需要知道 WEB 域存在。

---

## 6. 冻结 vs 活跃 (per CHARTER §4.4)

> ⚠️ **2026-09-22 更新 (ADR-0017)**: web admin 已解冻, 下表 `/admin/*` 由 ❄ 冻结 改为 ✅ 活跃。
> 本节保留两列 (现状 + 历史) 供回溯。

| 路径 / 模块 | 状态 | 说明 |
|---|---|---|
| WEB /admin/* | ✅ 活跃 (2026-09-22 解冻, ADR-0017) | 销售员产品 admin web; 解冻前为 ❄ 冻结 (v0.1.2) |
| WEB /admin/dev/* | ✅ 活跃 (v0.1.3, v0.1.4 迁入 admin) | 主人开发工具 (master-decide 集成到 admin 侧栏) |
| WEB /app-preview | ✅ 活跃 (v0.1.3) | Flutter web 预览 |
| WEB /login | ✅ 活跃 | Flutter + Web 共用 |
| WEB /api/* | ✅ 活跃 | 后端 API (两域共享) |
| APK modules/* | ✅ 活跃 | 7 模块 (auth / customer / wellness / follow_up / presentation / relation / salon) |

**解冻后规则** (per CHARTER §4.4 v0.1.5 + ADR-0017):
- /admin 可加新页面 / 新交互 / 新组件 (管理与分析功能为主)
- backend / schema 双线同步: Flutter + web admin 同批更新, `pnpm type-check` 必过
- 解冻 ≠ 重做: 存量页面不做大规模重构
- /app-preview 仍属 preview framework 冻结 (ADR-0009, 独立机制)

**活跃规则** (per v0.1.3 + 本 ADR):
- /dev 主人自用, 不算 admin 冻结范围
- /app-preview 维护模式, 跟随 Flutter SDK 更新
- /api/* 必须跟随 backend schema 同步 (CHARTER §3.5 红线)

---

## 7. 不变 (按主人 2026-09-13 ask 澄清)

- ❌ **不是 dev↔prod 切换** — 两域**永远共存**
- ❌ **WEB 域不需要 hot reload** — 脚手架稳定, production mode 永久跑
- ❌ **APK 域不在主人 web server 跑** — Flutter native dev, 独立 .apk 安装
- ✅ **共享后端 API** — Drizzle schema 是真理源, 两域都通过 /api/* 拿数据
- ✅ **共享认证** — Auth.js v5 session cookie, 跨域共享

---

## 8. 候选评估

### 候选 A: 单体仓库 + 双域共存 (本决策, 采纳)

- ✅ 主人 v0.1.3 已拍板
- ✅ 简单, 部署明确
- ✅ 后端 API 共享, 数据一致
- ⚠ WEB 域 /admin 已解冻 (2026-09-22, ADR-0017), 恢复管理与分析功能开发

### 候选 B: 拆 monorepo (APK + WEB 各独立仓库)

- ❌ 跟 ADR-0005 + 0007 矛盾
- ❌ 单 owner 个人项目, 拆仓库增加复杂度
- ❌ 后端 API 还是共享, 拆仓库意义不大

### 候选 C: 只做 APK, 不做 WEB

- ❌ WEB 域工具 (admin / dev / app-preview) 是主人自用, 必须有
- ❌ v0.1.0 已有 admin web, 完全删掉破坏大

### 选定: 候选 A (主人拍板)

---

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 主人误在 WEB 域跑 `pnpm dev` 跟 APK dev 混淆 | 主人拍板: WEB 域一直 production; agent 不主动跑 `pnpm dev` |
| APK 域 Flutter 改完没 rebuild .apk | 主人看 /download 页 + 真机验证 (Phase 1 验收) |
| WEB 域 /admin 冻结太久导致技术债 | 主人拍板 web 解冻 (per CHARTER §4.4.3 master-decide) |
| 后端 /api/* schema 改 → APK 老版本崩 | CHARTER §3.5 红线 (migration 不向后兼容 = 阻断) |
| cloudflared tunnel 配错 / DNS 漏 | 主人手工配 Dashboard; `tools/fix-nuankebao-deploy.sh` 一键修复 |

---

## 10. 关联文档

- [CHARTER.md §4 域划分](../CHARTER.md) (本 ADR 落地元宪法, 待 v0.1.4 同步)
- [ADR-0007 底座 + 模块化插件](0007-modular-architecture.md) (APK 域模块结构)
- [ADR-0005 mobile-only 阶段](0005-mobile-only-phase.md) (web admin freeze 历史)
- [AGENTS.md §4 文件组织](../../AGENTS.md) (具体路径)
- [AGENTS.md §4.5 模块化约束](../../AGENTS.md) (跨域边界规则)
- [docs/architecture/v0.1.3-final.md](../architecture/v0.1.3-final.md) (v0.1.3 总结)

---

## 11. 元数据

- **ADR 编号**: 0008
- **拍板日期**: 2026-09-13
- **写入位置**: `docs/adr/0008-apk-web-domain-spec.md` (项目书)
- **同步**: CHARTER §4 (待 v0.1.4) + AGENTS §4 (引用本 ADR)

---

**变更记录**:
- 2026-09-13: 创建 (主人 ask 澄清: 两域共存, 不是切换)
