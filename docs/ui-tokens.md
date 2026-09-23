# UI 设计令牌系统 (Design Tokens)

> **状态**: v1.0 — 2026-09-23 落地 (主人拍板: 跨端单一真相源 / 不开 dark mode / 运行时多主题 / 全量变量化)
> **真源**: [`design/tokens/design-tokens.json`](../design/tokens/design-tokens.json)
> **护栏**: [`tools/check-ui-tokens.sh`](../tools/check-ui-tokens.sh) + [`design/tokens/ui-token-baseline.json`](../design/tokens/ui-token-baseline.json)

---

## 1. 一句话

**改 UI = 改一个 JSON + 跑一条命令。** 两端 (Flutter APK + Web admin) 的颜色/间距/字号/圆角/阴影/动效全部由一个文件派生，
业务代码里**不允许再出现字面值**（护栏会拦）。

```bash
pnpm tokens:build        # 生成: JSON → Flutter token + Web CSS 变量 + Web TS
pnpm tokens:check        # 校验产物与真源一致 (CI / pre-commit)
pnpm tokens:contrast     # 打印 5 个主题的 WCAG 对比度体检表
tools/check-ui-tokens.sh # 硬编码棘轮护栏 (只许下降, 禁止上涨)
node tools/verify-ui-tokens.mjs  # 真浏览器视觉验收 (换肤端到端, 20 项断言)
```

---

## 2. 三层结构

```
L0 调色板 palette        原始色值, 唯一允许出现字面 hex 的地方 (87 槽)
        ↓
L1 尺度 scales           与颜色无关的「数」: 间距/圆角/字号/字重/尺寸/层次/时长/透明度
   semantic.*            尺度上的语义别名 (cardPadding / sectionGap / radius.card …)
        ↓
L2 语义令牌              一主题一份 (L2a 跨主题恒定的 const + L2b 随主题变的运行时值)
        ↓
业务代码                 Flutter: context.tokens.X / AppSpace.s16 / AppType.md
                          Web:     bg-brand / text-content-secondary / p-card-x
```

### 2.1 为什么要分「跨主题恒定」和「随主题变」

`design-tokens.json` 有一条硬规则：

> **themes 只覆盖品牌槽位；中性色 / 文字色 / 状态色在 `shared` 里共用。**

推论：
- 换肤**永远不会**把文字对比度换差（中性色不动）；
- 那些共用槽的色值**跨主题完全一致** → 可以做成**编译期常量** → 生成器自动产出
  `AppColors.textSecondary` 这种 const，存量代码里 `const TextStyle(color: Color(0xFF4A4A4A))`
  能零成本、零 const 冲突地换成令牌。

生成器**自动**判定哪些槽恒定（对比 5 个主题的取值）；把某个槽从 `shared` 挪进 `themes`，它就自动降级成运行时令牌。见 `tokens.g.dart` 的 `AppColors` vs `kThemeVariantTokenKeys`。

---

## 3. 两端怎么取令牌

### 3.1 Flutter (APK 域)

| 需求 | 写法 | 为什么 |
|---|---|---|
| 随主题变的色（品牌色） | `context.tokens.primary` | 只有 `Theme.of(context)` 里的是活值 |
| 跨主题恒定的色 | `AppColors.textSecondary` | const，能在 `const TextStyle(...)` 里用 |
| 间距 | `AppSpace.s16` / `AppSpace.cardPadding` | 尺度不随主题变 |
| 字号 | `AppType.md` | 同上 |
| 圆角 | `AppRadius.card` / `AppRadius.r12` | 同上 |
| 组件尺寸 | `AppSize.buttonLgHeight` | 同上 |
| 层次 / 时长 / 透明度 | `AppElevation.e1` / `AppDuration.base` / `AppOpacity.disabled` | 同上 |

```dart
// ✅ 正确
final t = context.tokens;
Container(
  padding: const EdgeInsets.all(AppSpace.cardPadding),   // 尺度: const 常量
  decoration: BoxDecoration(
    color: t.primarySurface,                             // 品牌色: 跟随换肤
    border: Border.all(color: AppColors.border),          // 中性色: 恒定
    borderRadius: BorderRadius.circular(AppRadius.card),
  ),
)

// ❌ 错误 (会被 tools/check-ui-tokens.sh 拦)
Container(padding: const EdgeInsets.all(16), color: const Color(0xFFFFFBF5));
```

> ⚠ **换肤唯一入口是 `context.tokens`**。`AppThemes.sage.primary` 是编译期常量，写死了默认主题 ——
> 只在两处合法：装配 `ThemeData`、设置页列选项。

