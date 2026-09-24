# UI 设计原则（Design Principles）

> **状态**: v1.0 — 2026-09-23 主人拍板
> **定位**: 本文件是**所有 UI 改动的验收标准**。提案 / 评审 / code review 都拿它逐条对。
> **配套**: 具体数值在 [`design/tokens/design-tokens.json`](../design/tokens/design-tokens.json)；
> 令牌机制见 [`docs/ui-tokens.md`](./ui-tokens.md)。
> **密度档位**: **B 档（紧凑专业）** — 正文 15px / 列表行 60px / 客户列表一屏约 9 条

---

## §0 为什么有这份文档：一次方向纠偏

```
用户画像 (CHARTER §1) : 大健康门店销售 + 客服，中年女性为主，移动端重度使用
曾经的设计            : 「中老年妇女极易用版本」正文 18 / 按钮 64 / FAB 80 / 列表行 80
```

**40-55 岁的职业女性不是"老人"。**

她们每天刷微信 8 小时、发朋友圈、看直播带货。把她们当成需要 80px 按钮的群体，
等于**把熟练用户当成障碍用户** —— 结果是：

- 一屏只能看 5 个客户（她们要管上百个）
- 106 个卡片容器把屏幕切成碎片
- 层级全靠"放大"，视觉噪音大
- 大色块 + 大圆角 + 全局阴影 = 廉价感

**纠偏方向**：一切 UI 服务于**客户管理本身**。目标气质 = **微信 × Linear × Things 3**。

> ⚠ 这次纠偏**不是"往回退一点"**，而是把目标用户改对。以下 5 条原则取代
> "字号尽量大、按钮尽量大" 那套，成为新的验收标准。

---

## §1 五条可验收的原则

### 原则 1 · 密度 = 尊重用户时间

**为什么**：销售员一天要看几十上百个客户。一屏 4 个 vs 一屏 8 个，是**2 倍效率差**。

> 密度不是"挤"，是"每个像素都在传递信息"。

**怎么做**
- 列表行高 60（原 80）、正文 15（原 18）、AppBar 52（原 64）
- 去掉"装饰性占用"：双层标题、重复图标、只起分隔作用的卡片
- 数字/状态用等宽对齐，一眼可扫

**怎么验收**
- ✅ **客户列表一屏可见条数 ≥ 9**（iPhone 14 尺寸，375×812）
- ✅ 首屏无需滚动即可看到：客户名 + 关键状态 + 下一步动作

---

### 原则 2 · 层级靠**对比**，不靠放大

**为什么**：靠放大建立层级 → 字号越滚越大 → 页面被撑爆，层级反而糊。
成熟做法用**三个维度**叠加：字号差 + 字重差 + 颜色差。

**怎么做**

| 层级 | 字号 | 字重 | 颜色 | 示例 |
|---|---|---|---|---|
| 页面标题 | 20 (`xl`) | 600 | 主文字 | 「客户」 |
| 区块标题 | 17 (`lg`) | 600 | 主文字 | 「最近跟进」 |
| 条目主文 | 15 (`md`) | 500 | 主文字 | 客户姓名 |
| 条目副文 | 13 (`sm`) | 400 | 次文字 | 「3 天未联系」 |
| 辅助/角标 | 12 (`xs`) | 400 | 三级文字 | 计数、时间戳 |

**字号差只需 2-3px**；层级感主要由**字重 + 颜色**提供。

**怎么验收**
- ✅ 整屏字号档位 ≤ 5 个
- ✅ 任一文字块，遮住字号只凭字重+颜色仍能判断层级
- ❌ 禁止：用 22px 以上字号表达"重要"（`xxl=28` 只留给主页大数字 / hero）

---

### 原则 3 · 留白是**分组工具**，不是装饰

**为什么**：紧凑 ≠ 拥挤。真正的紧凑靠**成组**：
相关元素贴紧（形成"视觉块"），不相关元素拉开（形成分界）。

旧设计的问题是"所有间距都偏大" → **反而没有分组感**，看起来又空又乱。

**怎么做**

