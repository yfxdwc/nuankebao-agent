# ui-kit — UI 方案模块 (WEB 域)

> **职责**: WEB 域的 UI 设计系统 (shadcn/ui + Tailwind + 主题 + 业务组件)
> **物理位置**: `src/components/ui/` + `tailwind.config.ts` + `src/styles/`
> **入口**: 17 个 ui 组件 (`src/components/ui/{button,card,...}.tsx`)
> **护栏**: `tests/ui-kit-contract.test.ts` (vitest) + `tools/check-ui-tokens.sh` (棘轮)

## 当前实现

### `src/components/ui/` (17 个组件, B0b 后)

**B0b 业务组件** (2026-09-24 后, 主人拍板的「暖精确」风格):
| 组件 | 文件 | 用途 |
|---|---|---|
| `PageHeader` | `page-header.tsx` | 页面标题 + 描述 + 操作区 |
| `Section` | `section.tsx` | 区块容器 (无边框无阴影, 仅靠 gap 分组) |
| `DataTable` | `data-table.tsx` | 表格 (B 档紧凑专业, 非 SaaS 卡片墙) |
| `EmptyState` | `empty-state.tsx` | 空态组件 (原则 8: 必须告诉下一步做什么) |
| `FilterBar` | `filter-bar.tsx` | 筛选条 (搜索 + 状态 / 类型过滤) |
| `StatRow` | `stat-row.tsx` | 详情页键值对 (等宽数字, divide-y 分隔) |
| `Skeleton` | `skeleton.tsx` | 骨架占位 (无动画, 跟 divide-y 列表配合) |

**shadcn 兼容层** (存量 600+ 处, 继续可用):
| 组件 | 文件 | 用途 |
|---|---|---|
| `Button` | `button.tsx` | 按钮 (primary / secondary / ghost / destructive 4 variant) |
| `Card` | `card.tsx` | 卡片容器 (**默认无边框无阴影**, 只用 gap 分组) |
| `Input` | `input.tsx` | 输入框 |
| `Label` | `label.tsx` | 表单标签 |
| `Textarea` | `textarea.tsx` | 多行输入 |
| `Select` | `select.tsx` | 下拉选择 |
| `Checkbox` | `checkbox.tsx` | 复选框 |
| `Fab` | `fab.tsx` | 悬浮操作按钮 (B 档 56pt, 非 80pt BigFab) |
| `Badge` | `badge.tsx` | 徽章 |
| `ThemeSwitcher` | `theme-switcher.tsx` | 换肤下拉 (admin topbar) |

### Flutter 侧对应组件 (`flutter_app/lib/core/widgets/app_*.dart`)

见 [docs/ui-principles.md §2.5](../../ui-principles.md) — 7 个 `App*` 组件
(`AppListRow` / `AppSection` / `AppStatRow` / `AppSectionHeader` / `AppSheetHeader` /
`AppBadge` / `AppEmptyState` / `AppSkeleton*`), 与 web 侧一一对应。

任一端遗漏 = UI 漂移; 改两边都用相同令牌 (`design-tokens.json` 真源)。

## `tailwind.config.ts` (Tailwind 配置)

养生行业风格: 暖色 (养生绿 #4A7C59 + 暖橙 accent), 紧凑专业 (B 档)。
令牌由 `design-tokens.json` 生成 (CSS 变量), 不允许字面色值 (护栏: `tools/check-ui-tokens.sh`)。

## 密度旋钮

```css
:root { --density: 1; }
--space-16: calc(1rem * var(--density));
```

```ts
document.documentElement.style.setProperty("--density", "0.9"); // 整体收紧 10%
```

## 护栏

| 工具 | 用途 |
|---|---|
| `tools/check-ui-tokens.sh` | 硬编码棘轮 (色值 / 间距 / 圆角 / 字号); `tools/check-ui-density.sh` 互补 |
| `tools/check-ui-density.sh` | 密度棘轮 (framed / visibleRows); 列表路由「一屏可见行数 ≥ 10」护栏 |
| `tools/check-ui-style.sh` | 旧风格检查 (banned tokens 等) |
| `node tools/verify-ui-tokens.mjs` | 真浏览器视觉验收 (换肤端到端, 20 项断言) |
| `tests/ui-kit-contract.test.ts` | B0b 组件契约 (文件存在 + 导出 + SaaS 三件套扫描 + density-baseline 结构) |
| `tests/design-tokens.test.ts` | 设计令牌契约 (56 例) |

## 反 vibe (B3 / B4 沉淀)

- ❌ 「rounded-lg border shadow-sm」三件套同时出现 (`tests/ui-kit-contract.test.ts` 直接拦)
- ❌ 列表页用 Card 容器 (B3 已迁 divide-y, 见 `/admin/customers`)
- ❌ 「rounded-lg border」shadcn 默认 Card 的滥用 (Card 默认变体已改为无边框无阴影, 见 `card.tsx`)

## 相关 SOP

- [AGENTS.md §1 vibe + 反 vibe](../../AGENTS.md)
- [docs/ui-principles.md](../../ui-principles.md) — 5 条原则 + B 档规格 + review 清单
- [docs/ui-tokens.md](../../ui-tokens.md) — 令牌机制 + 主题换肤
- [docs/CHARTER.md §1.3](../../CHARTER.md) — 反 vibe (暗色主题禁用)

## 待办

- [ ] 把 B0b 组件在 `/admin/dev/ui-kit` 页面加 demo (B0b 已落地但还没全展示)
- [ ] Storybook 集成 (可选, 当前 shadcn 组件 demo 在 app-preview 里)