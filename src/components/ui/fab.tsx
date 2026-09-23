"use client";

import Link from "next/link";
import { Plus } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * 暖客宝 浮动操作按钮 (Floating Action Button)
 *
 * 移动端: 浮在右下角 (避底部 Tab Bar), 大触摸区, 主色绿
 * 桌面端: 隐藏 (用页面里的按钮)
 *
 * 设计原则 (AGENTS.md §1):
 *   - 拇指可达 (右下)
 *   - ≥56px 触摸目标 (Material Design 规范)
 *   - safe-area-inset-bottom 兼容刘海手机
 *   - 阴影: shadow-lg + 主色背景
 */
interface FabProps {
  href?: string;
  onClick?: () => void;
  label?: string;          // a11y + 长按提示
  icon?: React.ReactNode;
  variant?: "primary" | "rose";  // 主色 / 玫色 (养生用)
  className?: string;
}

export function Fab({
  href,
  onClick,
  label = "新增",
  icon = <Plus className="h-6 w-6" />,
  variant = "primary",
  className,
}: FabProps) {
  const variantClass =
    variant === "primary"
      ? "bg-primary text-primary-foreground shadow-primary/30"
      : "bg-danger text-white shadow-danger/30";

  const content = (
    <>
      <span className="sr-only">{label}</span>
      {icon}
    </>
  );

  const baseClass = cn(
    "md:hidden",
    "fixed right-4 z-30",
    "bottom-[calc(4rem+env(safe-area-inset-bottom)+0.5rem)]",  // 4rem = Tab Bar 高度
    "h-14 w-14 rounded-full",
    "flex items-center justify-center",
    "shadow-lg active:scale-95 transition-transform",
    "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
    variantClass,
    className
  );

  if (href) {
    return (
      <Link href={href} className={baseClass} aria-label={label}>
        {content}
      </Link>
    );
  }

  return (
    <button
      type="button"
      onClick={onClick}
      className={baseClass}
      aria-label={label}
    >
      {content}
    </button>
  );
}
