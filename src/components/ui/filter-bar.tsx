// ============================================
// FilterBar / FilterChip — Web admin 表格页头部标准件
// ============================================
//
// 设计要点 (docs/ui-principles.md):
//   - 一行筛选区 + 下方 border-b 分隔 —— "bordered 模式" 与 Section 同语义
//   - FilterChip 是胶囊 (rounded-chip 全圆, 不是 rounded-md 半吊子)
//   - active = 主色实底; inactive = 中性浅底 + hover 更深
//     **不要描边** (描边 chip 是最典型的 SaaS 观感, 反 vibe)
//   - count 用 tabular-nums + opacity-70, 等宽对齐一眼可扫 (原则 1)
//
// 用法:
//   <FilterBar actions={<Button>导出</Button>}>
//     <FilterChip active>全部 (42)</FilterChip>
//     <FilterChip>新客户 (5)</FilterChip>
//     <FilterChip>活跃 (28)</FilterChip>
//   </FilterBar>
// ============================================

import * as React from "react";
import { cn } from "@/lib/utils";

// ============================================
// FilterChip — 客户端 (含 onClick 交互)
// ============================================

export interface FilterChipProps {
  active?: boolean;
  onClick?: () => void;
  children: React.ReactNode;
  /** 可选计数 (e.g. 全部 (42)); 等宽对齐, opacity-70 弱化视觉重量 */
  count?: number;
  /** 视觉/语义禁用 (灰色不可点) */
  disabled?: boolean;
  className?: string;
}

const FilterChip = React.forwardRef<HTMLButtonElement, FilterChipProps>(
  (
    { active = false, onClick, children, count, disabled, className },
    ref,
  ) => (
    <button
      ref={ref}
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={active}
      // h-7(28) 紧凑; text-caption(12); 全圆 pill
      // active = 主色实底 + 反白文字; inactive = 中性浅底 + hover 更深
      // **关键**: 不要加 border-* (描边 = SaaS 观感, 反 vibe)
      className={cn(
        "inline-flex items-center gap-1.5 rounded-chip h-7 px-3 text-caption font-medium",
        "transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
        "disabled:cursor-not-allowed disabled:opacity-50",
        active
          ? "bg-brand text-brand-foreground"
          : "bg-surface-subtle text-content-secondary hover:bg-surface-sunken",
        className,
      )}
    >
      <span>{children}</span>
      {/* count 用 tabular-nums + opacity-70 —— 等宽 + 弱化视觉重量 (原则 1) */}
      {typeof count === "number" && (
        <span
          className={cn(
            "tabular-nums opacity-70",
            active && "text-brand-foreground",
          )}
        >
          ({count})
        </span>
      )}
    </button>
  ),
);
FilterChip.displayName = "FilterChip";

// ============================================
// FilterBar — 纯展示容器, 可被 server 组件直接渲染
// ============================================
//
//   下方 border-b + pb-3 —— "bordered" 模式 (同 Section.bordered 语义)
//   没有 "use client" (FilterBar 自己无交互; FilterChip 子组件是 client)
// ============================================

export interface FilterBarProps {
  children: React.ReactNode;
  /** 右对齐动作: 导出按钮 / 列设置 / 视图切换等 */
  actions?: React.ReactNode;
  className?: string;
}

const FilterBar = React.forwardRef<HTMLDivElement, FilterBarProps>(
  ({ children, actions, className }, ref) => (
    <div
      ref={ref}
      // 行内: flex-wrap + gap-2(8) 让筛选 chip 自适应换行
      // 跨页: border-b + pb-3 —— "bordered 模式" (同 Section.bordered)
      className={cn(
        "flex flex-wrap items-center gap-2 border-b border-divider pb-3",
        className,
      )}
    >
      {/* 主体区: 自动占满, 移动端也撑开 */}
      <div className="flex flex-1 flex-wrap items-center gap-2">{children}</div>

      {/* 动作区: 桌面端右对齐, 移动端换行 */}
      {actions && (
        <div className="flex items-center gap-2 md:ml-auto">{actions}</div>
      )}
    </div>
  ),
);
FilterBar.displayName = "FilterBar";

export { FilterBar, FilterChip };