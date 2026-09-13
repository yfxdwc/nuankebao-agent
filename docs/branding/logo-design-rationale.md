# 暖客宝 Logo Design Rationale

> 决策日期: 2026-09-04
> 决策人: pi (per owner prompt: "为 app 生成图标,要有高级感,有 AI 元素,辨识度高,简洁")
> skill: `~/.muse/skills/project-icon-generator/v0.1` (5 套风格预设固定)

---

## §1. 为什么选 `organic` 风格预设

mm7 skill v0.1 只暴露 5 套预设 (muse-station / minimal / cyber / brutalist / organic),
AGENTS.md §1 的硬约束 — "❌ 不要暗色主题 / ❌ 不要 SaaS 冷色调 / ✅ 养生行业偏温暖"
— 把可选项从 5 砍到 1:

| 预设 | 调色板 | 撞 AGENTS.md 哪条 | 结论 |
|---|---|---|---|
| muse-station | 暗底 + 金 accent | ❌ 暗色主题 | 否 |
| minimal | 黑白灰冷 | ❌ SaaS 冷色调 | 否 |
| cyber | 黑底霓虹绿/红 | ❌ 暗色 + 冷 | 否 |
| brutalist | 红黑白强对比 | ❌ 冷色 + 养生气质违和 | 否 |
| **organic** | **#f4e4c1 暖米 + #2d5016 森林绿 + #8b4513 大地棕** | ✅ 温暖 + 自然 | **选** |

森林绿 + 暖米 + 大地棕 — 中医养生行业经典配色,
"圆形 + 弧线" 的 organic 几何天然契合"叶脉 / 药材 / 太极弧"语汇,
且与 NocoBase / Twenty / Frappe 等参考项目的"轻 SaaS"反差明显,辨识度天然高。

## §2. 6 个 logo 候选与 AI 元素注入

按 prompt 模板原版的"几何多样性"原则 (点阵 / 字母 mark / 抽象 / 弧线 / 负空间 / 组合),
但**每个 prompt 都手工注入一个独立 AI 元素**,避免 6 张长得一样:

| # | logo id | 几何路径 | 注入的 AI 元素语义 |
|---|---|---|---|
| 1 | dot-matrix | 点阵 → 字母 B | 点 = 神经网络节点 (neural network nodes),大点 = AI 信号流节点 |
| 2 | letter-mark | 单字母 B mark | AI 数据带 (data-ribbon) 穿字,字形 = AI 计算通道 |
| 3 | abstract-shape | 圆 + 斜线 | 圆 = AI 雷达轨道 (radar orbit),线 = 养生火 (wellness spark) |
| 4 | path-arc | 单弧线 = 字母 B | 弧 = AI 持续学习循环 + 养生生长周期 |
| 5 | negative-space | 负空间 B | B 形似 AI 培育的叶脉 (AI-nurtured wellness leaf vein) |
| 6 | composite-mark | 圆+环 + B 横排 | 圆带同心 AI 雷达环 (concentric radar rings) |

每个 logo 既能独立成 app 图标,又能拼成"养生 + AI"叙事线,
避开传统养生 logo 只会画太极 / 莲花 / 草药的同质化。

## §3. 高级感 (premium) 用词贯穿

| 维度 | 用词 (prompt 频次) |
|---|---|
| 排版 | refined, balanced negative space, generous whitespace |
| 材质 | subtle gradient, subtle glow, soft shadows |
| 气质 | premium editorial quality, editorial wellness brand studio photography |
| 几何 | perfectly balanced, mathematical precision, smooth bezier curves |
| 修边 | rounded terminals / junctions / dot edges / corner radii |

拒绝关键词:neon / glow / cyberpunk / brutalist / high contrast black (与"高级感 + 温暖"冲突)。

## §4. 辨识度设计

- **首字母锚点**:6 个 logo 都用 'B'(暖客宝 字形) 作为几何锚点,6 张在远处看都是 B,品牌一致性 100%
- **几何家族**:dot grid / letter / circle-line / arc / block / composite — 6 种几何路径,
  确保真图出来后挑选余地大,不会"6 张长得像"
