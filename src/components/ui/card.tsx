import * as React from "react";
import { cn } from "@/lib/utils";

// ============================================
// Card — B 档 (紧凑专业) 重写
// ============================================
// 设计原则 (docs/ui-principles.md §1.4): 容器越少内容越强。
//
// 旧版本: 每个 Card = 边框 + 阴影 + p-6 (24px) + text-2xl 标题
//   → 满屏方块, 屏幕被"墙"切碎
//
// 新版本三档:
//   - <Card> (默认)         纯背景 + 圆角 + p-4    ── 软分组, 不画线
//   - <Card variant="outlined">  + 1px border      ── 需要"独立实体"感 (客户卡、统计块)
//   - <Card variant="elevated">  + 微阴影          ── 极少数 (浮层下面的卡)
//
// 「列表行」场景: 不要用 Card ── 用 divide-y 分隔线 (下面有 <ListRow> 演示)
// 「统计数字」: 用 variant="outlined" 让数字"独立出来"
// 「弹层里的内容块」: 用 variant="elevated"
// ============================================

type CardVariant = "default" | "outlined" | "elevated";
type CardSize = "default" | "sm" | "lg";

const cardVariants: Record<CardVariant, string> = {
  default: "rounded-lg bg-card text-card-foreground",
  outlined: "rounded-lg border border-border-default bg-card text-card-foreground",
  elevated: "rounded-lg bg-card text-card-foreground shadow-sm",
};
const cardSizes: Record<CardSize, string> = {
  default: "p-card-y",
  sm: "p-3",
  lg: "p-6",
};

const Card = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement> & {
    variant?: CardVariant;
    size?: CardSize;
  }
>(({ className, variant = "default", size = "default", ...props }, ref) => (
  <div
    ref={ref}
    className={cn(cardVariants[variant], cardSizes[size], className)}
    {...props}
  />
));
Card.displayName = "Card";

const CardHeader = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement> & { compact?: boolean }
>(({ className, compact = false, ...props }, ref) => (
  <div
    ref={ref}
    className={cn("flex flex-col gap-1 px-4 pb-2", compact ? "pt-3" : "pt-4", className)}
    {...props}
  />
));
CardHeader.displayName = "CardHeader";

const CardTitle = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  // B 档: 标题用 title-sm (17) + semibold, 而不是 2xl (24)。层级靠对比不靠放大
  <div
    ref={ref}
    className={cn("text-title-sm font-semibold leading-tight tracking-tight", className)}
    {...props}
  />
));
CardTitle.displayName = "CardTitle";

const CardDescription = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn("text-body text-content-tertiary", className)} {...props} />
));
CardDescription.displayName = "CardDescription";

const CardContent = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn("px-4 pb-4", className)} {...props} />
));
CardContent.displayName = "CardContent";

const CardFooter = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn("flex items-center px-4 pb-3", className)}
    {...props}
  />
));
CardFooter.displayName = "CardFooter";

// ============================================
// ListRow — 列表行 (替代"列表项包 Card"的反模式)
// ============================================
// 用法:
//   <ul className="divide-y divide-divider">
//     {items.map(it => <ListRow key={it.id}>{...}</ListRow>)}
//   </ul>
const ListRow = React.forwardRef<
  HTMLLIElement,
  React.LiHTMLAttributes<HTMLLIElement>
>(({ className, ...props }, ref) => (
  <li
    ref={ref}
    className={cn("p-3 transition-colors hover:bg-surface-subtle", className)}
    {...props}
  />
));
ListRow.displayName = "ListRow";

export {
  Card,
  CardHeader,
  CardFooter,
  CardTitle,
  CardDescription,
  CardContent,
  ListRow,
};
