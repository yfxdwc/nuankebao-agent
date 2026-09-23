#!/usr/bin/env tsx
// ============================================
// 设计令牌生成器 (暖客宝 UI 单一真相源 → 两端)
// ============================================
//
// 源:   design/tokens/design-tokens.json
// 产物: ① flutter_app/lib/core/theme/tokens.g.dart   (Flutter: 常量 + AppTokens + 主题目录)
//       ② src/lib/design-tokens.g.ts                (Web/TS: 图表 / meta themeColor / canvas 用)
//       ③ src/styles/globals.css                    (标记注入块: CSS 变量 + [data-theme] 覆盖)
//
// 用法:
//   pnpm tokens:build     生成 (幂等)
//   pnpm tokens:check     只校验 (CI / pre-commit 用; 磁盘产物与源不一致 → exit 1)
//   pnpm tokens:contrast  打印所有主题的对比度体检表
//
// 为什么用「标记注入」而不是 @import 一个 tokens.css:
//   本项目没装 postcss-import, Next.js 也没有内置 —— @import 会静默失效.
//   标记注入零依赖且能保住 globals.css 里手写的那部分 (base layer).
//
// 自动推导的东西 (不要手写 JSON):
//   onPrimary / onAccent / onSuccess / ... = 按 WCAG 相对亮度自动选白或深色前景,
//   保证「换主题不会换出白字白底」。

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve as pathResolve } from "node:path";

const ROOT = process.cwd();
const SRC = pathResolve(ROOT, "design/tokens/design-tokens.json");
const OUT_FLUTTER = pathResolve(ROOT, "flutter_app/lib/core/theme/tokens.g.dart");
const OUT_TS = pathResolve(ROOT, "src/lib/design-tokens.g.ts");
const OUT_CSS = pathResolve(ROOT, "src/styles/globals.css");

const BEGIN_MARK = "/* ==== BEGIN GENERATED: design tokens (pnpm tokens:build) ==== */";
const END_MARK = "/* ==== END GENERATED: design tokens ==== */";

type Json = Record<string, any>;

const MODE: "build" | "check" | "contrast" = process.argv.includes("--check")
  ? "check"
  : process.argv.includes("--contrast")
    ? "contrast"
    : "build";

// ============================================
// 颜色工具 (WCAG 2.1 相对亮度 + 对比度)
// ============================================

function hexToRgb(hex: string): { r: number; g: number; b: number } {
  const h = hex.replace("#", "").trim();
  const full =
    h.length === 3
      ? h
          .split("")
          .map((c) => c + c)
          .join("")
      : h;
  if (!/^[0-9a-fA-F]{6}$/.test(full)) throw new Error(`非法 hex 色值: ${hex}`);
  return {
    r: parseInt(full.slice(0, 2), 16),
    g: parseInt(full.slice(2, 4), 16),
    b: parseInt(full.slice(4, 6), 16),
  };
}

function srgbToLinear(c8bit: number): number {
  const c = c8bit / 255;
  return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function relLuminance(hex: string): number {
  const { r, g, b } = hexToRgb(hex);
  return (
    0.2126 * srgbToLinear(r) + 0.7152 * srgbToLinear(g) + 0.0722 * srgbToLinear(b)
  );
}

/** WCAG 对比度 (1..21) */
export function contrastRatio(a: string, b: string): number {
  const la = relLuminance(a);
  const lb = relLuminance(b);
  const hi = Math.max(la, lb);
  const lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

function toDartHex(hex: string): string {
  const { r, g, b } = hexToRgb(hex);
  const h = (n: number) => n.toString(16).toUpperCase().padStart(2, "0");
  return `0xFF${h(r)}${h(g)}${h(b)}`;
}

// ============================================
// 令牌解析
// ============================================

const doc: Json = JSON.parse(readFileSync(SRC, "utf8"));

/** 解析 `{a.b.c}` 形式的令牌引用 (W3C DTCG 别名语法) */
function resolveRef(value: unknown, seen: string[] = []): unknown {
  if (typeof value !== "string") return value;
  const m = /^\{([^}]+)\}$/.exec(value.trim());
  if (!m) return value;
  const path = m[1];
  if (seen.includes(path)) throw new Error(`令牌引用成环: ${seen.join(" → ")} → ${path}`);
  let cur: any = doc;
  for (const seg of path.split(".")) {
    cur = cur?.[seg];
    if (cur === undefined) throw new Error(`无法解析令牌引用 {${path}}`);
  }
  return resolveRef(cur, [...seen, path]);
}

/** 解析一张扁平映射, 并强制所有叶子为 hex 色值 */
function resolveColorMap(map: Json, where: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(map)) {
    const resolved = resolveRef(v);
    if (typeof resolved !== "string" || !resolved.startsWith("#")) {
      throw new Error(`${where}.${k} 解析后不是 hex 色值 (得到 ${JSON.stringify(resolved)})`);
    }
    out[k] = resolved.toUpperCase();
  }
  return out;
}