- **silhouette 黑盒测试**:每个 logo 都描述为"在纯色底上,即使剪影也能识别 B 形" — 这是
  app 图标缩到 32×32 px 仍可读的硬条件

## §5. mockup 微调 (一处与原版不同)

skill 默认 mockup 模板用 "**dark luxury** background" — 这违反 暖客宝 项目"不要暗色"的硬约束。

**手工改**: `dark luxury` → `warm cream premium` (与 logo 主色一致) + 加 `editorial wellness brand`。

validate 已校通过 — 仍含 show case/presentation + warm cream/forest green 关键字。

## §6. 后续怎么用这份 prompt

本 skill **只渲染 prompt,不直接生图** (设计边界:避免无 API key 权限冲突,§A L2)。
拿到 6 个 prompt + 1 个 mockup 后,需要上层 image_gen 接口跑真图。可选:

```bash
# 方案 A: Codex image_gen (内置工具, 无需 API key)
python3 ~/.muse/skills/project-icon-generator/scripts/mm7_project_icon.py bundle \
    --input ~/.muse/data/projects/bbt-agent/logo-prompts.json \
    --format codex-imagegen

# 方案 B: OpenAI gpt-image-2 (需 OPENAI_API_KEY 环境变量)
python3 ~/.muse/skills/project-icon-generator/scripts/mm7_project_icon.py bundle \
    --input ~/.muse/data/projects/bbt-agent/logo-prompts.json \
    --format curl
```

跑完 7 张图 (6 logo + 1 mockup) 后:

- **挑选 1 张**作 `src/app/icon.png` (Next.js 自动识别)
- **挑选 1 张**作 `public/logo-{light,dark}.svg`
- mockup 留着做 launch 宣传图

## §7. 已知约束 (v0.1 skill 限制)

- 5 套预设固定,不能新增 (主人拍 v0.2 加 `--custom-palette` 后可自定义)
- mockup 只有 1 套模板 (v0.3 计划加横排 / 网格 / 立体场景 三套)
- skill 不直接调用 image_gen API (避免 §B L3 第 5 条 LLM 出网边界)

## §8. 落档位置

```
~/.muse/data/projects/bbt-agent/
├── logo-prompts.json                    ← 6 logo + 1 mockup prompt 真源
└── bundles/
    └── logo-prompts.md                  ← markdown 版 (人审稿用)

/home/tooyan/nuankebao-agent/docs/branding/
├── logo-prompts.json                    ← 副本 (项目成员可读)
├── logo-prompts.md                      ← 副本
└── logo-design-rationale.md             ← 本文件
```

