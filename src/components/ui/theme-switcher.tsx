"use client";

// ============================================
// 换肤控件 (Web admin)
// ============================================
//
// 用法:
//   <ThemeSwitcher />                  → 下拉选择 (放 sidebar / topbar)
//   <ThemeSwitcher variant="inline" /> → 内联色卡 (放设置页)
//
// 色值全部来自 src/lib/design-tokens.g.ts (由 design-tokens.json 生成),
// 所以往 design-tokens.json 加主题 → 这里零改动自动出现。

import { useEffect, useState } from "react";

import { cn } from "@/lib/utils";
import {
  applyTheme,
  getActiveTheme,
  subscribeTheme,
  themeList,
  themePreview,
  type ThemeId,
} from "@/lib/theme";

function useActiveTheme(): [ThemeId, (id: ThemeId) => void] {
  const [id, setId] = useState<ThemeId>(() => getActiveTheme());

  useEffect(() => {
    // 首屏脚本可能已经把属性打上了, 但 React state 初值是在 hydrate 时算的 —— 对齐一次
    setId(getActiveTheme());
    return subscribeTheme(setId);
  }, []);

  return [
    id,
    (next: ThemeId) => {
      applyTheme(next);
      setId(next);
    },
  ];
}

/** 三色小色卡 —— 让用户选之前就看到效果 */
function Swatch({ id, size = "md" }: { id: ThemeId; size?: "sm" | "md" }) {
  const p = themePreview(id);
  return (
    <span
      aria-hidden
      className={cn(
        "inline-flex shrink-0 overflow-hidden rounded-sm border border-border-default",
        size === "sm" ? "h-3.5 w-5" : "h-5 w-8",
      )}
    >
      <span className="flex-[5]" style={{ backgroundColor: p.primary }} />
      <span className="flex-[3]" style={{ backgroundColor: p.primaryLight }} />
      <span className="flex-[4]" style={{ backgroundColor: p.accent }} />
    </span>
  );
}

export function ThemeSwitcher({
  variant = "select",
  className,
}: {
  variant?: "select" | "inline";
  className?: string;
}) {
  const [active, setTheme] = useActiveTheme();

  if (variant === "inline") {
    const groups = themeList.reduce<Record<string, (typeof themeList)[number][]>>(
      (acc, t) => {
        (acc[t.group] ??= []).push(t);
        return acc;
      },
      {},
    );

    return (
      <div className={cn("space-y-section-y", className)}>
        {Object.entries(groups).map(([group, items]) => (
          <div key={group} className="space-y-2">
            <p className="text-caption font-medium text-content-tertiary">{group}</p>
            <div className="flex flex-wrap gap-2">
              {items.map((t) => {
                const on = t.id === active;
                return (
                  <button
                    key={t.id}
                    type="button"
                    onClick={() => setTheme(t.id)}
                    aria-pressed={on}
                    className={cn(
                      "inline-flex items-center gap-2 rounded-chip border px-3 py-2 text-body transition-colors",
                      on
                        ? "border-brand bg-brand-surface font-semibold text-brand-dark"
                        : "border-border-default text-content-primary hover:bg-surface-subtle",
                    )}
                  >
                    <Swatch id={t.id} />
                    {t.label}
                    {on && <span className="text-brand">✓</span>}
                  </button>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <label className={cn("inline-flex items-center gap-2", className)}>
      <Swatch id={active} size="sm" />
      <span className="sr-only">主题配色</span>
      <select
        value={active}
        onChange={(e) => setTheme(e.target.value as ThemeId)}
        className="h-9 cursor-pointer rounded-md border border-border-default bg-surface-card px-2 text-body text-content-primary"
      >
        {themeList.map((t) => (
          <option key={t.id} value={t.id}>
            {t.group} · {t.label}
          </option>
        ))}
      </select>
    </label>
  );
}