const palette = resolveColorMap(doc.palette, "palette");
const sharedColors = resolveColorMap(doc.shared, "shared");

// ============================================
// 按对比度自动推导「前景色」(on*)
// ============================================

const LIGHT_FG: string = resolveRef(doc.contrast.lightForeground) as string;
const DARK_FG: string = resolveRef(doc.contrast.darkForeground) as string;
const MIN_RATIO: number = doc.contrast.minOnColorRatio ?? 4.5;
const PREFER_RATIO: number = doc.contrast.preferRatio ?? 7;

/** 需要自动配前景色的底: 令牌键 → 生成的前景键名 */
const FG_PAIRS: Array<[string, string]> = [
  ["primary", "onPrimary"],
  ["accent", "onAccent"],
  ["success", "onSuccess"],
  ["warning", "onWarning"],
  ["danger", "onDanger"],
  ["info", "onInfo"],
];

const contrastWarnings: string[] = [];

function deriveForeground(bgHex: string, label: string): string {
  const cLight = contrastRatio(bgHex, LIGHT_FG.toUpperCase());
  const cDark = contrastRatio(bgHex, DARK_FG.toUpperCase());
  const pickLight = cLight >= cDark;
  const best = pickLight ? cLight : cDark;
  if (best < MIN_RATIO) {
    contrastWarnings.push(
      `⚠ ${label} (${bgHex}) 最优前景对比度仅 ${best.toFixed(2)}:1 < ${MIN_RATIO}:1 (WCAG AA)`,
    );
  } else if (best < PREFER_RATIO) {
    contrastWarnings.push(
      `· ${label} (${bgHex}) 前景对比度 ${best.toFixed(2)}:1 (达 AA, 未达 AAA ${PREFER_RATIO}:1; 仅大字号可用)`,
    );
  }
  return pickLight ? LIGHT_FG.toUpperCase() : DARK_FG.toUpperCase();
}

// ============================================
// 主题装配
// ============================================

interface ThemeDef {
  id: string;
  label: string;
  group: string;
  isDefault: boolean;
  colors: Record<string, string>;
}

const themeDefs: ThemeDef[] = (doc.themes as Json[]).map((t, idx) => ({
  id: t.id as string,
  label: t.label as string,
  group: (t.group as string) ?? "主题",
  isDefault: t.isDefault === true || idx === 0,
  colors: resolveColorMap(t.colors as Json, `themes.${t.id}.colors`),
}));

if (themeDefs.filter((t) => t.isDefault).length !== 1) {
  // 允许多个 isDefault=false 的写法, 但必须恰好一个默认; 否则回退到第一个
  themeDefs.forEach((t, i) => (t.isDefault = i === 0));
}
const DEFAULT_THEME = themeDefs.find((t) => t.isDefault)!;

/** 一个主题的完整语义色表 = 品牌槽 (按主题) + 共用槽 + 自动前景色 */
function buildThemeColors(t: ThemeDef): Record<string, string> {
  const merged: Record<string, string> = { ...sharedColors, ...t.colors };
  for (const [bgKey, fgKey] of FG_PAIRS) {
    if (fgKey in (t.colors as Json)) {
      throw new Error(
        `themes.${t.id}.colors.${fgKey} 不该手写 —— on* 前景色由生成器按对比度自动推导`,
      );
    }
    merged[fgKey] = deriveForeground(merged[bgKey], `${t.label}.${fgKey}`);
  }
  merged.focusRing = merged.primary;
  return merged;
}

const themeColors: Record<string, Record<string, string>> = {};
for (const t of themeDefs) themeColors[t.id] = buildThemeColors(t);

// ============================================
// 尺度
// ============================================

const spaceScale: Record<string, number> = doc.scales.space;
const radiusScale: Record<string, number> = doc.scales.radius;
const typeScale: Record<string, number> = doc.scales.type;
const weightScale: Record<string, number> = doc.scales.weight;
const sizeScale: Record<string, number> = doc.scales.size;
const elevationScale: Record<string, number> = doc.scales.elevation;
const durationScale: Record<string, number> = doc.scales.duration;
const opacityScale: Record<string, number> = doc.scales.opacity;
const semSpace: Record<string, string> = doc.semantic.space;
const semRadius: Record<string, string> = doc.semantic.radius;