⚠ **主题里每个组件 TextStyle 必须显式写 `color`**（2026-09-22 主人报的「chip 白字」根因）：
Flutter 取组件样式是 `theme.xxx ?? defaults.xxx`，我们的非空样式只要漏 color 就把默认色整个顶掉。
`test/theme_tokens_test.dart` 会遍历整个 `ThemeData` 拦这个（已抓到 4 处真 bug）。

### 3.2 Web (WEB 域)

```tsx
// ✅ 语义类 (新代码优先)
<div className="bg-brand text-content-secondary border-divider rounded-card shadow-md p-card-x text-body" />

// ✅ shadcn 兼容层 (存量 600+ 处, 继续可用)
<Button className="bg-primary text-primary-foreground" />

// ✅ 需要真色值的 JS 场景 (recharts / canvas / meta themeColor)
const c = useChartColors();           // 运行时读 CSS 变量, 换肤自动跟随
<Bar fill={c.series1} />
import { palette, themeColors } from "@/lib/design-tokens.g";

// ❌ 会被拦
<div className="bg-amber-700 text-[10px] min-h-[44px]" />
```

**密度旋钮**：`--density` 一个数控制全站语义间距。

```css
:root { --density: 1; }
--space-16: calc(1rem * var(--density));
```

```ts
document.documentElement.style.setProperty("--density", "0.9"); // 整体收紧 10%
```

⚠ **透明度修饰符**：Tailwind 的 `bg-primary/30` 需要一个**可解析的颜色**。
所以生成器对每个语义色同时输出两种形式：

```css
--primary: #4A7C59;              /* 直接当 CSS 值用 */
--primary-rgb: 74 124 89;        /* 给 Tailwind <alpha-value> 用 */
```

tailwind.config 里一律写 `rgb(var(--primary-rgb) / <alpha-value>)`。
（对 `var(--primary)` 用 `/30` 会让 Tailwind **静默不生成类** —— 2026-09-23 迁移时踩到。）

---

## 4. 主题与运行时换肤

### 4.1 主题清单

| id | 名称 | 分组 |
|---|---|---|
| `sage` | 养生绿 | 品牌（默认） |
| `spring` | 春 · 新芽 | 季节 |
| `summer` | 夏 · 青荷 | 季节 |
| `autumn` | 秋 · 琥珀 | 季节 |
| `winter` | 冬 · 苏木 | 季节 |

**不开 dark mode**（AGENTS §1：养生行业偏温暖，不要冷色调）。`globals.css` 里显式 `color-scheme: light`。

### 4.2 加一个主题

1. `design-tokens.json` → `themes` 数组加一项（只需 7 个品牌槽：primary/primaryLight/primaryDark/primarySurface/accent/accentLight/accentSurface）
2. `pnpm tokens:build`
3. **完** —— 两端零改动：Flutter 设置页、Web 下拉、图表色板、QR meta 全部自动出现
4. `pnpm tokens:contrast` 看对比度是否达标（生成器会在构建时报 warning）

`on*` 前景色（onPrimary / onAccent / onSuccess …）**不许手写** —— 写进 JSON 生成器会直接报错。
生成器按 WCAG 相对亮度在白/深之间自动选，从机制上消灭「白字白底」。

### 4.3 运行时机制

| | Flutter | Web |
|---|---|---|
| 取值 | `ThemeData.extensions` 里的 `AppTokensTheme` | `<html data-theme>` + CSS 变量覆盖块 |
| 读 | `context.tokens` | `var(--brand)`（Tailwind 类名走它） |
| 持久化 | `shared_preferences: settings.theme_id` | `localStorage: nuankebao.theme` |
| 防闪 | `main()` 里 await prefs 后再 runApp | `<head>` 内联 boot script（绘制前打属性） |
| 入口 | 「我的」→ 主题配色 | admin topbar 下拉 |
| 订阅 | Riverpod `activeTokensProvider` | `subscribeTheme()`（含跨标签页同步） |

未知/旧版本的 theme id 一律**安全回落默认主题**（两端都测了）。

---

## 5. 改什么去哪个文件

| 想改 | 改哪里 | 影响范围 |
|---|---|---|
| 品牌主色 / 加主题 | `design-tokens.json` → `themes` | 两端全部品牌色 |
| 卡片圆角 | `design-tokens.json` → `semantic.radius.card` | 两端所有卡片 |
| 全站间距密度（Flutter） | `design-tokens.json` → `scales.space` | 所有 `AppSpace.*` |
| 全站间距密度（Web） | 运行时 `--density` | 所有语义 spacing 类 |
| 正文可读性底线 | `design-tokens.json` → `scales.type` | 所有 `AppType.*` / `text-body` |
| 对比度门槛 | `design-tokens.json` → `contrast` | 生成器的自动推导 + 测试门 |

---

## 6. 护栏

