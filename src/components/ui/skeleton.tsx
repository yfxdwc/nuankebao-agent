// ============================================
// Skeleton / SkeletonList — 加载占位
// ============================================
//
// 设计要点 (docs/ui-principles.md):
//   - 默认**无动画** (原则 7 + 反炫技):
//     养生系统的用户群体不靠呼吸效果感知"在加载";
//     且动画会让暗色模式/低性能设备显得吃力。
//     若有项目内特定场景认为需要 pulse, 改用 .animate-pulse 一行 className 即可;
//     在那之前, 默认静默更尊重用户注意力。
//   - 行高与真实列表一致 (避免加载完成跳动, 这是 skeleton 的核心价值)
//   - 用 surface-sunken (中性底色), 不放 brand-surface (品牌色是状态信号, 不是装饰)
//
// 用法:
//   <Skeleton className="h-4 w-32" />                 // 任意形状
//   <SkeletonList rows={6} />                        // 模拟列表行
//   <SkeletonList rows={4} showLeading showSubtitle /> // 带头像 + 副标题的列表
// ============================================

import * as React from "react";
import { cn } from "@/lib/utils";

// ---- Skeleton: 单个占位块 ----
//
// ⚠ 默认无动画 (animate-pulse 默认不开启):
//   - 任务硬约束 §2.7: "无动画 (原则 7 + 反炫技)"
//   - 若项目内某处确实需要 pulse 效果, 在调用方加 "animate-pulse" className 即可;
//     **不要**在这里默认开 —— 让"反炫技"成为基线
const Skeleton = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  ({ className, ...props }, ref) => (
    <div
      ref={ref}
      aria-hidden
      // rounded-md(6) —— 与 button/input 同档, 给骨架一种"中性控件"质感
      // 不写 w/h —— 完全靠调用方传 className 控制形状
      className={cn("bg-surface-sunken rounded-md", className)}
      {...props}
    />
  ),
);
Skeleton.displayName = "Skeleton";

// ---- SkeletonList: 模拟列表行 ----

export interface SkeletonListProps {
  /** 行数 (默认 5) */
  rows?: number;
  /** 是否显示左侧头像方块 (32×32) */
  showLeading?: boolean;
  /** 是否在主文字下方加一行更窄的副文字骨架 */
  showSubtitle?: boolean;
  /** 行间距 —— 默认 12px, 与真实 list row padding (14) 接近以减少跳动 */
  rowGap?: number;
  className?: string;
}

const SkeletonList = React.forwardRef<HTMLDivElement, SkeletonListProps>(
  (
    {
      rows = 5,
      showLeading = false,
      showSubtitle = false,
      rowGap = 12,
      className,
    },
    ref,
  ) => (
    <div
      ref={ref}
      role="status"
      aria-label="加载中"
      // divide-y 与真实列表保持视觉一致; 减少加载完成时的跳动
      className={cn("divide-y divide-divider", className)}
      style={{ rowGap }}
    >
      {Array.from({ length: rows }).map((_, i) => (
        // 行高与真实 list row padding 一致 (避免跳动)
        <div
          key={i}
          className="flex items-center gap-inline px-3 py-3"
          // 行间距: 实际项目里通常外层用 space-y, 这里也允许 inline gap
        >
          {showLeading && <Skeleton className="h-8 w-8 rounded-full shrink-0" />}
          <div className="min-w-0 flex-1 space-y-2">
            {/* 主文字骨架: 占 60% 宽, 模仿「客户姓名」最长截断 */}
            <Skeleton className="h-3.5 w-3/5" />
            {showSubtitle && <Skeleton className="h-3 w-2/5" />}
          </div>
          {/* 右侧元数据骨架 (e.g. 时间戳) —— 比主文字窄 */}
          <Skeleton className="h-3 w-12 shrink-0" />
        </div>
      ))}
    </div>
  ),
);
SkeletonList.displayName = "SkeletonList";

export { Skeleton, SkeletonList };