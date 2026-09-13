# UI 风格指南 (暖客宝 NuankeBao)

> **借鉴源**: 本指南借鉴自 [sales-ai `docs/UI_STYLE_GUIDE.md`](https://github.com/sales-ai/sales-ai/blob/main/docs/UI_STYLE_GUIDE.md) (1673 行) — **结构 + 设计原则**借鉴, **品牌 + 视觉** nuankebao 自有 (养生绿 + 移动优先 + 中年女性友好).
>
> **状态**: v1.0 (2026-09-13) — 主人 v0.1.4 拍板 key_modules_ui 后, 借鉴 sales-ai 落地.
>
> **关联**: [AGENTS.md §1 vibe](../../AGENTS.md) (中医/养生气质, 移动优先, 反 SaaS) + [AGENTS §4.5 模块化约束](../../AGENTS.md) + [dev-modules/ui-kit.md](dev-modules/ui-kit.md) (7 模块之一).

---

## 1. 设计原则 (5 条)

> **借鉴自 sales-ai §1, 但 nuankebao 5 条更精简** (因为我们没他们那么多业务复杂度).

### 1.1 Token 驱动, 不写死颜色

所有颜色必须走 CSS 变量 (Tailwind utility class), **禁止**写 `text-gray-500` `bg-[#xxx]` 等硬编码.

**唯一例外**: 调试 border 临时 `border-pink-400` 在 PR 标记.

### 1.2 ❌ 暗色模式禁用 (v0.1 反 vibe)

**主人 2026-09-04 拍板** (per AGENTS §1): "❌ 不要暗色主题 (养生行业偏温暖)".

- 即使 shadcn/ui 默认支持 `dark:` variant, **nuankebao 项目不写 `.dark:*` 类**
- `tailwind.config.ts` 的 `darkMode: ["class"]` **保留** (shadcn 兼容), 但 **nuankebao UI 不主动用**
- 颜色变量只走 `:root` 一套, 不维护 `.dark` 第二套

### 1.3 移动优先 + 字号偏大 (中年女性友好)

**主人 v0.1 拍板**: 销售员中年女性为主, 移动端重度使用.

- 默认 breakpoints: `sm` `md` `lg` `xl` (Tailwind 标准)
- 默认最小字号: `text-sm` (14px) 但**推荐** `text-base` (16px) 或 `text-lg` (18px)
- 按钮最小高度: `h-11` (44px) 移动端友好, **不要** `h-8` `h-9` (太小)
- 列表行: `py-4` (16px 上下), **不要** `py-2` (太挤)

### 1.4 shadcn/ui 风格手写组件

- 组件位于 [`src/components/ui/`](../../src/components/ui/) (per dev-modules/ui-kit.md)
- 借鉴 shadcn/ui 但**不**依赖 `@shadcn/ui` 包 (复制代码改完再 reuse)
- 业务组件目录 (如 `business/`) **禁止**复制这些基础组件

### 1.5 icon 库 = `lucide-react` (单一)

- 只用 [`lucide-react`](https://lucide.dev/) (per ui-kit.md)
- **禁止** `react-icons` `@heroicons` `@tabler/icons-react` `@iconify/*` `phosphor-react`
- ❌ 不 namespace 全量 `import * as Icons from "lucide-react"`
- ✅ 具名 import: `import { Plus, Search, Trash2 } from "lucide-react"`

---

## 2. 颜色 token 表

> **借鉴 sales-ai §2 语义色结构**, 但颜色值是 nuankebao 养生绿品牌 (`#2D5F3F`).

### 2.1 语义色 (推荐用)

> 颜色定义在 [`src/styles/globals.css`](../../src/styles/globals.css) `:root`, 由 [`tailwind.config.ts`](../../tailwind.config.ts) 桥接.

| Token | Tailwind class | 养生绿品牌值 | 用途 |
|---|---|---|---|
| `--primary` | `bg-primary` `text-primary` | 养生绿 #2D5F3F | 主按钮, 主链接, 选中导航, 品牌强调 |
| `--primary-foreground` | `text-primary-foreground` | 浅色 #FAFAFA | `bg-primary` 容器内的文字 |
| `--background` | `bg-background` | 浅色 #FFFFFF | 页面整体底色 |
| `--card` | `bg-card` | 浅色 #FFFFFF | 卡片, 对话框, 侧栏 |
| `--muted` | `bg-muted` | 浅米色 | 次要容器, 搜索框 hover |
| `--muted-foreground` | `text-muted-foreground` | 深灰 | **次要文字 (说明, footer, 辅助信息)** |
| `--foreground` | `text-foreground` | 近黑 | 主文字 (标题, 单元格主内容) |
| `--destructive` | `bg-destructive` `text-destructive` | 红 | 删除按钮, 错误提示, ⚠ 危险操作 |
| `--destructive-foreground` | `text-destructive-foreground` | 浅 | 危险按钮文字 |
| `--border` | `border-border` | 浅灰 | 表单边框, 卡片边线, 分隔线 |
| `--input` | `border-input` | 浅灰 | 输入框边框 |
| `--ring` | `ring-ring` | 养生绿 | focus-visible 焦点环 |
| `--secondary` `bg-secondary` | 浅黄 | 次按钮 |
| `--accent` `bg-accent` | 极浅米 | hover 态底色 |
| `--radius` | `borderRadius` | 0.5rem | 默认圆角 |

**品牌色 (`#2D5F3F` 养生绿)** 同步自 [Flutter `core/theme/app_theme.dart`](../../flutter_app/lib/core/theme/app_theme.dart) 的 `AppTheme.primary`. **改一个必须同步改另一个** (AGENTS §6.3 强绑定).

### 2.2 透明度变体 (推荐)

用于叠加弱化背景:

| class | 用途 |
|---|---|
| `bg-muted/30` | 表格斑马行, 提示条弱底色 |
| `bg-muted/40` | 略深的中性覆盖 |
| `bg-muted/50` | hover / 卡片高亮态 |
| `bg-primary/5` `bg-primary/10` | 主色极淡覆盖 (选中 hint) |
| `hover:bg-primary/90` | Button hover (已封装) |
| `hover:bg-destructive/90` | 危险按钮 hover (已封装) |

### 2.3 ❌ 禁止项

- ❌ `bg-gray-*` `bg-slate-*` `bg-zinc-*` 等 Tailwind 默认色板 (绕过 token)
- ❌ `text-[#xxx]` `bg-[#xxx]` 硬编码颜色 (除 `border-pink-400` 调试)
- ❌ `.dark:bg-*` 双写 (项目禁用暗色模式)
- ❌ 改 `:root` 变量来适配单个组件 (token 系统崩溃的开始)
- ❌ 硬编码 `#xxxxxx` hex 值 (包括图表色板)
- ❌ `hsl(...)` 残留 (sales-ai 已全切 oklch, 我们暂时保留 HSL 是 shadcn 默认)

### 2.4 ✅ 多主题设计 (品牌锁定)

**主人 2026-09-04 拍板** (per AGENTS §1): 养生绿品牌锁定, **不**做多主题切换 (不像 sales-ai 5 套皮肤).

- 唯一主题: 养生绿
- 未来如需季节性换色 (e.g. 冬季暖橙), 在 `globals.css` 加 `.winter` 类, **主人拍板后**才实施
- ❌ 不写 `<html data-theme="...">` 切换逻辑

---

## 3. 核心组件使用约定 (借鉴 sales-ai §3 精简)

> 仅列最常用 6 个, 详细 API 见 [`src/components/ui/*` 源码](../../src/components/ui/).

### 3.1 Card (区块容器) - 最常用

```tsx
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from "@/components/ui/card";

// ✅ 三段式 (CardHeader + CardContent + CardFooter)
<Card>
  <CardHeader>
    <CardTitle>标题</CardTitle>
  </CardHeader>
  <CardContent>{/* 主内容 */}</CardContent>
  <CardFooter>{/* 操作按钮 */}</CardFooter>
</Card>

// ✅ CardHeader 复杂版 (标题 + 描述 + 操作按钮)
<Card>
  <CardHeader>
    <div className="flex items-center justify-between">
      <div>
        <CardTitle>客户总数</CardTitle>
        <p className="text-xs text-muted-foreground mt-1">本月底</p>
      </div>
      <Button size="sm" variant="ghost">详情</Button>
    </div>
  </CardHeader>
  <CardContent>
    <p className="text-3xl font-bold text-primary">120</p>
  </CardContent>
</Card>
```

### 3.2 Button (操作按钮)

```tsx
import { Button } from "@/components/ui/button";

// 4 variant (per shadcn)
<Button variant="default">主操作</Button>
<Button variant="secondary">次操作</Button>
<Button variant="outline">描边按钮</Button>
<Button variant="ghost">透明按钮</Button>
<Button variant="destructive">危险操作 (e.g. 删除)</Button>

// 4 size
<Button size="sm">小 (h-9)</Button>
<Button size="default">默认 (h-10)</Button>
<Button size="lg">大 (h-11, 移动端友好)</Button>
<Button size="icon">图标按钮 (方形)</Button>

// icon + 文字 (常见组合)
<Button>
  <Plus className="h-4 w-4 mr-2" />
  新增客户
</Button>

// ❌ 禁止
<Button className="bg-blue-500">  ← 硬编码颜色
<Button className="h-8">      ← 太小 (移动端)
<Button style={{ padding: 20 }}> ← inline style 禁止
```

### 3.3 Tabs (PageTabs / SubnavTabs)

```tsx
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";

// ✅ 推荐: 用 url hash 同步 (受控)
<Tabs defaultValue="customers" onValueChange={...}>
  <TabsList>
    <TabsTrigger value="customers">客户 (12)</TabsTrigger>
    <TabsTrigger value="wellness">养生 (45)</TabsTrigger>
  </TabsList>
  <TabsContent value="customers">{/* 客户列表 */}</TabsContent>
  <TabsContent value="wellness">{/* 养生列表 */}</TabsContent>
</Tabs>
```

### 3.4 Table (列表表格)

```tsx
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/ui/table";

<Table>
  <TableHeader>
    <TableRow>
      <TableHead>姓名</TableHead>
      <TableHead>手机号</TableHead>
      <TableHead className="text-right">操作</TableHead>
    </TableRow>
  </TableHeader>
  <TableBody>
    <TableRow>
      <TableCell>张三</TableCell>
      <TableCell>13800138000</TableCell>
      <TableCell className="text-right">
        <Button size="sm" variant="ghost">详情</Button>
      </TableCell>
    </TableRow>
  </TableBody>
</Table>
```

### 3.5 Badge (状态标签)

```tsx
import { Badge } from "@/components/ui/badge";

<Badge>默认</Badge>
<Badge variant="secondary">次要</Badge>
<Badge variant="outline">描边</Badge>
<Badge variant="destructive">危险</Badge>

// 常用组合 (语义 + 颜色)
<Badge variant="outline" className="text-xs text-primary border-primary">养生绿</Badge>
<Badge variant="destructive" className="text-xs">失败</Badge>
```

### 3.6 Input / Textarea / Select

```tsx
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select";

// ✅ 标准用法 (中等大小, 移动友好)
<Input placeholder="搜索..." className="h-11" />
<Textarea placeholder="备注..." rows={4} />
<Select>
  <SelectTrigger className="h-11">
    <SelectValue placeholder="选择..." />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="a">选项 A</SelectItem>
  </SelectContent>
</Select>
```

---

## 4. 图标系统 (Iconography)

> **借鉴 sales-ai §1.1**, 但尺寸矩阵更精简 (5 级 → 4 级).

### 4.1 尺寸矩阵 (4 级)

| 场景 | icon class | 说明 |
|---|---|---|
| 行内状态 / 加载 | `h-3 w-3 shrink-0` | 仅用于 `text-xs` 附近 |
| **按钮 / 菜单 / Tab / 表格行 / 输入框 (默认事实标准)** | `h-4 w-4 shrink-0` | **必背** |
| 独立状态 / 紧凑卡片 | `h-5 w-5 shrink-0` | 不用于普通按钮 |
| 表单 H1 / EmptyState 主图标 | `h-8 w-8 shrink-0` | 由 `EmptyState` 统一渲染 |

**保持 Lucide 默认 `strokeWidth`**. 矩阵外尺寸必须在代码注释中说明原因.

### 4.2 高频语义映射 (借鉴 sales-ai §1.1.4)

| 语义 | Lucide icon | 语义 | Lucide icon |
|---|---|---|---|
| 新建 | `Plus` | 编辑 | `Pencil` |
| 删除 | `Trash2` | 查看 | `Eye` |
| 搜索 | `Search` | 刷新 | `RefreshCw` |
| 返回 | `ArrowLeft` | 关闭 | `X` |
| 成功 | `CircleCheck` | 警告 | `TriangleAlert` |
| 错误 | `CircleX` | 加载 | `Loader2` + `animate-spin` |
| **客户** | `Users` | 养生记录 | `Heart` |
| **跟进任务** | `Bell` | **联系记录** | `MessageCircle` |
| **报表** | `BarChart3` | **导入** | `Upload` |
| **AI** | `Brain` | **App 下载** | `Download` |
| **网络/部署** | `Network` | **数据库/备份** | `Database` |
| **历史/快照** | `History` | **架构图** | `Network` (复用) |
| **开发工具** | `Terminal` | **文档** | `BookOpen` |
| **设置** | `Settings` | **注意/通知** | `Bell` (复用) |

> **业务语义优先**: nuankebao 是养生 CRM, 客户/养生/跟进/联系是高频概念, 必须用稳定 icon. 同一概念不换 glyph.

### 4.3 颜色与状态

- Lucide 默认 `currentColor`, 用 `text-primary` `text-muted-foreground` `text-destructive`
- ❌ 硬编码 `stroke` `fill` Hex
- 导航选中/未选中用**同一图标**, 只改容器/文字/边框 Token
- 禁用态由父控件的 `disabled:opacity-*` 管理

### 4.4 无障碍

```tsx
{/* 有可见文字: 图标装饰性 */}
<Button>
  <Plus aria-hidden="true" className="h-4 w-4 mr-2 shrink-0" />
  新建客户
</Button>

{/* 纯图标: 控件必须有可访问名称 */}
<Button variant="ghost" size="icon" aria-label="刷新">
  <RefreshCw aria-hidden="true" className="h-4 w-4 shrink-0" />
</Button>
```

---

## 5. 与 Flutter 同步规则 (强绑定)

> **AGENTS §6.3 改名红线**: 主品牌色 / 字号 / 圆角 / 间距跨端必须同步.

### 5.1 颜色 (养生绿 primary)

| 维度 | WEB (Tailwind) | Flutter (AppTheme) |
|---|---|---|
| Primary | `bg-primary` | `AppTheme.primary` |
| 背景 | `bg-background` | `AppTheme.bgWarm` |
| 字号 | Tailwind scale | `AppTheme.fontSm/Md/Lg/Xl` |
| 圆角 | `rounded-lg` 等 | `BorderRadius.circular(8)` 等 |
| 间距 | Tailwind scale | `EdgeInsets.all(16)` 等 |

**改一项必须同步另一项**. 否则视觉不一致.

### 5.2 不同步项 (各端特有)

- WEB 特有: 鼠标 hover 态, focus ring, 键盘快捷键
- Flutter 特有: Bottom Navigation 5 tab (per Plan F2), Material Design ripple, native camera

---

## 6. 机械化守门 (借鉴 sales-ai §1.1.7)

### 6.1 工具: `tools/check-ui-style.sh`

```bash
bash tools/check-ui-style.sh
```

检查项:
- ❌ 禁用图标包 (`react-icons` `@heroicons/*` `@tabler/*` `@iconify/*`)
- ❌ namespace 全量 import (`import * as Icons from "lucide-react"`)
- ❌ 硬编码颜色 (`text-gray-*` `bg-slate-*` `bg-[#xxx]`)
- ❌ 暗色模式 (`.dark:*` 在 nuankebao UI 中)
- ❌ inline style (`style={{ ... }}`)
- ❌ icon-only 控件缺少 `aria-label`
- ⚠️ icon 尺寸非标准 (矩阵外)

### 6.2 CI 集成 (per AGENTS §3)

主人 review 后, 加进 GitHub Actions `.github/workflows/ci.yml`:

```yaml
- name: UI Style Check
  run: bash tools/check-ui-style.sh
```

### 6.3 Owner

- 主人 review: UI 大改 (e.g. 换品牌色, 加新图标语义)
- Agent 自治: 单文件 token 替换 (机械操作)

---

## 7. 借鉴声明 (per AGENTS §2 原则 8)

**借鉴自 [sales-ai `docs/UI_STYLE_GUIDE.md`](https://github.com/sales-ai/sales-ai/blob/main/docs/UI_STYLE_GUIDE.md)** (1673 行):

| 借鉴维度 | 说明 |
|---|---|
| §1 设计原则 5 条 | 结构借鉴, 内容 nuankebao 自有 |
| §2 颜色 token 表 | 结构借鉴, 颜色值 nuankebao 养生绿 |
| §3 核心组件约定 | **完全借鉴** (shadcn 风格, 跨项目一致) |
| §4 icon 系统 | 尺寸矩阵借鉴, 高频语义 nuankebao 业务化 (养生 / 加盟 / 跟进) |
| §6 机械化守门 | **完全借鉴** (跨项目一致) |

**nuankebao 自有 (不借鉴 sales-ai)**:
- ❌ 暗色模式 (主人反 vibe)
- ❌ 多主题 (养生绿品牌锁定)
- 字号偏大 / 按钮 h-11 (中年女性友好)
- Flutter 同步规则 (AGENTS §6.3 强绑定)

详见 [`docs/references.md`](references.md) 完整借鉴清单.

---

## 8. 元数据

- **版本**: v1.0
- **日期**: 2026-09-13
- **拍板**: 主人 2026-09-13 (key_modules_ui 后, 借鉴 sales-ai)
- **借鉴源**: sales-ai UI_STYLE_GUIDE.md (1673 行)
- **维护**: 主人 review, agent 自治

---

## 9. 关联文档

- [`docs/dev-modules/ui-kit.md`](dev-modules/ui-kit.md) — 7 模块之一
- [`AGENTS.md §1 vibe`](../../AGENTS.md) — 养生气质 / 移动优先 / 反 SaaS
- [`AGENTS.md §4.5 模块化约束`](../../AGENTS.md) — UI 唯一源
- [`tailwind.config.ts`](../../tailwind.config.ts) — Tailwind token 桥接
- [`src/styles/globals.css`](../../src/styles/globals.css) — CSS 变量定义
- [`flutter_app/lib/core/theme/app_theme.dart`](../../flutter_app/lib/core/theme/app_theme.dart) — Flutter 同步源
- [`sales-ai UI_STYLE_GUIDE.md`](https://github.com/sales-ai/sales-ai/blob/main/docs/UI_STYLE_GUIDE.md) — 借鉴源

---

**本文件结束. 下一个应读**:
- 主人: 看 §1 设计原则 + §4 icon 语义映射 (开发时查)
- Agent 开发 UI: 看 §3 组件约定 + §4 icon 尺寸矩阵 (边写边查)
- 维护者: §6 守门 + §7 借鉴声明 (review 时)