```
tools/check-ui-tokens.sh              报告 (永远 exit 0)
tools/check-ui-tokens.sh --strict     超基线 → exit 1 (CI / pre-commit)
tools/check-ui-tokens.sh --update-baseline   往下拧一格 (上涨会被拒绝写入)
tools/check-ui-tokens.sh --by-file    列每个文件的明细
```

**棘轮 (ratchet) 语义**：存量登记在 `ui-token-baseline.json`，**只禁止上涨**，不要求立刻清零。
每修一批就 `--update-baseline` 往下拧。当前基线 = **0**。

指标：

| 指标 | 含义 |
|---|---|
| `flutter.color` | `core/theme/` 之外的字面 `Color(0x…)` |
| `flutter.fontSize` / `radius` / `spacing` | 裸数字字号 / 圆角 / 间距 |
| `web.paletteClass` | 绕过语义令牌的 Tailwind 调色板类 (`bg-amber-700`) |
| `web.arbitraryValue` | `[16px]` / `[#fff]` 这类任意值 |
| `web.hexLiteral` | tsx/ts 里的字面 hex |
| `flutter.constThemeRef` | 绕过 `context.tokens` 直接读 `AppThemes.x.y` |

### 例外白名单（不算违规）

- `flutter_app/lib/core/theme/**` —— 令牌系统自身
- `src/lib/design-tokens.g.ts` / `globals.css` 生成块 —— 生成的镜像
- `src/components/preview/**` + `src/app/app-preview/**` —— **AGENTS §9.1 冻结的预览框架**，不可改
- `src/app/admin/dev/architecture/**` + `mermaid-renderer.tsx` —— mermaid `classDef` 是**图的 DSL 字符串**，不是 CSS
- `vh` / `vw` / `%` —— 视口相对单位，没有"绝对值令牌"可替
- 代码注释里提到的 hex

---

## 7. 相关文件

| 文件 | 角色 |
|---|---|
| `design/tokens/design-tokens.json` | **唯一真源** |
| `design/tokens/ui-token-baseline.json` | 硬编码棘轮基线 |
| `scripts/generate-tokens.ts` | 生成器 |
| `flutter_app/lib/core/theme/tokens.g.dart` | 生成物（勿手改） |
| `flutter_app/lib/core/theme/app_theme.dart` | 令牌 → `ThemeData` 装配（不含字面值） |
| `flutter_app/lib/core/theme/theme_ext.dart` | `context.tokens` |
| `flutter_app/lib/core/providers/theme_provider.dart` | 主题状态 + 持久化 |
| `flutter_app/lib/screens/theme_picker_card.dart` | 换肤 UI |
| `src/lib/design-tokens.g.ts` | 生成物：JS 侧色值（勿手改） |
| `src/lib/theme.ts` | Web 换肤运行时 + 防闪脚本 |
| `src/lib/use-theme-colors.ts` | 给 recharts/canvas 的运行时取色 hook |
| `src/components/ui/theme-switcher.tsx` | 换肤 UI |
| `src/styles/globals.css` | 生成块注入 + base layer |
| `tailwind.config.ts` | CSS 变量 → 类名映射（零字面色值） |
| `flutter_app/web/{index.html,manifest.json}` | PWA 启动壳的 `theme-color`（生成器**外科式**改色，保住 name/description/icons 等人工字段） |
| `tests/design-tokens.test.ts` | 契约测试 56 例 |
| `flutter_app/test/theme_tokens_test.dart` | 契约测试 41 例 |

---

## 8. 已知取舍 / 后续

- **`_deprecated/` 已真删**（2026-09-23 主人拍板）：20 个文件本来就是坏的（43 处 `uri_does_not_exist`，
  临时解禁分析出 200 条 issue，0 条与令牌有关），观察期早已过。删除前先做了完整令牌化，
  万一要回滚: `git log --diff-filter=D --oneline -- flutter_app/lib/_deprecated` 找到删除 commit,
  再 `git checkout <该commit>^ -- flutter_app/lib/_deprecated/`。
- **Web 字号 `--text-micro` (10px)** ×42 处来自 web admin 密集表格。Flutter 可读性底线仍是 14px；
  web admin 是主人自用脚手架，暂许更小。要统一抬高 → 改 `scales.type.micro` 一个数。
- **PWA 启动壳的颜色是静态的**（`index.html` / `manifest.json`）：浏览器在 Dart 引擎启动前就读它们，
  那时没有 CSS 变量也没有 localStorage → 只能给品牌默认色。生成器会同步它们，
  `tokens:check` 漂移即 fail（下次改 `scales`/主色时自动跟随）。
- **`sage` 的 `primary` 对白字 4.86:1**（AA，未达 AAA 7:1）。基础字号 18pt 属 WCAG 大字号，AA-large 达标；
  需要 AAA 的场景用 `primaryDark`（7.95:1）。`pnpm tokens:contrast` 会列出全部。
- 未做 dark mode（主人 2026-09-23 拍板）。