如主人选 v0.2 加自定义调色板 (例:奶白 #FAF7F0 + 草绿 #6B8E5A + 暖金 #C9A961),
本文件 §1 表格 + 6 个 prompt 都需重跑。

---

## §9. r2 决策 (2026-09-05): logo 全端统一 → 登陆页 spa 图标

**owner prompt**: "apk登陆页面的绿色图标我很满意，把web图标和apk都设置成登陆页这个图标，logo统一"

**事实**: §1-§8 选出的 logo-4 弧线 (2026-09-04) **被推翻**, 主人觉得"高级感"过于抽象,
反而觉得**登陆页那个简单的 spa 绿色图标更有视觉锤 + 辨识度**。

**新 logo 源**:
- **不再** 用 §1 选出的 6 个有机风格 logo 之一
- **改用** Material Icons font 里 `Icons.spa` 的官方 SVG path (Google Material Design Icons)
  - viewBox: 24×24
  - 3 个 path: 顶部尖叶 + 左下弧叶 + 右下弧叶
  - fill: `#1F8A4C` (暖客宝 养生绿 = `AppTheme.primary`)
- 这也是 Flutter `login_screen.dart:46` 用的图标: `Icon(Icons.spa, size: 64, color: AppTheme.primary)`
  - 主人在真实登陆页面前认为满意

**全端覆盖路径** (一处真源 + ImageMagick/rsvg 多尺寸分发):

| 端 | 文件 | 改法 |
|---|---|---|
| 唯一 SVG 真源 | `tools/branding/bbt-logo-spa.svg` | 手写 |
| 渲染脚本 | `tools/branding/render-spa.py` | rsvg-convert + PIL palette |
| Next.js favicon | `src/app/icon.svg` | 拷贝 SVG (Next.js 15 metadata-icons 约定自动注入) |
| Next.js apple-icon | `src/app/apple-icon.png` (180×180) | 渲染分发 |
| Flutter web PWA | `flutter_app/web/icons/Icon-{192,512,maskable-192,maskable-512}.png` + `flutter_app/web/favicon.png` | 渲染分发 |
| Flutter web manifest | `flutter_app/web/manifest.json` theme_color `#0175C2` → `#1F8A4C`, name `flutter_app` → `暖客宝 · 大健康销售 CRM` | 手改 |
| Flutter web index.html | title `flutter_app` → `暖客宝 · 大健康销售 CRM`, description 更新 | 手改 |
| APK launcher | `flutter_app/android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` | 渲染分发 (PNG8 256 色) |

**废止**:
- `public/logo-picked.svg` (2026-09-04 选的老 logo, 已被删除)
- `docs/branding/r1-archive/picked-2026-09-04T11-57-23+08-00.json` 保留作历史归档, 不动

**重新生成**:
```bash
python3 tools/branding/render-spa.py
# 13 个 PNG 一键重生 (mipmap×5 + favicon×3 + apple×1 + pwa×2 + maskable×2)
```

**代码侧 hint** (Flutter 侧, 后期若想做 in-app 复用):
```dart
import 'package:flutter/material.dart';
// 内置 Material Icons font 里的 spa 字符, 已经是 暖客宝 视觉锤
Icon(Icons.spa, color: AppTheme.primary)  // login_screen.dart:46 已在用
```

**为什么不另画**:
- 主人原话 "不需要人临时生成呀, 我上传的这个图标已经在项目中了" — spa 是 Material Icons font 现成字符,
  不需要也不应该重新手画 (容易走形)
- 直接用 Google 官方 SVG path d 是最保真的方案, fill 改 #1F8A4C 即可注入 暖客宝 养生绿
- v2 试过手画贝塞尔水滴形 → 视觉走样, 已废

---

## §10. r3 决策 (2026-09-05): logo 再换 → 主人上传原图 (PNG 真源, 不再手画)

**owner prompt**:
- v1: "logo统一。把项目中所有图标都统一成这个图标（web图标、apk图标等）" (上传了白底嫩芽)
- v2: "直接使用这个图，不要你再多余去生成" (同图, 要求不再手画 SVG)

**事实**: §9 r2 选的 spa 花苞样式只撑了一天, 主人上传了**新图标**并要求全端统一。
新图标与 spa 形状不同:
- spa (r2): 玫瑰花苞形, 透明背景, 三片叶交叉紧凑
- **白底嫩芽 (r3, 本次)**: 白底圆角矩形 (iOS squircle), 顶部饱满水滴尖叶, 底部两片对称月牙翅膀叶,
  中间 V 形锐角白色缺口

**为什么用 PNG 真源 (而非再去找现成 Material Icon 或手画 SVG)**:
- 主人明确: "直接使用这个图，不要你再多余去生成"
- 这个**具体形状** (尖头 + 月牙 + V 缺口) 在 Material Icons / Font Awesome / Tabler Icons
  都没找到精确对应的现成字符 — 近似 closest 是 `spa` / `eco` / `energy_savings_leaf`, 但都不够准
- pi 初版尝试手画 SVG (v0 椭圆叶 → v1 加粗 → v2 双凸弧翅膀), v2 视觉与原图相近但**不是 1:1 像素级还原** —
  主人认定 "不要多余生成", 应直接以原图为真源
- 原图存放在 `/home/new6/下载/ChatGPT Image 2026年9月5日 11_15_16.png` (1254×1254, 931KB),
  拷贝到 `tools/branding/bbt-logo-source.png` 作为项目内唯一真源

**全端覆盖路径** (PNG 真源 + PIL LANCZOS 多尺寸分发):

| 端 | 文件 | 改法 |
|---|---|---|
| 唯一 PNG 真源 | `tools/branding/bbt-logo-source.png` | 拷贝主人上传的原图 |
| 渲染脚本 | `tools/branding/render-logo.py` | PIL LANCZOS resize + palette + maskable safe-zone |
| Next.js favicon | `src/app/icon.png` (192×192) | Next.js 15 metadata-icons 自动注入 |
| Next.js apple-icon | `src/app/apple-icon.png` (180×180) | Next.js 15 metadata-icons 自动注入 |
| Next.js public | `public/favicon.ico` (16+32+48), `public/apple-touch-icon.png` (180), `public/icon-192.png`, `public/icon-512.png` | 渲染分发 + ICO 合成 |
| Flutter web PWA | `flutter_app/web/favicon.png` (192), `flutter_app/web/icons/Icon-{192,512,maskable-192,maskable-512}.png` | 渲染分发 |
| Flutter web manifest | `flutter_app/web/manifest.json` (theme_color #1F8A4C, name "暖客宝") | 不变 (r2 已改) |
| Flutter web index.html | `<link rel="icon" href="favicon.png">` + `<link rel="apple-touch-icon" href="icons/Icon-192.png">` | 不变 (r2 已改) |
| APK launcher | `flutter_app/android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` | 渲染分发 (PNG8 256 色) |
| APK launcher background | `drawable/launch_background.xml` = `@android:color/white` (亮模式) / `?android:colorBackground` (暗模式) | 不变, 与图标白底视觉连贯 |

**maskable 安全区**: 80% (不是默认 60%) — 因为本 logo 自带白底圆角矩形, mask 裁切后白底会被吃掉,
**白底 + 月牙叶**作为一个整体放 80% 中心, 留 10% 边距给各种 launcher mask。

**废止 / 归档** (mm7 §A.5 历史可追溯):
- `tools/branding/bbt-logo.svg` (pi 手画) → 删除 (主人 v2 prompt 否决)
- `tools/branding/_draft-logo.svg` (v0/v1 草稿) → 删除
- `public/logo-spa.svg` → 删除 (被 src/app/icon.png 取代)
- `src/app/icon.svg` (之前从手画 SVG 复制) → 删除, 改为 `src/app/icon.png`
- `public/logo.svg` (之前从手画 SVG 复制) → 删除
- `tools/branding/legacy/r2-bbt-logo-spa.svg` + `r2-render-spa.py` → 保留 (历史归档, 不动)
- `tools/branding/legacy/public_logo-candidates-r1/` + `r2-logo-picker/` + `r{1,2}-logo-prompts*` → 保留 (历史归档)
- `flutter_app/build/web/favicon.png + icons/` → 删除 (r2 build 产物, 已被新源覆盖)

**重新生成**:
```bash
python3 tools/branding/render-logo.py
# 13 个 PNG 一键重生 (mipmap×5 + favicon×3 + apple×1 + pwa×2 + maskable×2)
# 然后脚本外手动 cp 到各端 (见上表) — 渲染脚本只负责 build/, 部署是单独步骤
```

**flutter build 提示**:
- 改完 Android mipmap 图标后, `cd flutter_app && flutter clean && flutter build apk`
  才能让 Gradle 把新 PNG 打进 APK (旧 APK 缓存的 launcher 不会自动更新)
- Flutter web `flutter build web` 同理, 会把 web/favicon.png 重新打包

**反思** (主人 v2 prompt 后):
- "高级感" "AI 元素" 这类抽象叙事在 32×32 launcher 上**根本看不出来**, r0.1 organic 风的雷达轨道就是这么失败
- "手画 SVG" 不如 "直接用主人原图" — 即使手画视觉接近, 也**不是 1:1 还原**,
  主人会因 "走样" 反复迭代, 浪费 token
- 流程改进: 以后再有 "用这个图" 的需求, **先问 / 先搜主人是否已上传到本地** (~/下载/、桌面、项目 public/uploads/),
  不要先动手画