| 关系 | 间距 | 令牌 |
|---|---|---|
| 同一行内元素 | 4-6 | `AppSpace.s4` / `s6` |
| 同组内上下元素 | 8 | `AppSpace.inlineGap` |
| 组内边距 | 14 | `AppSpace.cardPadding` |
| 卡片之间 | 10 | `AppSpace.cardGap` |
| 区块之间 | 20 | `AppSpace.sectionGap` |
| 页面左右边距 | 16 | `AppSpace.pagePadding` |

**留白比 = 组内 : 组间 ≈ 1 : 2** —— 这是"看起来清爽"的数学本质。

**怎么验收**
- ✅ 组内间距 ≤ 组间间距的 1/2
- ✅ 截图缩小到 25%，仍能看出信息分组

---

### 原则 4 · 容器越少，内容越强

**为什么**：这是当前最大的问题 —— **实测 106 处 `Card(`，散在 21 个文件**。

> 旧设计：每个信息块 = 卡片 + 边框 + 阴影 + 大圆角 + 左右 16px margin
> → 满屏方块，屏幕被"墙"切碎，真正的内容只剩一半宽度

**怎么做 —— 容器分级**

| 场景 | 用什么 | 不用什么 |
|---|---|---|
| 同质列表（客户、跟进、记录） | **1px 分隔线** + 留白 | ❌ 卡片 |
| 独立实体（客户卡、沙龙卡） | 卡片，**无边框、无阴影**，仅靠留白区分 | ❌ 边框+阴影叠加 |
| 强调块（紧要提醒、AI 建议） | 浅色底 (`*-surface`) 圆角块 | ❌ 描边 |
| 弹层（Sheet / Dialog） | 卡片 + 阴影（仅此处保留阴影） | |
| 分组标题 | 纯文字 + 小间距 | ❌ 装饰条/色块 |

**怎么验收**
- ✅ 一屏内"有边框或有阴影"的元素 ≤ 2 个
- ✅ 列表类页面不出现卡片容器
- ✅ 卡片左右 margin = 0（用页面 padding 统一），不再"卡片内缩"

---

### 原则 5 · 颜色是**信号**，不是装饰

**为什么**：大面积彩色 = 廉价感。中性色打底 + 克制的高饱和点缀 = 高级感。

**怎么做**
- **一个强调色**（`primary`），只用在**可点的东西**上：主按钮、选中的 tab、链接
- 状态色（success/warning/danger/info）**只在有状态时出现**，不做背景铺色
- 图标默认用**三级文字色**，不要一屏十种颜色
- 浅色底（`*-surface`）只用于"强调块"，一屏 ≤ 2 处

**怎么验收**
- ✅ 截图转灰度后，层级与可点性信息**不丢失**（说明没靠颜色传递关键信息）
- ✅ 一屏内饱和色块（除图片）≤ 3 处
- ❌ 禁止：用颜色表达"分类"（用文字/图标/位置）

---

## §2 具体规格（B 档 · 紧凑专业）

> 全部来自 `design-tokens.json`，改令牌即全站生效。

### 字号 `scales.type`

| 令牌 | 值 | 用途 |
|---|---|---|
| `micro` | 11 | 图谱画布微标签（常规 UI 不用） |
| `xs` | 12 | 角标 / 时间戳 / 辅助 |
| `sm` | 13 | 副信息（"3 天未联系"） |
| `md` | **15** | **正文** |
| `lg` | 17 | 区块标题 |
| `xl` | 20 | 页面标题 |
| `xxl` | 28 | 主页大数字 / hero |

### 尺寸 `scales.size`

| 令牌 | 值 | 原值 | 用途 |
|---|---|---|---|
| `buttonLgHeight` | **48** | 64 | 主按钮 |
| `buttonMinHeight` | **40** | 56 | 次按钮 |
| `fabSize` | **56** | 80 | FAB |
| `listRowHeight` | **60** | 80 | 列表行 |
| `appBarHeight` | **52** | 64 | AppBar |
| `controlSm/Md/Lg` | 32 / 34 / 44 | 36/40/52 | 分段控件、chip、输入 |
| `avatarSm/Md/Lg` | 32 / 44 / 64 | 40/56/96 | 头像 |
| `tapMin` | **48（不变）** | 48 | **热区下限，见 §3** |