// 自检: 语义别名必须指向真实存在的尺度键
for (const [alias, target] of Object.entries(semSpace)) {
  if (!(target in spaceScale)) throw new Error(`semantic.space.${alias} → ${target} 不存在于 scales.space`);
}
for (const [alias, target] of Object.entries(semRadius)) {
  if (!(target in radiusScale)) throw new Error(`semantic.radius.${alias} → ${target} 不存在于 scales.radius`);
}

// ============================================
// 图表色板 (Web recharts 用; 跟随主题)
// ============================================

function chartPalette(colors: Record<string, string>): string[] {
  return [
    colors.primary,
    colors.primaryLight,
    colors.accent,
    colors.info,
    colors.graphFranchiseeB,
    colors.textTertiary,
  ];
}

// ============================================
// 命名转换
// ============================================

/** `neutral-50` → `neutral50`; `springAccent-500` → `springAccent500` */
function camelKey(k: string): string {
  return k.replace(/-([a-z0-9])/gi, (_, c: string) => c.toUpperCase());
}

/** `s8` → `s8`; `buttonLgHeight` → `buttonLgHeight` */
function dartName(k: string): string {
  return k;
}

/** 8 → `8.0`, 0.5 → `0.5` */
function dartDouble(n: number): string {
  return Number.isInteger(n) ? `${n}.0` : String(n);
}

// ============================================
// ① Flutter 产物
// ============================================

