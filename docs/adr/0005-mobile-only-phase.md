# ADR-0005: Mobile-Only 阶段 (web admin 冻结 + flutter-only-sync)

**日期**: 2026-09-07
**状态**: ⚠️ Superseded (部分) — freeze-keep + flutter-only-sync 段已被 [ADR-0017](./0017-web-admin-unfreeze.md) (2026-09-22) 取代; 本 ADR 保留作为历史决策记录
**决策者**: 主人 (虾王)
**影响范围**: 整个 frontend 策略 + Phase 1 实施节奏 + 后续 git commit 模式
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §4.4 (v0.1.2) + §10.2 变更记录

## 上下文

本决策对应元宪法:

- [`CHARTER.md`](../CHARTER.md) **§2 原则 3** (移动优先 > 桌面优先) — 移动端是主战场
- [`CHARTER.md`](../CHARTER.md) **§2 原则 7** (小步快跑 > 一次大跃) — 一次只做一个方向, 避免双线分散精力
- [`CHARTER.md`](../CHARTER.md) **§4.3** (前端策略 apk-first) — 销售侧默认 Flutter
- [`CHARTER.md`](../CHARTER.md) **§5.2** (必须 ask_user L1 战略决策) — 整体前端策略大改属 L1

---

## 问题

### 历史观察 (2026-09-03 → 2026-09-07)

W1-W3 期间, 项目"Flutter + Next.js admin"双线并行:

- ✅ Flutter: 12 screen 完成, 5 个 service, freezed models, theme, go_router
- ✅ Next.js admin: 16 page 完成, 12 业务组件, mobile-first 重构 (FAB / tab / 时间线 / infinite scroll / AI 二级选择)

但双线带来 4 个实际问题:

1. **精力分散**: 一个 agent 同时维护 Flutter + Web admin, 上下文切换频繁, 主人多次看到 mobile 体验细节被 web 重构挤掉
2. **策略冲突**: 主人 2026-09-04 拍板 apk-first (销售侧默认 Flutter), 但 09-04 → 09-07 期间 git log 显示 `feat(admin): 4 项 mobile 增强` / `feat(admin): 6 个子页 mobile-first 重构` —— 这些**销售侧**功能也在 web admin 做了一遍, 违反 apk-first 精神
3. **web 资源浪费**: W3 投入 ~40% 精力做 mobile-friendly 的 web admin UI, 但销售员日常在手机, web admin 实际使用率会极低 (Phase 1 单门店 1-2 销售内测场景)
4. **主人干预成本高**: 每次开新 feature, 都要判断「这条改 Flutter 还是 web」, 主人被琐碎决策打扰

### 触发本决策的引子

主人 2026-09-07 直接指示:

> "接下来开发只开发移动端, web 端服务等移动端开发完成后再补"

这是一句 L1 战略决策, 需要细化三个边界:

1. **web admin 怎么存在**? (删 / 隐藏 / 冻结保留 / 拆分支)
2. **解冻条件是什么**? (Phase 1 完成 / 功能对齐 / 主人手动)
3. **backend / schema 同步策略**? (auto-both 不变 / 只同步 Flutter / 其他)

---

## 决策

主人 2026-09-07 ask_user 三项拍板 (本 ADR 的核心):

| 边界 | 拍板 | 缩写 |
|---|---|---|
| 1. web admin 命运 | **冻结但保持运行** (代码保留 / 部署照常 / 不加新 UI / 仅 P0 bug) | `freeze-keep` |
| 2. 解冻条件 | **主人手动拍板** (无预定义里程碑) | `master-decide` |
| 3. backend / schema 同步 | **只同步 Flutter** (schema 必同步两边 / API 改动 web client 暂停 / 类型 catch-up 推迟) | `flutter-only-sync` |

落地为 CHARTER §4.4 (v0.1.2) 4 段:

- **§4.4.1** web admin 状态 — freeze-keep
- **§4.4.2** backend / schema 同步策略 — flutter-only-sync
- **§4.4.3** 解冻条件 — master-decide
- **§4.4.4** 当前 active 目录清单 (让 agent 知道能动哪)
- **§4.4.5** 误判处理 (5 个常见场景的判例)

---

## 候选评估

### 候选 A: 双线继续 (维持现状)

- ✅ 灵活性最高 (任何 feature 可选 Flutter 或 Web)
- ❌ 违反 apk-first 实际效果 (双线投入产出一边)
- ❌ 主人反复被琐碎决策打扰
- ❌ 移动端体验被 web 重构挤掉

**结论**: ❌ 排除