### 圆角 `semantic.radius`

| 用途 | 值 | 理由 |
|---|---|---|
| `card` | 10 | |
| `button` / `input` | 8 | |
| `badge` | 4 | 小元素用小圆角 |
| `chip` | **全圆 (pill)** | 避免"半吊子圆角"显廉价 |
| `dialog` | 14 | |
| `sheet` | 16 | |

> **圆角与元素尺寸成正比**；嵌套元素的内圆角 = 外圆角 − 内边距。

### 间距 `semantic.space`

`pagePadding 16` · `cardPadding 14` · `cardGap 10` · `sectionGap 20` · `inlineGap 8` · `tightGap 4` · `listRowPadding 14` · `formFieldGap 10`

### 层次 `scales.elevation`

**默认全部 0**。阴影只保留在：弹层（Dialog / Sheet / PopupMenu / FAB）。

卡片、按钮、列表一律**无阴影**。

---
### 层次 `scales.elevation`

**默认全部 0**。阴影只保留在：弹层（Dialog / Sheet / PopupMenu / FAB）。

卡片、按钮、列表一律**无阴影**。

---

## §2.5 组件契约（B0 已落地）

> **后续所有页面重写必须用下表组件，禁止自己拼 `Row + Card` + 分隔线 / 自造徽章 / 自造骨架。**
> B0a 落地 7 个 Flutter 组件（`flutter_app/lib/core/widgets/app_*.dart`）。
> B0b 同步落地 web 侧同名组件（`src/components/ui/*.tsx`）—— 任一端遗漏 = UI 漂移。
> 令牌来源一律 `tokens.g.dart` / Tailwind 语义类，不允许字面值（护栏：`tools/check-ui-tokens.sh`，基线 0）。

| 组件 | 一句话职责 | 关键参数（契约） |
|---|---|---|
| **AppListRow** | 同质列表的唯一行组件（客户 / 跟进 / 记录 / 沙龙 列表） | `leading` (44pt)、`title` (md+medium)、`subtitle` (sm+secondary)、`meta` (sm+tertiary)、`trailing`、`onTap`、`dense` (60/52)、`showDivider`。无卡片/无圆角；分隔线随 leading 左缩进；热区 ≥48 |
| **AppSectionHeader** | 区块标题（纯文字 + 可选 action + 可选副标题） | `title` (lg+semibold)、`subtitle` (sm+secondary)、`action`、`padding`。无装饰条/色块/图标前缀 |
| **AppSection** | AppSectionHeader + 子内容一站式容器 | `title`、`subtitle`、`action`、`child`、`childPadding`、`outerPadding`（默认 pagePadding）。不画边框/阴影/卡片背景 |
| **AppStatRow** | 详情页一行键值对（左 label / 右 value） | `label` (sm+secondary)、`value` (md+medium+textPrimary+**等宽数字**)、`valueColor`、`trailing`、`onTap`、`dense` (40 vs 48)、`showDivider` |
| **AppStatGroup** | 多行 AppStatRow 视觉组（组内 8, 组间 20） | `children`、`gap`、`padding` |
| **AppSheetHeader** | 底部弹层统一头部（配合 dragHandle=true） | `title` (lg+semibold)、`subtitle` (sm+secondary)、`actions: List<Widget>`、`padding`、`showDivider`。不自画手柄（走 BottomSheetThemeData） |
| **AppSkeleton** | 单块骨架占位（静止，无动画） | `width`、`height`、`radius` (默认 r6)、`color` (默认 surfaceSunken) |
| **AppSkeletonList** | 模拟 AppListRow 的骨架列表（行高一致避免跳动） | `rows` (默认 5)、`showLeading`、`showSubtitle`、`dense` |
| **AppBadge** | 统一状态徽章（色 + 文字双编码，色弱也能分） | `label`、`tone ∈ {neutral, brand, success, warning, danger, info, gold}`、`dense`、`foreground`、`background`。圆角 4, 字号 xs, color **必显式写** |
| **AppEmptyState** | B 档空态组件（原则 8：必须告诉「下一步做什么」） | `icon`、`title` (必填)、`hint`、`action`、`secondaryAction`、`padding` |
| **EmptyState** *(兼容入口)* | 旧空态组件（保留兼容），**新代码优先用 AppEmptyState** | 原 `onAction` + `actionLabel` 仍可用；新增 `action` / `secondaryAction` widget 参数可替换默认按钮 |
| **franchise_chip.dart** *(待迁移)* | 旧加盟徽章；B2 迁移到 AppBadge (tone=brand/success/info) | B0a **不动** —— 仅在注释里留迁移提示 |