function emitFlutter(): string {
  const L: string[] = [];
  const p = (s = "") => L.push(s);

  p("// GENERATED FILE — 请勿手改。");
  p("//");
  p("// 源:      design/tokens/design-tokens.json");
  p("// 重新生成: pnpm tokens:build");
  p("// 校验:     pnpm tokens:check (CI / pre-commit)");
  p("//");
  p("// 分层:");
  p("//   AppPalette   L0 原始调色板 —— 全项目唯一允许出现字面 hex 的地方(的镜像)");
  p("//   AppSpace/…   L1 尺度       —— 间距 / 圆角 / 字号 / 尺寸 / 层次 / 时长 / 透明度");
  p("//   AppTokens    L2 语义令牌   —— 每个主题一份实例 (运行时可变)");
  p("//   AppThemes    主题目录      —— 运行时换肤的入口");
  p("//");
  p("// ⚠ 运行时换肤: 业务代码要读 `context.tokens.primary`, **不要**读 AppThemes.sage.primary ——");
  p("//   后者写死了默认主题, 换肤不会生效。");
  p("");
  p("import 'package:flutter/material.dart';");
  p("");

  // ---- L0 palette ----
  p("/// L0 原始调色板 (不等于语义 —— 业务代码不该直接用, 用 AppTokens)");
  p("abstract final class AppPalette {");
  for (const [k, v] of Object.entries(palette)) {
    p(`  static const Color ${camelKey(k)} = Color(${toDartHex(v)});`);
  }
  p("}");
  p("");

  // ---- L1 scales ----
  p("/// L1 尺度 —— 间距 (中老年友好: 主档 8/12/16, 触控留白充足)");
  p("abstract final class AppSpace {");
  for (const [k, v] of Object.entries(spaceScale)) {
    p(`  static const double ${dartName(k)} = ${dartDouble(v)};`);
  }
  p("  // 语义别名");
  for (const [alias, target] of Object.entries(semSpace)) {
    p(`  static const double ${dartName(alias)} = ${target};`);
  }
  p("}");
  p("");

  p("/// L1 尺度 —— 圆角");
  p("abstract final class AppRadius {");
  for (const [k, v] of Object.entries(radiusScale)) {
    p(`  static const double ${dartName(k)} = ${dartDouble(v)};`);
  }
  p("  // 语义别名");
  for (const [alias, target] of Object.entries(semRadius)) {
    p(`  static const double ${dartName(alias)} = ${target};`);
  }
  p("}");
  p("");

  p("/// L1 尺度 —— 字号 (中老年: 正文 18 起步, Material 默认是 14)");
  p("abstract final class AppType {");
  for (const [k, v] of Object.entries(typeScale)) {
    p(`  static const double ${dartName(k)} = ${dartDouble(v)};`);
  }
  p("}");
  p("");

  p("/// L1 尺度 —— 字重");
  p("abstract final class AppWeight {");
  for (const [k, v] of Object.entries(weightScale)) {
    p(`  static const FontWeight ${dartName(k)} = FontWeight.w${v};`);
  }
  p("}");
  p("");

  p("/// L1 尺度 —— 组件尺寸");
  p("abstract final class AppSize {");
  for (const [k, v] of Object.entries(sizeScale)) {
    p(`  static const double ${dartName(k)} = ${dartDouble(v)};`);
  }
  p("}");
  p("");

  p("/// L1 尺度 —— 阴影层次 (Material elevation)");
  p("abstract final class AppElevation {");
  for (const [k, v] of Object.entries(elevationScale)) {
    p(`  static const double ${dartName(k)} = ${dartDouble(v)};`);
  }
  p("}");
  p("");

  p("/// L1 尺度 —— 动效时长 (毫秒)");
  p("abstract final class AppDuration {");
  for (const [k, v] of Object.entries(durationScale)) {
    p(`  static const Duration ${dartName(k)} = Duration(milliseconds: ${v});`);
  }
  p("}");
  p("");

  p("/// L1 尺度 —— 透明度");
  p("abstract final class AppOpacity {");
  for (const [k, v] of Object.entries(opacityScale)) {
    p(`  static const double ${dartName(k)} = ${dartDouble(v)};`);
  }
  p("}");
  p("");

  // ---- L2 AppTokens ----
  const colorKeys = Object.keys(themeColors[DEFAULT_THEME.id]);
  p("/// L2 语义令牌 —— 一个主题一份 (运行时可变, 用于换肤)");
  p("///");
  p("/// 取用方式 (业务代码唯一正确姿势):");
  p("///   `context.tokens.primary`   ← 见 core/theme/theme_ext.dart");
  p("@immutable");
  p("class AppTokens {");
  p("  final String id;");
  p("  final String label;");
  p("  final String group;");
  for (const k of colorKeys) p(`  final Color ${k};`);
  p("");
  p("  const AppTokens({");
  p("    required this.id,");
  p("    required this.label,");
  p("    required this.group,");
  for (const k of colorKeys) p(`    required this.${k},`);
  p("  });");
  p("");

  p("  /// 这个主题的对比度体检 (供设置页 / 测试用)");
  p("  Map<String, double> contrastReport() => <String, double>{");
  p("    'primary/onPrimary': _ratio(primary, onPrimary),");
  p("    'accent/onAccent': _ratio(accent, onAccent),");
  p("    'textPrimary/surface': _ratio(textPrimary, surface),");
  p("    'textSecondary/surface': _ratio(textSecondary, surface),");
  p("    'textPrimary/surfaceCard': _ratio(textPrimary, surfaceCard),");
  p("    'border/surfaceCard': _ratio(border, surfaceCard),");
  p("  };");
  p("");
  p("  static double _ratio(Color a, Color b) {");
  p("    final la = a.computeLuminance();");
  p("    final lb = b.computeLuminance();");
  p("    final hi = la > lb ? la : lb;");
  p("    final lo = la > lb ? lb : la;");
  p("    return (hi + 0.05) / (lo + 0.05);");
  p("  }");
  p("}");
  p("");

  // ---- AppThemes 主题目录 ----
  p("/// 主题目录 —— 运行时换肤的入口");
  p("///");
  p("/// ⚠ 业务代码不要直接读 `AppThemes.sage.primary` (写死了默认主题, 换肤不生效);");
  p("///   要读 `context.tokens.primary`。AppThemes 只在【装配 ThemeData】和【设置页列选项】两处用。");
  p("abstract final class AppThemes {");
  for (const t of themeDefs) {
    const c = themeColors[t.id];
    p(`  /// ${t.label} (${t.group})${t.isDefault ? " — 默认主题" : ""}`);
    p(`  static const AppTokens ${t.id} = AppTokens(`);
    p(`    id: '${t.id}',`);
    p(`    label: '${t.label}',`);
    p(`    group: '${t.group}',`);
    for (const k of colorKeys) {
      p(`    ${k}: Color(${toDartHex(c[k])}),`);
    }
    p("  );");
    p("");
  }
  p("  /// 全部主题 (设置页遍历 / 测试对比度)");
  p(`  static const List<AppTokens> all = <AppTokens>[`);
  for (const t of themeDefs) p(`    ${t.id},`);
  p("  ];");
  p("");
  p("  static const Map<String, AppTokens> byId = <String, AppTokens>{");
  for (const t of themeDefs) p(`    '${t.id}': ${t.id},`);
  p("  };");
  p("");
  p(`  static const String defaultId = '${DEFAULT_THEME.id}';`);
  p("");
  p("  /// 按 id 取主题; 未知 id 回落到默认 (存 shared_preferences 的值可能是旧版本遗留)");
  p("  static AppTokens resolve(String? id) => byId[id] ?? byId[defaultId]!;");
  p("");
  p("  /// 按分组列主题 (设置页: 品牌 / 季节)");
  p("  static Map<String, List<AppTokens>> get grouped {");
  p("    final out = <String, List<AppTokens>>{};");
  p("    for (final t in all) {");
  p("      out.putIfAbsent(t.group, () => <AppTokens>[]).add(t);");
  p("    }");
  p("    return out;");
  p("  }");
  p("}");
  p("");
  p("/// 生成器自检: 每个主题的【色值个数】必须一致 (防止加主题时漏槽位)");
  p(`const int kTokenColorCount = ${colorKeys.length};`);
  p("");

  return L.join("\n");
}

