"use client";

// ============================================
// 取当前主题的真色值 (给「不认 CSS 变量」的库用)
// ============================================
//
// 为什么需要:
//   Tailwind 类名走 CSS 变量 → 换肤自动生效。
//   但 recharts / mermaid / canvas 这些库要的是**字符串色值**, 它们不认 var(--x),
//   于是过去 chart 色被写死成一个和品牌不一致的绿色 —— 卡在令牌系统之外, 换肤也不会变。
//
// 做法: 在客户端从 documentElement 的 computedStyle 读 CSS 变量,
//   并订阅主题变化重读。首屏 (SSR) 用生成器产出的默认主题色兜底。
//
// 边界: 只给「必须拿色值字符串」的场景用。能用 className 的地方一律用 className。

import { useEffect, useState } from "react";

import { defaultThemeId, themeColors, type ThemeId } from "./design-tokens.g";
import { getActiveTheme, subscribeTheme } from "./theme";

/** 图表/画布需要的语义色 —— 变量名 → CSS 自定义属性 */
const CHART_VARS = {
  series1: "--chart-1",
  series2: "--chart-2",
  series3: "--chart-3",
  series4: "--chart-4",
  series5: "--chart-5",
  series6: "--chart-6",
  grid: "--divider",
  axis: "--text-tertiary",
  surface: "--surface-card",
  border: "--border-default",
  primary: "--primary",
  danger: "--danger",
  success: "--success",
  info: "--info",
  muted: "--text-tertiary",
} as const;

export type ChartColors = Record<keyof typeof CHART_VARS, string>;

/** 生成器产出的默认主题色 —— SSR 兜底 (避免首屏图表闪成透明) */
function fallbackColors(): ChartColors {
  const c = themeColors[defaultThemeId];
  return {
    series1: c.primary,
    series2: c.primaryLight,
    series3: c.accent,
    series4: c.info,
    series5: c.graphFranchiseeB,
    series6: c.textTertiary,
    grid: c.divider,
    axis: c.textTertiary,
    surface: c.surfaceCard,
    border: c.border,
    primary: c.primary,
    danger: c.danger,
    success: c.success,
    info: c.info,
    muted: c.textTertiary,
  };
}

function readColors(): ChartColors {
  if (typeof document === "undefined") return fallbackColors();
  const cs = getComputedStyle(document.documentElement);
  const out = {} as ChartColors;
  for (const [key, varName] of Object.entries(CHART_VARS)) {
    const v = cs.getPropertyValue(varName).trim();
    out[key as keyof ChartColors] = v || fallbackColors()[key as keyof ChartColors];
  }
  return out;
}

/** 当前主题的图表色板 —— 换肤后自动更新 */
export function useChartColors(): ChartColors {
  // 初值: SSR 与首帧用默认主题 (hydration 一致); mount 后再读真实值
  const [colors, setColors] = useState<ChartColors>(fallbackColors);

  useEffect(() => {
    setColors(readColors());
    return subscribeTheme(() => {
      // CSS 变量已被 applyTheme 换过 —— 但要等浏览器完成样式重算
      requestAnimationFrame(() => setColors(readColors()));
    });
  }, []);

  return colors;
}

/** 当前主题 id (给需要按主题分支的极端场景) */
export function useThemeId(): ThemeId {
  const [id, setId] = useState<ThemeId>(defaultThemeId);
  useEffect(() => {
    setId(getActiveTheme());
    return subscribeTheme(setId);
  }, []);
  return id;
}
