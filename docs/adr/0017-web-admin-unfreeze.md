# ADR-0017: web admin 解冻 (结束 mobile-only, 恢复双线开发)

**日期**: 2026-09-22
**状态**: ✅ Accepted (主人拍板)
**决策者**: 主人 (虾王)
**影响范围**: 前端策略 (CHARTER §4.4) + AGENTS §3 同步策略 + commit 规范 + 用量分析模块落地位置
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §4.4 (v0.1.5) + §10.2
**Supersedes (部分)**: [ADR-0005](./0005-mobile-only-phase.md) — freeze-keep + flutter-only-sync 段

## 上下文

2026-09-07 主人拍板 mobile-only (ADR-0005): web admin 冻结但保持运行 (freeze-keep),
backend 改动只同步 Flutter (flutter-only-sync), 解冻条件为 master-decide。

2026-09-22, 主人明确拍板:

> 「"web admin 冻结中"这是个错误, 需要解冻结。新模块接入 web admin。」

触发场景: 使用数据采集模块 (usage analytics) 讨论中, 把新模块的查看入口放在 web admin
还是 Flutter admin 页。主人直接否定冻结前提, 要求整段解冻并把新模块接进 web admin。

## 决策

| # | 边界 | 拍板 |
|---|---|---|
| 1 | web admin 状态 | **解冻** — `src/app/admin/**` / `src/components/business/**` / `src/components/admin/**` 全部恢复为可改 (新页面 / 新交互 / 新组件均可) |
| 2 | backend / schema 同步策略 | **恢复双线同步** — schema / API 改动 Flutter service + web admin client 都要同步 (不再 catch-up) |
| 3 | 对存量 web admin 的处理 | 不做大规模重构, 新功能按需增量; 存量页面保持现状 |
| 4 | 解冻后首个模块 | 使用数据采集模块 (usage analytics): migration 0023 + `POST /api/usage/events` + `GET /api/admin/usage/*` + `/admin/usage` 页 |

## 候选评估

### 候选 A: 保持冻结, 新模块只做 Flutter admin 页

- ✅ 遵守 v0.1.2 拍板
- ❌ 主人 2026-09-22 明确说冻结是错误 (L0 级别否定)
- ❌ 用量分析天然是"看报表"场景, web 大屏比手机列表合适
- ❌ 16 个现成 admin 页 + 侧栏/布局资产闲置

**结论**: ❌ 排除 (被主人拍板否定)

### 候选 B: 完全解冻, 恢复双线同步 (本决策)

- ✅ 消除 "这条改 Flutter 还是 web" 的日常判断成本
- ✅ web admin 有完整报表能力, 新分析模块有归处
- ⚠ 双线投入再次分裂精力 (ADR-0005 原始顾虑) — 用「新功能默认单一入口、不要求两边对齐」缓解
- ⚠ 冻结期 backlog 的 web client catch-up 需分批处理 (不一次性大重构)

**结论**: ⭐⭐⭐⭐ 采纳

### 候选 C: 只解冻新模块需要的路径 (白名单解冻)

- ✅ 风险最小
- ❌ 主人原话是"解冻结", 不是"开一个口子"; 白名单又要 agent 每次判边界
- ❌ 冻结期攒的 web 问题会继续攒

**结论**: ❌ 排除

## 落地约定 (解冻后怎么协作)

1. **功能默认单一入口**: 销售侧功能仍以 Flutter 为准 (CHARTER §4.3 apk-first 不变);
   web admin 是**管理与分析**入口 (报表 / 导入 / 审计 / 用量), 不追销售侧功能对齐。
2. **双线同步**: 改 API / schema 时, Flutter service 与 web admin client **同一批**更新;
   `pnpm type-check` 必须过 (catch-up 不再是合法借口)。
3. **提交规范**: commit message 可注明 `[web]` / `[apk]`; 双端改动写清范围。
4. **不回溯大重构**: 冻结期没有大坏掉的页面不动; 解冻 ≠ 重做 web admin。
5. **预览框架冻结不受影响**: `docs/adr/0009` (preview framework freeze) 继续有效, 与 web admin 解冻无关。

## 影响

- ✅ `docs/CHARTER.md` v0.1.5: §4.4 重写 (解冻 + 新协作约定, 保留历史), §4.2 加用量域, §10 版本表/变更记录
- ✅ `AGENTS.md` §3 同步策略改写 + §4 目录标注 (admin 恢复活跃) + §5 两条 mobile-only 反模式加"已解冻"注记
- ✅ `docs/adr/0005-mobile-only-phase.md` 顶部加 Superseded 注记 (历史决策保留)
- ✅ `docs/adr/0008-apk-web-domain-spec.md` §6 冻结表更新
- ✅ `CHANGELOG.md` 记录解冻

## 风险

| 风险 | 缓解 |
|---|---|
| 双线精力分散复发 | 功能默认单一入口 (销售侧 Flutter / 管理侧 web), 不要求两边对齐 |
| 冻结期 web 代码腐化 (依赖漂移) 解冻即炸 | 首次进入时先跑 `pnpm type-check` + 目标页冒烟; 分批 catch-up |
| agent 把"解冻"误读为"重做 web" | 本 ADR 第 4 条: 不回溯大重构 |
| 用量数据隐私风险 | 另见 CHARTER §4.4 用量域红线: release APK 采集 / 无 PII / 自托管 / 180 天保留 |