// ============================================
// ② Web TS 产物
// ============================================

function emitTs(): string {
  const L: string[] = [];
  const p = (s = "") => L.push(s);

  p("// GENERATED FILE — 请勿手改。");
  p("//");
  p("// 源:      design/tokens/design-tokens.json");
  p("// 重新生成: pnpm tokens:build");
  p("// 校验:     pnpm tokens:check");
  p("//");
  p("// 用途: 需要**真实色值**的 JS 场景 —— recharts / mermaid / canvas / <meta name=themeColor> /");
  p("//       CVA 变体常量。纯 CSS 场景请用 CSS 变量 (globals.css 里那一坨), 不要 import 这里。");
  p("");

  p("export const palette = {");
  for (const [k, v] of Object.entries(palette)) p(`  ${JSON.stringify(k)}: "${v}",`);
  p("} as const;");
  p("");

  p("export const space = {");
  for (const [k, v] of Object.entries(spaceScale)) p(`  ${JSON.stringify(k)}: ${v},`);
  p("} as const;");
  p("");

  p("export const radius = {");
  for (const [k, v] of Object.entries(radiusScale)) p(`  ${JSON.stringify(k)}: ${v},`);
  p("} as const;");
  p("");

  p("export const typeScale = {");
  for (const [k, v] of Object.entries(typeScale)) p(`  ${JSON.stringify(k)}: ${v},`);
  p("} as const;");
  p("");

  p("export const size = {");
  for (const [k, v] of Object.entries(sizeScale)) p(`  ${JSON.stringify(k)}: ${v},`);
  p("} as const;");
  p("");

  p("export const duration = {");
  for (const [k, v] of Object.entries(durationScale)) p(`  ${JSON.stringify(k)}: ${v},`);
  p("} as const;");
  p("");

  p("export const themeColors = {");
  for (const t of themeDefs) {
    p(`  ${JSON.stringify(t.id)}: {`);
    for (const [k, v] of Object.entries(themeColors[t.id])) {
      p(`    ${JSON.stringify(k)}: "${v}",`);
    }
    p("  },");
  }
  p("} as const;");
  p("");

  p("export const chartColors = {");
  for (const t of themeDefs) {
    p(`  ${JSON.stringify(t.id)}: ${JSON.stringify(chartPalette(themeColors[t.id]))},`);
  }
  p("} as const;");
  p("");

  p("export interface ThemeMeta {");
  p("  id: ThemeId;");
  p("  label: string;");
  p("  group: string;");
  p("}");
  p("");
  p("export const themeList: readonly ThemeMeta[] = [");
  for (const t of themeDefs) {
    p(`  { id: ${JSON.stringify(t.id)}, label: ${JSON.stringify(t.label)}, group: ${JSON.stringify(t.group)} },`);
  }
  p("] as const;");
  p("");

  p("export type ThemeId =");
  p(themeDefs.map((t) => `  | ${JSON.stringify(t.id)}`).join("\n") + ";");
  p("");
  p(`export const defaultThemeId: ThemeId = ${JSON.stringify(DEFAULT_THEME.id)};`);
  p("");
  p("export const themeIds = themeList.map((t) => t.id) as readonly ThemeId[];");
  p("");
  p("export function isThemeId(v: unknown): v is ThemeId {");
  p("  return typeof v === \"string\" && (themeIds as readonly string[]).includes(v);");
  p("}");
  p("");
  p("/** 当前活动主题的色值快照 (取默认主题; 运行时换肤请看 CSS 变量, 这里只是静态参考) */");
  p("export const defaultThemeColors = themeColors[defaultThemeId];");
  p("");
  p("export const defaultChartColors = chartColors[defaultThemeId];");
  p("");
  p("export const web = {");
  p(`  fontSans: ${JSON.stringify(doc.web.fontSans)},`);
  p(`  fontMono: ${JSON.stringify(doc.web.fontMono)},`);
  p(`  density: ${doc.web.density},`);
  p("  shadow: {");
  for (const [k, v] of Object.entries(doc.web.shadow as Json)) {
    p(`    ${JSON.stringify(k)}: ${JSON.stringify(v)},`);
  }
  p("  },");
  p("} as const;");
  p("");

  return L.join("\n");
}