### 候选 B: 拆 monorepo (Flutter + Web 各自完整)

- ✅ 边界清晰
- ✅ 两边可独立部署
- ❌ W2 早期拆 = 一次大跃 (违反原则 7)
- ❌ NuankeBao 单 owner 个人项目, monorepo 工具链成本高
- ❌ Flutter + Backend 仍是同仓 (API 类型同步不便)

**结论**: ❌ 排除

### 候选 C: Mobile-Only + freeze-keep + flutter-only-sync (本决策)

- ✅ 主人一句话落地清晰
- ✅ agent 自治空间足够 (§4.4.4 + §4.4.5 边界明确)
- ✅ 解冻机制明确 (master-decide, 不绑死里程碑)
- ✅ 投入产出聚焦移动端 (销售真正用的入口)
- ⚠️ web 解冻时需一次性 catch-up (catch-up 工作量待估)
- ⚠️ 误判 5 类场景需要主人 / agent 共同判断 (§4.4.5)

**结论**: ⭐⭐⭐⭐⭐ 采纳

### 候选 D: 拆分支保存 web

- ✅ web 完全隔离, 主干干净
- ❌ 主人拍 freeze-keep, 不是 remove
- ❌ 拆分支后, 主人想问 web 现状还要切换分支, 摩擦高

**结论**: ❌ 排除 (主人明确选 freeze-keep)

---

## 影响

### 立即生效 (2026-09-07 起)

- ✅ `docs/CHARTER.md` v0.1.2 升级 (§4.3 + §4.4 + §7 + §10)
- ✅ `AGENTS.md` §3 同步策略改写 + §5 反模式 +2 条 + §7 路线图调整
- ✅ `docs/phase-1-mvp.md` W2-3 / W4 / W5-6 优先级调整 (本 ADR 同步触发)
- ✅ `README.md` 加"当前策略"段 (让主人快速看到)
- ✅ `CHANGELOG.md` [Unreleased] 加 mobile-only 决策条目

### 节奏变化

| 之前 | 现在 |
|---|---|
| Flutter + Web admin 双线推进 | Flutter 单线 (释放 ~40% 精力) |
| 1 个 feature 选 Flutter 还是 Web | 默认 Flutter (无选择成本) |
| Web admin mobile-first 重构 | web 冻结, 不再加 UI 功能 |
| Backend 改 → 同步 Flutter + Web | Backend 改 → 同步 Flutter (web 解冻时 catch-up) |

### 风险 + 缓解

| 风险 | 缓解 |
|---|---|
| web 解冻时 catch-up 工作量大 | 解冻时 (master-decide 时点) 估工作量 + ADR 拍板执行顺序 |
| 主人突然想加一个 web 功能 | §4.4.5 第 5 行: 主人明确说「这个 web 也要」= override, commit message 标注 |
| web 解冻后两端 type drift | 解冻后第一周 = type-only sync PR, 不带功能改动 |
| 销售内测期间 web admin 出 bug | §4.4.1 仅 P0 fix: 影响销售登录/数据/安全的才修, 其他攒到解冻 |
| API 改了 web admin 编译挂 | §4.4.5 第 3 行: schema-driven UI 改动允许, 不算新功能 |

---

## 后续行动

### 立即 (本 ADR 通过后 1 天内)

- [x] 写本 ADR
- [x] 升 `docs/CHARTER.md` 到 v0.1.2
- [x] 改 `AGENTS.md` §3 / §5 / §7
- [x] 改 `docs/phase-1-mvp.md` 优先级
- [x] `CHANGELOG.md` [Unreleased] 条目
- [x] `README.md` 当前策略段

### 解冻时 (master-decide 时点, 时间不定)

- [ ] 主人 ask_user 拍板解冻 + 估 catch-up 工作量
- [ ] 写 ADR-0006 解冻执行计划
- [ ] web admin client (类型 / 调用) catch-up sync (一次性 PR)
- [ ] 主人 review 后恢复双线推进
- [ ] 升 CHARTER v0.2.x (移除 §4.4 freeze 段)

---

## 参考

- [`docs/CHARTER.md`](../CHARTER.md) §4.4 (本 ADR 元宪法落地)
- [`docs/adr/0003-flutter-dev-workflow.md`](0003-flutter-dev-workflow.md) (Web + Phone 仍并行, 不冲突)
- [`docs/adr/0004-schema-evolution.md`](0004-schema-evolution.md) (Schema 红线, 同步仍受 §3.5 约束)
- AGENTS.md §3 同步策略段 (操作层落地)
- AGENTS.md §5 反模式最后 2 条 (mobile-only 阶段硬约束)