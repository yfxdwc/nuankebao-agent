# ui-kit — UI 方案模块 (WEB 域)

> **职责**: WEB 域的 UI 设计系统 (shadcn/ui + Tailwind + 主题)
> **物理位置**: `src/components/ui/` + `tailwind.config.ts` + `src/styles/`
> **入口**: `src/components/ui/button.tsx` 等 11 个 shadcn 组件

## 当前实现

### `src/components/ui/` (11 个 shadcn 基础组件)

shadcn/ui 是 Radix UI Primitives + Tailwind CSS 组合, **组件代码**复制到项目里 (不引 npm 包), 主人可自由修改.

| 组件 | 文件 | 用途 |
|---|---|---|
| Button | `button.tsx` | 按钮 (primary / secondary / ghost / destructive 4 variant) |
| Input | `input.tsx` | 输入框 |
| Label | `label.tsx` | 表单标签 |
| Textarea | `textarea.tsx` | 多行输入 |
| Select | `select.tsx` | 下拉选择 |
| Checkbox | `checkbox.tsx` | 复选框 |
| Dialog | `dialog.tsx` | 模态对话框 |
| DropdownMenu | `dropdown-menu.tsx` | 下拉菜单 |
| Tabs | `tabs.tsx` | 标签页 |
| Toast | `toast.tsx` + `toaster.tsx` + `use-toast.ts` | 吐司提示 |
| Card | `card.tsx` | 卡片容器 |
| Table | `table.tsx` | 表格 |

### `tailwind.config.ts` (Tailwind 配置)

养生行业风格:
- 主色: `#2D5F3F` (养生绿, 从 `AppTheme.primary` Flutter 端同步)
- 字体: 系统默认 (避免大字体下载)
- 暗色模式: ❌ 禁用 (per AGENTS §1 反 vibe)
- 移动优先: 默认 breakpoints (sm / md / lg / xl)

### `src/styles/` (全局样式)

- `globals.css` — Tailwind 基础 + CSS variables (shadcn theme tokens)

## 扩展指南

**新增组件** (e.g. DatePicker):
```bash
# 1. 用 shadcn CLI (官方)
npx shadcn-ui@latest add date-picker

# 2. 或手动: 复制 Radix UI 代码 → src/components/ui/date-picker.tsx
# 3. 检查依赖加进 package.json
```

**改主题色** (e.g. 客户是康复行业, 想要蓝绿):
1. 改 `tailwind.config.ts` 的 `colors.primary`
2. 同步改 `flutter_app/lib/core/theme/app_theme.dart` 的 `AppTheme.primary`
3. ⚠ 强绑定 (AGENTS §6.3): 改一个必须同步改另一个

**加暗色模式** (⚠ 主人 override):
- AGENTS §1 反 vibe: "❌ 不要暗色主题 (养生行业偏温暖)"
- 主人拍板后可加 `darkMode: 'class'` + shadcn dark variant

## 与 Flutter theme 同步

| 维度 | WEB (Tailwind) | Flutter (AppTheme) |
|---|---|---|
| 主色 | `colors.primary` | `AppTheme.primary` |
| 背景色 | `colors.background` | `AppTheme.bgWarm` |
| 字体大小 | Tailwind scale | `AppTheme.fontSm/Md/Lg/Xl` |
| 圆角 | `rounded-lg` 等 | `BorderRadius.circular(8)` |
| 间距 | Tailwind scale | `EdgeInsets.all(16)` 等 |

**改动任一项必须同步改另一项** (避免视觉不一致).

## 相关 SOP

- [AGENTS.md §1 vibe + 反 vibe](../../AGENTS.md)
- [CHARTER.md §1.3 反 vibe (暗色主题禁用)](../../CHARTER.md)
- shadcn/ui 文档: <https://ui.shadcn.com/>
- Tailwind CSS 文档: <https://tailwindcss.com/docs>

## 待办

- [ ] 主题色 / 字体 / 圆角集中化 (现在散落在 tailwind.config.ts 和 AppTheme)
- [ ] 设计 token 文档 (主人 review 用)
- [ ] Storybook 集成 (可选, 当前 shadcn 组件 demo 在 app-preview 里)