**硬规则（每个组件都遵守）**：

- 每个 `TextStyle` **必须显式写 color**。`test/app_kit_test.dart` 已用 `DefaultTextStyle.of(context)` 验证解析后样式。
- 所有数值（间距/字号/圆角/颜色/尺寸/层次）从 `tokens.g.dart` 取；品牌色走 `context.tokens.xxx`。
- 不引入新依赖。
- 触摸底线 ≥ 48（`AppSize.tapMin`）。

---

## §3 三条**不要丢**（它们不是适老化）

纠偏时容易连这些一起丢掉，但它们是**通用正确性**：

### 3.1 触摸热区 ≥ 48pt —— **视觉可以小，热区不能小**

Apple HIG / Material 的硬标准，不是老人专属。**"紧凑"和"好点"不矛盾**：

```dart
// 视觉 20px 的图标按钮，热区仍是 48px
IconButton(
  iconSize: AppSize.iconMd,                                   // 视觉
  constraints: const BoxConstraints(minWidth: AppSize.tapMin,  // 热区
                                    minHeight: AppSize.tapMin),
  padding: const EdgeInsets.all(AppSpace.s14),                 // 差的用 padding 撑
)
```

> 这条决定了整个"紧凑化"会不会变成"难点化"。
> **验收：任何可点元素的 hit box ≥ 48×48**（不是视觉尺寸）

### 3.2 对比度底线 **AA (4.5:1)** —— 硬门槛

业界标准（微信 / Linear / Stripe 都按 AA）。
**降低到 AA 是为了给调色板自由度**（AAA 会锁死成暗淡配色），但**不能再降**。

保留的两条更严的：
- **正文对背景 ≥ 7:1**（便宜且真有用，防止有人选浅灰当正文）
- **边框对卡片 ≥ 1.5:1**（1.32:1 等于没画线，这是曾经的真 bug）

> ⚠ 历史教训：暖橙底配白字只有 **2.21:1** —— 曾经真的存在过。`on*` 前景色
> 由生成器按亮度自动推导，就是为了让这类错误物理上不可能发生。

### 3.3 字号档位功能 —— **保留，默认值降下来**

把"给所有人一刀切的大"换成 **"默认为紧凑 + 想大字的自己调"** —— 两边都照顾，更专业。

`settings_provider.dart` 已有四档：小 0.85 / 标准 1.0 / 大 1.15 / 特大 1.3。
与系统字号叠加后夹在 `[0.7, 1.6]`。

---

## §4 Review 检查清单

任何 UI 改动（含 agent 自动改动）提交前逐条过：

- [ ] **密度**：客户列表一屏 ≥ 9 条？首屏能看到"下一步动作"？
- [ ] **层级**：整屏字号档 ≤ 5 个？遮住字号仍能分辨层级？
- [ ] **分组**：组内间距 ≤ 组间间距的 1/2？
- [ ] **容器**：一屏有边框/阴影的元素 ≤ 2 个？列表页无卡片？
- [ ] **组件契约**：列表行用了 `AppListRow` 而不是自己拼 `Row` + `Card`？
- [ ] **容器计数**：列表页一屏「有边框或有阴影」的元素 ≤ 2？
- [ ] **颜色**：转灰度后信息不丢？饱和色块 ≤ 3 处？
- [ ] **热区**：所有可点元素 hit box ≥ 48×48？（不是视觉尺寸）
- [ ] **对比度**：`pnpm tokens:contrast` 无 FAIL？
- [ ] **令牌**：`tools/check-ui-tokens.sh` 硬编码计数未上涨？
- [ ] **真机**：真机截图看过（web 预览会骗人，见 AGENTS §5）
- [ ] **卡片棘轮 (B4)**：`bash tools/check-ui-tokens.sh` 的 `flutter.cardWidget` 未上涨？
  若确需新增 Card，须在 `tools/check-ui-tokens.sh` 的 `FLUTTER_CARD_WHITELIST`
  数组里加文件路径 + 拍板日期（理由写在 commit message）
