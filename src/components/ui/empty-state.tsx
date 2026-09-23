// ============================================
// EmptyState — 空状态占位
// ============================================
//
// 设计要点 (docs/ui-principles.md):
//   - 图标用三级文字色, 不放彩色大图标 (反 vibe · 原则 5: 颜色是信号)
//   - 默认给一个「下一步动作」action prop —— 原则 8:
//     "没有出口的空状态 = 死路; 必须告诉用户下一步能做什么"
//   - 文案规则: 发生了什么 + 下一步能做什么
//   - size="sm": 紧凑, 用于卡片内/表格内; "md": 整页
//
// 用法:
//   <EmptyState
//     icon={Users}
//     title="还没有客户"
//     description="从销售现场录入第一位客户, 系统会帮你管起来"
//     action={<Button>新增客户</Button>}
//   />
// ============================================

import * as React from "react";
import { Inbox, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

export interface EmptyStateProps {
  /** 左侧图标 (B 档: 默认 Inbox, 三级文字色, 不要彩色大色块) */
  icon?: LucideIcon;
  /** 主标题: 发生了什么 */
  title: string;
  /** 副说明: 下一步能做什么 / 为什么是空的 */
  description?: React.ReactNode;
  /** 行动按钮 (原则 8: 必须给出口) */
  action?: React.ReactNode;
  /** sm: 表格内/卡片内紧凑版; md: 整页 (默认) */
  size?: "sm" | "md";
  className?: string;
}

// 纯展示组件, 不加 "use client"
const EmptyState = React.forwardRef<HTMLDivElement, EmptyStateProps>(
  (
    {
      icon: Icon = Inbox,
      title,
      description,
      action,
      size = "md",
      className,
    },
    ref,
  ) => {
    const isSm = size === "sm";

    return (
      <div
        ref={ref}
        // 容器越少越好 (原则 4): 不画边框不画阴影, 仅靠 py + 居中营造"独立块"
        className={cn(
          "flex flex-col items-center justify-center text-center",
          // sm 用 py-6 + 图标小, md 用 py-10 + 图标标准
          isSm ? "py-6 px-4" : "py-10 px-card-x",
          className,
        )}
      >
        {/* 图标: 三级文字色, 不画彩色背景 (反 vibe) */}
        <Icon
          aria-hidden
          className={cn(
            "text-content-tertiary",
            isSm ? "h-5 w-5 mb-2" : "h-6 w-6 mb-3",
          )}
        />

        {/* 标题: body-lg(15) / medium / 主文字色 (B 档不放大, 靠字重) */}
        <p
          className={cn(
            "font-medium text-content-primary",
            isSm ? "text-body" : "text-body-lg",
          )}
        >
          {title}
        </p>

        {/* 描述: body(13) / 次级文字色 / 最多 max-w 让长描述居中不撑满 */}
        {description && (
          <p
            className={cn(
              "mt-1 max-w-sm text-body text-content-secondary",
              isSm && "text-caption",
            )}
          >
            {description}
          </p>
        )}

        {/* 行动按钮: 给出口 (原则 8) */}
        {action && (
          <div className={cn("mt-section-y", isSm && "mt-3")}>{action}</div>
        )}
      </div>
    );
  },
);
EmptyState.displayName = "EmptyState";

export { EmptyState };