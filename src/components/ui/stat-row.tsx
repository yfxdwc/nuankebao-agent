// ============================================
// StatRow / StatGroup — 关键信息行
// ============================================
//
// 设计要点 (docs/ui-principles.md):
//   - 替代「一堆小卡片展示统计数字」(反 vibe, 原则 4: 容器越少越好)
//   - 左 label 次级文字色 / 右 value 主文字色 + 等宽数字 —— 数字一眼可扫
//   - 用 divide-y 同质分行; **不画卡片** (StatGroup 不包外层卡片)
//   - tone 只改 value 颜色, label 不变 —— 颜色是状态信号, 不是装饰 (原则 5)
//   - 详情页「关键信息」区: 一组 StatRow 直接放在 Section 下, 不要再包 Card
//
// 用法:
//   <StatGroup title="客户概览">
//     <StatRow label="我的客户" value="42" />
//     <StatRow label="本月新增" value="5" tone="success" hint="+12% MoM" />
//     <StatRow label="待跟进" value="3" tone="warning" onClick={...} />
//   </StatGroup>
// ============================================

import * as React from "react";
import { cn } from "@/lib/utils";

// ---- StatRow: 单行 label/value ----
//
// 因 onClick 是 React DOM 事件, 必须在 client component 注册 → 本组件加 "use client"
// (任务硬约束 §1: 纯展示不加, 有交互加; onClick 就是交互)
//
// 视觉上若不需要点击, onClick 不传即可 —— 仍然走 client 是为了 Props 一致

export type StatTone = "default" | "success" | "warning" | "danger" | "brand";

export interface StatRowProps {
  label: React.ReactNode;
  value: React.ReactNode;
  /** 右侧 value 下方的辅助文字 (e.g. 同比/趋势) */
  hint?: React.ReactNode;
  /** value 颜色: 状态信号, 只在确有状态时用 (原则 5) */
  tone?: StatTone;
  /** 行可点击 (整行 hover 反馈 + cursor-pointer) */
  onClick?: () => void;
  className?: string;
}

const toneClass: Record<StatTone, string> = {
  default: "text-content-primary",
  success: "text-success",
  warning: "text-warning",
  danger: "text-danger",
  brand: "text-brand",
};

const StatRow = React.forwardRef<HTMLDivElement, StatRowProps>(
  (
    { label, value, hint, tone = "default", onClick, className },
    ref,
  ) => {
    const interactive = typeof onClick === "function";

    return (
      <div
        ref={ref}
        // min-h-10(40) 行高, py-2 + 横排 —— B 档紧凑
        // 可点击时: cursor + hover 反馈 + active 轻反馈
        className={cn(
          "flex min-h-10 items-center justify-between gap-inline px-1 py-2",
          interactive &&
            "cursor-pointer rounded-md transition-colors hover:bg-surface-subtle active:bg-surface-sunken",
          className,
        )}
        onClick={onClick}
        role={interactive ? "button" : undefined}
        tabIndex={interactive ? 0 : undefined}
        onKeyDown={
          interactive
            ? (e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  onClick?.();
                }
              }
            : undefined
        }
      >
        {/* 左: label (次级文字色, 不放大, 不加粗 —— 视觉重量让给右 value) */}
        <span className="text-body text-content-secondary">{label}</span>

        {/* 右: value + hint 垂直堆叠 */}
        <div className="flex flex-col items-end leading-tight">
          <span
            className={cn(
              "text-body-lg font-medium tabular-nums",
              toneClass[tone],
            )}
          >
            {value}
          </span>
          {hint && (
            <span className="text-caption text-content-tertiary">{hint}</span>
          )}
        </div>
      </div>
    );
  },
);
StatRow.displayName = "StatRow";

// ---- StatGroup: 多行同质分组, 用分隔线代替卡片 ----

export interface StatGroupProps {
  title?: React.ReactNode;
  description?: React.ReactNode;
  children: React.ReactNode;
  /** 默认 true: 用 divide-y 分隔线; false 时调用方自己管理间距 */
  divided?: boolean;
  className?: string;
}

const StatGroup = React.forwardRef<HTMLDivElement, StatGroupProps>(
  (
    { title, description, children, divided = true, className },
    ref,
  ) => (
    <div ref={ref} className={cn("space-y-section-y", className)}>
      {(title || description) && (
        <div className="space-y-tight">
          {title && (
            <h3 className="text-title-sm font-semibold text-content-primary">
              {title}
            </h3>
          )}
          {description && (
            <p className="text-body text-content-secondary">{description}</p>
          )}
        </div>
      )}

      {/* 关键: 不画外层卡片/边框/阴影, 只用分隔线把行分开 (原则 4) */}
      <div className={cn(divided ? "divide-y divide-divider" : "space-y-1")}>
        {children}
      </div>
    </div>
  ),
);
StatGroup.displayName = "StatGroup";

export { StatRow, StatGroup };