- [ ] **密度棘轮 (B4)**：`bash tools/check-ui-density.sh` 全路由不涨？
  列表路由 `/admin/customers` / `/admin/follow-ups` / `/admin/interactions` /
  `/admin/wellness-records` 的 `framed ≤ 基线` 且 `visibleRows ≥ 10 @1440×900`
- [ ] **字重验证 (B4)**：Android 中文真机是否真有 `w500` 笔画？见
  [`docs/ui-font-weight-verification.md`](./ui-font-weight-verification.md)
  （本批状态：**未在真机验证**, 主人跑 `tools/font-weight-probe/` 后填结论）
- [ ] **白字回归 (B4)**：本批引入/改造的 Flutter 组件的 TextStyle 都显式 color？
  跑 `cd flutter_app && flutter test test/app_kit_white_text_test.dart --concurrency=1`
  （防 AGENTS §5 chip 白字教训）

---

## §5 反模式（写下来防复发）

- ❌ **靠放大表达重要** —— 层级是字重+颜色的活，不是字号的活
- ❌ **所有间距都偏大** —— 没有对比的留白 = 没有分组
- ❌ **卡片套卡片** —— 一个信息块最多一层容器
- ❌ **一屏十种颜色** —— 颜色是信号，一屏饱和色 ≤ 3
- ❌ **给列表加卡片** —— 同质列表用分隔线
- ❌ **为了紧凑牺牲热区** —— 视觉尺寸和 hit box 是两回事
- ❌ **"紧凑"= 减小行高但保留双层标题** —— 先删装饰，再谈压缩
- ❌ **在 web 预览上做最终验收** —— CanvasKit 兜底色与真机不同（AGENTS §5 chip 白字教训）
- ❌ **给验证脚本写死期望值** —— 期望值必须从 `design-tokens.json` 读（2026-09-23 漂移教训）

---

## §6 与其他文档的关系

| 文档 | 关系 |
|---|---|
| [`docs/CHARTER.md`](./CHARTER.md) §1 | 项目 vibe / 用户画像（本文件 §0 的纠偏依据） |
| [`docs/ui-tokens.md`](./ui-tokens.md) | 令牌机制：怎么改、怎么加主题、怎么防漂移 |
| [`AGENTS.md`](../AGENTS.md) §1 §3 | 操作层：agent 做 UI 改动时的强制规则 |
| [`design/tokens/ui-token-baseline.json`](../design/tokens/ui-token-baseline.json) | 硬编码棘轮基线（`flutter.cardWidget` 等） |
| [`design/tokens/density-baseline.json`](../design/tokens/density-baseline.json) | 密度棘轮基线 (`framed` / `visibleRows`) — **B4 新** |
| [`docs/ui-font-weight-verification.md`](./ui-font-weight-verification.md) | Android CJK 字重真机验证状态 — **B4 新** |
| [`tools/check-ui-tokens.sh`](../tools/check-ui-tokens.sh) | 硬编码棘轮护栏 (Bash + vitest 双保险) |
| [`tools/check-ui-density.sh`](../tools/check-ui-density.sh) | 密度棘轮护栏 (framed / visibleRows / rowHeight) — **B4 新** |
| [`tools/check-auto-snapshot-extension.sh`](../tools/check-auto-snapshot-extension.sh) | 扩展护栏: `agent_end` + `git add -A` 双重禁用 — **B4 新** |