// ============================================
// ③ Web CSS 产物 (标记注入)
// ============================================

function px2rem(px: number): string {
  return `${+(px / 16).toFixed(4)}rem`;
}

/** shadcn/ui 兼容层: 旧变量名 → 新语义令牌 */
function emitShadcnLayer(c: Record<string, string>): string[] {
  const L: string[] = [];
  const p = (s: string) => L.push(s);
  p("  /* --- shadcn/ui 兼容层 (607 处既有用法依赖这些名字, 不要删) --- */");
  p(`  --background: ${c.surface};`);
  p(`  --foreground: ${c.textPrimary};`);
  p(`  --card: ${c.surfaceCard};`);
  p(`  --card-foreground: ${c.textPrimary};`);
  p(`  --popover: ${c.surfaceCard};`);
  p(`  --popover-foreground: ${c.textPrimary};`);
  p(`  --primary: ${c.primary};`);
  p(`  --primary-foreground: ${c.onPrimary};`);
  p(`  --secondary: ${c.surfaceSubtle};`);
  p(`  --secondary-foreground: ${c.textPrimary};`);
  p(`  --muted: ${c.surfaceSubtle};`);
  p(`  --muted-foreground: ${c.textTertiary};`);
  p(`  --accent: ${c.accentSurface};`);
  p(`  --accent-foreground: ${c.textPrimary};`);
  p(`  --destructive: ${c.danger};`);
  p(`  --destructive-foreground: ${c.onDanger};`);
  p(`  --border: ${c.border};`);
  p(`  --input: ${c.borderInput};`);
  p(`  --ring: ${c.primary};`);
  p(`  --radius: ${px2rem(radiusScale.r8)};`);
  return L;
}

/** 新语义层 (避开 shadcn 的 --accent 等重名) */
function emitSemanticLayer(c: Record<string, string>, indent = "  "): string[] {
  const L: string[] = [];
  const p = (s: string) => L.push(indent + s);
  p(`--brand: ${c.primary};`);
  p(`--brand-light: ${c.primaryLight};`);
  p(`--brand-dark: ${c.primaryDark};`);
  p(`--brand-surface: ${c.primarySurface};`);
  p(`--brand-foreground: ${c.onPrimary};`);
  p(`--brand-accent: ${c.accent};`);
  p(`--brand-accent-light: ${c.accentLight};`);
  p(`--brand-accent-surface: ${c.accentSurface};`);
  p(`--brand-accent-foreground: ${c.onAccent};`);
  p(`--surface: ${c.surface};`);
  p(`--surface-card: ${c.surfaceCard};`);
  p(`--surface-subtle: ${c.surfaceSubtle};`);
  p(`--surface-sunken: ${c.surfaceSunken};`);
  p(`--surface-inverse: ${c.surfaceInverse};`);
  p(`--text-primary: ${c.textPrimary};`);
  p(`--text-secondary: ${c.textSecondary};`);
  p(`--text-tertiary: ${c.textTertiary};`);
  p(`--text-disabled: ${c.textDisabled};`);
  p(`--text-on-inverse: ${c.textOnInverse};`);
  p(`--border-default: ${c.border};`);
  p(`--border-strong: ${c.borderStrong};`);
  p(`--divider: ${c.divider};`);
  p(`--focus-ring: ${c.focusRing};`);
  p(`--success: ${c.success};`);
  p(`--success-light: ${c.successLight};`);
  p(`--success-surface: ${c.successSurface};`);
  p(`--success-foreground: ${c.onSuccess};`);
  p(`--warning: ${c.warning};`);
  p(`--warning-light: ${c.warningLight};`);
  p(`--warning-surface: ${c.warningSurface};`);
  p(`--warning-foreground: ${c.onWarning};`);
  p(`--danger: ${c.danger};`);
  p(`--danger-light: ${c.dangerLight};`);
  p(`--danger-surface: ${c.dangerSurface};`);
  p(`--danger-foreground: ${c.onDanger};`);
  p(`--info: ${c.info};`);
  p(`--info-light: ${c.infoLight};`);
  p(`--info-surface: ${c.infoSurface};`);
  p(`--info-foreground: ${c.onInfo};`);
  p(`--member-gold: ${c.memberGold};`);
  p(`--member-gold-surface: ${c.memberGoldSurface};`);
  p(`--badge-neutral: ${c.badgeNeutral};`);
  p(`--badge-neutral-surface: ${c.badgeNeutralSurface};`);
  p(`--graph-a: ${c.graphFranchiseeA};`);
  p(`--graph-a-surface: ${c.graphFranchiseeASurface};`);
  p(`--graph-b: ${c.graphFranchiseeB};`);
  p(`--graph-b-surface: ${c.graphFranchiseeBSurface};`);
  p(`--graph-line: ${c.graphLine};`);
  p(`--graph-line-soft: ${c.graphLineSoft};`);
  p(`--shadow-color: ${c.shadowColor};`);
  p(`--scrim: ${c.scrim};`);
  const charts = chartPalette(c);
  charts.forEach((v, i) => p(`--chart-${i + 1}: ${v};`));
  return L;
}

