// ============================================
// 运行时换肤 (Web) —— 令牌系统的浏览器端
// ============================================
//
// 机制:
//   1. 主题色全部走 CSS 变量 (由 design-tokens.json 生成到 globals.css)
//   2. 换肤 = 给 <html> 换 `data-theme` 属性 → 命中 globals.css 里对应的覆盖块
//   3. 持久化 = localStorage; 首屏用 layout.tsx 里的内联脚本在**绘制前**打上属性 (防闪白)
//
// 为什么不用 CSS-in-JS / context 传色值:
//   服务端渲染时没有"用户选的主题"这回事 —— 只能在客户端补。而 CSS 变量方案让
//   所有 Tailwind 类 (bg-primary / text-content-secondary …) 零改动跟着变,
//   也不需要把颜色从 React 树里穿下去。
//
// ⚠ 主题 id 的**真源**是 design/tokens/design-tokens.json 的 themes 数组,
//   这里只做「读写 + 应用」, 不定义任何主题名/色值。

import {
  defaultThemeId,
  isThemeId,
  themeColors,
  themeList,
  type ThemeId,
} from "./design-tokens.g";

export const THEME_STORAGE_KEY = "nuankebao.theme";
export const THEME_ATTR = "data-theme";

export type { ThemeId };
export { themeList, defaultThemeId };

/** 服务端渲染时拿不到 localStorage → 一律返回默认主题 (避免 hydration 不一致) */
export function readStoredTheme(): ThemeId {
  if (typeof window === "undefined") return defaultThemeId;
  try {
    const raw = window.localStorage.getItem(THEME_STORAGE_KEY);
    return isThemeId(raw) ? raw : defaultThemeId;
  } catch {
    // 隐私模式 / 禁用 storage —— 不抛错, 退回默认
    return defaultThemeId;
  }
}

/** 当前实际生效的主题 (以 DOM 属性为准, 因为首屏脚本比 React 先跑) */
export function getActiveTheme(): ThemeId {
  if (typeof document === "undefined") return defaultThemeId;
  const raw = document.documentElement.getAttribute(THEME_ATTR);
  return isThemeId(raw) ? raw : readStoredTheme();
}

const themeSubscribers = new Set<(id: ThemeId) => void>();

function notify(id: ThemeId) {
  for (const fn of themeSubscribers) fn(id);
}

/** 订阅主题变化 (含跨标签页) —— 给 useTheme 用 */
export function subscribeTheme(fn: (id: ThemeId) => void): () => void {
  themeSubscribers.add(fn);
  const onStorage = (e: StorageEvent) => {
    if (e.key === THEME_STORAGE_KEY && isThemeId(e.newValue)) {
      applyTheme(e.newValue, { persist: false });
    }
  };
  window.addEventListener("storage", onStorage);
  return () => {
    themeSubscribers.delete(fn);
    window.removeEventListener("storage", onStorage);
  };
}

/**
 * 应用主题。
 * @param persist 写不写 localStorage (跨标签页同步 / 首屏恢复时用 false)
 */
export function applyTheme(id: ThemeId, opts: { persist?: boolean } = {}): void {
  if (typeof document === "undefined") return;
  const { persist = true } = opts;
  const next = isThemeId(id) ? id : defaultThemeId;

  if (next === defaultThemeId) {
    // 默认主题就是 :root 那套, 去掉属性即可 (少一层覆盖, 也方便调试)
    document.documentElement.removeAttribute(THEME_ATTR);
  } else {
    document.documentElement.setAttribute(THEME_ATTR, next);
  }

  // 移动端浏览器地址栏 / 状态栏配色跟着换
  const meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
  if (meta) meta.content = themeColors[next].primary;

  if (persist) {
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, next);
    } catch {
      // storage 不可用: 主题本次会话内仍然生效, 只是不记住
    }
  }

  notify(next);
}

/**
 * 首屏防闪脚本 —— 必须**内联**在 <head> 且早于 body 绘制。
 * 逻辑故意不依赖任何模块 (冷启动时 JS chunk 还没到), 所以这里是纯字面量拼接。
 */
export const themeBootScript = `
(function(){try{
  var k=${JSON.stringify(THEME_STORAGE_KEY)};
  var d=${JSON.stringify(defaultThemeId)};
  var v=localStorage.getItem(k);
  var ids=${JSON.stringify(themeList.map((t) => t.id))};
  if(v&&ids.indexOf(v)>-1&&v!==d){document.documentElement.setAttribute(${JSON.stringify(THEME_ATTR)},v);}
  var m=document.querySelector('meta[name="theme-color"]');
  if(m&&v&&v!==d){var c=${JSON.stringify(
    Object.fromEntries(themeList.map((t) => [t.id, themeColors[t.id].primary])),
  )};if(c[v]){m.setAttribute('content',c[v]);}}
}catch(e){}})();
`.trim();

/** 主题色预览 (设置 UI 用) —— 直接取生成的真色值, 不写死 */
export function themePreview(id: ThemeId) {
  const c = themeColors[id];
  return {
    primary: c.primary,
    primaryLight: c.primaryLight,
    accent: c.accent,
    primarySurface: c.primarySurface,
  };
}