function emitCssBlock(): string {
  const L: string[] = [];
  const p = (s = "") => L.push(s);

  p(BEGIN_MARK);
  p("/*");
  p(" * 由 scripts/generate-tokens.ts 生成 —— 请勿手改本区块。");
  p(" * 改 token: 编辑 design/tokens/design-tokens.json, 然后 `pnpm tokens:build`");
  p(" * 校验:     `pnpm tokens:check` (CI 会跑; 不一致则 fail)");
  p(" */");
  p("");
  p(":root {");
  p("  /* ---- L0 原始调色板 ---- */");
  for (const [k, v] of Object.entries(palette)) p(`  --palette-${k}: ${v};`);
  p("");
  p("  /* ---- L1 尺度 ---- */");
  p("  /* 密度旋钮: 改这一个数就能整体收紧/放松全站间距 (JS: setProperty('--density', '0.9')) */");
  p(`  --density: ${doc.web.density};`);
  for (const [k, v] of Object.entries(spaceScale)) {
    const n = k.replace(/^s/, "");
    p(`  --space-${n}: calc(${px2rem(v)} * var(--density));`);
  }
  for (const [k, v] of Object.entries(radiusScale)) {
    if (k === "full") {
      p(`  --radius-full: 9999px;`);
    } else {
      p(`  --radius-${k.replace(/^r/, "")}: ${px2rem(v)};`);
    }
  }
  for (const [k, v] of Object.entries(typeScale)) p(`  --text-${k}: ${px2rem(v)};`);
  for (const [k, v] of Object.entries(weightScale)) p(`  --weight-${k}: ${v};`);
  for (const [k, v] of Object.entries(sizeScale)) {
    p(`  --size-${k.replace(/([A-Z])/g, "-$1").toLowerCase()}: ${px2rem(v)};`);
  }
  for (const [k, v] of Object.entries(elevationScale)) p(`  --elevation-${k}: ${v};`);
  for (const [k, v] of Object.entries(durationScale)) p(`  --duration-${k}: ${v}ms;`);
  for (const [k, v] of Object.entries(opacityScale)) p(`  --opacity-${k}: ${v};`);
  p("");
  p("  /* 语义间距 / 圆角别名 */");
  for (const [alias, target] of Object.entries(semSpace)) {
    p(`  --space-${alias.replace(/([A-Z])/g, "-$1").toLowerCase()}: var(--space-${target.replace(/^s/, "")});`);
  }
  for (const [alias, target] of Object.entries(semRadius)) {
    const t = target === "full" ? "9999px" : `var(--radius-${target.replace(/^r/, "")})`;
    p(`  --radius-${alias}: ${t};`);
  }
  p("");
  p("  /* 排版家族 */");
  p(`  --font-sans: ${doc.web.fontSans};`);
  p(`  --font-mono: ${doc.web.fontMono};`);
  p("");
  p("  /* 阴影 */");
  for (const [k, v] of Object.entries(doc.web.shadow as Json)) p(`  --shadow-${k}: ${v};`);
  p("");
  p("  /* 动效曲线 */");
  p("  --ease-standard: cubic-bezier(0.2, 0, 0, 1);");
  p("  --ease-decelerate: cubic-bezier(0, 0, 0.2, 1);");
  p("  --ease-accelerate: cubic-bezier(0.4, 0, 1, 1);");
  p("");
  L.push(...emitShadcnLayer(themeColors[DEFAULT_THEME.id]));
  p("");
  p("  /* ---- L2 语义令牌 (默认主题: " + DEFAULT_THEME.label + ") ---- */");
  L.push(...emitSemanticLayer(themeColors[DEFAULT_THEME.id]));
  p("}");
  p("");
  p("/* ---- 运行时换肤: <html data-theme=\"x\"> 覆盖品牌槽位 ---- */");
  for (const t of themeDefs) {
    if (t.isDefault) continue;
    p(`[data-theme="${t.id}"] { /* ${t.label} · ${t.group} */`);
    L.push(...emitShadcnLayer(themeColors[t.id]));
    p("");
    L.push(...emitSemanticLayer(themeColors[t.id]));
    p("}");
    p("");
  }
  p(END_MARK);

  return L.join("\n");
}

// ============================================
// 写盘 / 校验
// ============================================

function injectCss(existing: string, block: string): string {
  const b = existing.indexOf(BEGIN_MARK);
  const e = existing.indexOf(END_MARK);
  if (b === -1 || e === -1) {
    throw new Error(
      `src/styles/globals.css 缺少生成标记。请先手工加入:\n  ${BEGIN_MARK}\n  ...\n  ${END_MARK}`,
    );
  }
  if (e < b) throw new Error("src/styles/globals.css 生成标记顺序颠倒 (END 在 BEGIN 之前)");
  return existing.slice(0, b) + block + existing.slice(e + END_MARK.length);
}

function writeOrCheck(path: string, next: string, results: string[]): void {
  let prev = "";
  try {
    prev = readFileSync(path, "utf8");
  } catch {
    prev = "";
  }
  if (prev === next) {
    results.push(`  ✓ ${path.replace(ROOT + "/", "")}`);
    return;
  }
  if (MODE === "check") {
    results.push(`  ✗ ${path.replace(ROOT + "/", "")} —— 与 design-tokens.json 不一致`);
    return;
  }
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, next, "utf8");
  results.push(`  ✎ ${path.replace(ROOT + "/", "")} (${prev ? "已更新" : "已创建"})`);
}

if (MODE === "contrast") {
  console.log("\n暖客宝 主题对比度体检 (WCAG 2.1)\n");
  console.log("  目标: 正文 ≥ 4.5:1 (AA) · 理想 ≥ 7:1 (AAA)\n");
  for (const t of themeDefs) {
    const c = themeColors[t.id];
    console.log(`▸ ${t.label} (${t.id})${t.isDefault ? "  [默认]" : ""}`);
    const rows: Array<[string, string, string]> = [
      ["primary  底 vs onPrimary  字 (按钮)", c.primary, c.onPrimary],
      ["accent   底 vs onAccent   字 (强调)", c.accent, c.onAccent],
      ["surface  底 vs textPrimary  字 (正文)", c.surface, c.textPrimary],
      ["surface  底 vs textSecondary 字 (副文)", c.surface, c.textSecondary],
      ["surface  底 vs textTertiary  字 (提示)", c.surface, c.textTertiary],
      ["card     底 vs textPrimary  字", c.surfaceCard, c.textPrimary],
      ["card     底 vs border     线 (可见性)", c.surfaceCard, c.border],
      ["danger   底 vs onDanger   字", c.danger, c.onDanger],
      ["warning  底 vs onWarning  字", c.warning, c.onWarning],
      ["success  底 vs onSuccess  字", c.success, c.onSuccess],
      ["info     底 vs onInfo     字", c.info, c.onInfo],
    ];
    for (const [label, bg, fg] of rows) {
      const r = contrastRatio(bg, fg);
      const grade = r >= 7 ? "AAA" : r >= 4.5 ? "AA " : r >= 3 ? "AA-lg" : "✗ FAIL";
      console.log(`    ${label.padEnd(36)} ${r.toFixed(2).padStart(6)}:1  ${grade}`);
    }
    console.log("");
  }
  if (contrastWarnings.length) {
    console.log("提示:");
    for (const w of contrastWarnings) console.log("  " + w);
    console.log("");
  }
  process.exit(0);
}

const results: string[] = [];
writeOrCheck(OUT_FLUTTER, emitFlutter(), results);
writeOrCheck(OUT_TS, emitTs(), results);

const cssBlock = emitCssBlock();
let cssNext: string;
try {
  cssNext = injectCss(readFileSync(OUT_CSS, "utf8"), cssBlock);
} catch (err) {
  console.error(`\n✗ ${(err as Error).message}\n`);
  process.exit(1);
}
writeOrCheck(OUT_CSS, cssNext, results);

const drifted = results.some((r) => r.includes("✗ "));
console.log("\n设计令牌" + (MODE === "check" ? "一致性校验" : "生成") + ":");
console.log(results.join("\n"));

if (contrastWarnings.length) {
  console.log("\n对比度提示 (不阻断):");
  for (const w of contrastWarnings) console.log("  " + w);
}

if (MODE === "check" && drifted) {
  console.error(
    "\n✗ 生成产物与 design/tokens/design-tokens.json 不一致。\n  修法: pnpm tokens:build 然后一起提交。\n",
  );
  process.exit(1);
}

console.log(
  drifted
    ? "\n✗ 见上方不一致项\n"
    : `\n✓ ${themeDefs.length} 个主题 · ${Object.keys(palette).length} 个色板槽 · ${Object.keys(themeColors[DEFAULT_THEME.id]).length} 个语义色槽\n`,
);
