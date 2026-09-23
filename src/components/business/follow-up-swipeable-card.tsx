"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Bell, Check, X } from "lucide-react";
import { formatDate } from "@/lib/utils";
import { cn } from "@/lib/utils";
import { CompleteFollowUpButton } from "./complete-follow-up-button";

/**
 * 暖客宝 跟进任务卡片 (W17, swipe enabled)
 *
 * 移动端交互:
 *   - 默认态: 正常显示卡片
 *   - 左滑: 露出右 action 区 (✓ 标记完成)
 *   - 右滑: 露出左 action 区 (✗ 取消跟进)
 *   - 阈值 40% 宽度
 *   - 桌面端 (md+): 正常显示 + 内嵌 CompleteFollowUpButton (无 swipe)
 *
 * B3 重构: 去掉外层 Card 包裹, 改为内层单一容器 (避免一屏两重卡片墙).
 */

interface FollowUpTask {
  id: string;
  customerId: string;
  reason: string;
  aiSuggestion: string | null;
  dueAt: string;
  status: string;
  createdAt: string;
}

interface Props {
  task: FollowUpTask;
  customerName: string | null;
  overdue: boolean;
  isDesktop?: boolean;
}

import { useSwipe, Swipeable } from "@/hooks/use-swipe";

export function FollowUpSwipeableCard({ task, customerName, overdue, isDesktop }: Props) {
  const router = useRouter();
  const [actionLoading, setActionLoading] = useState<null | "complete" | "cancel">(null);
  const swipe = useSwipe({
    threshold: 0.4,
    rightWidth: 80,  // 左滑露 "完成"
    leftWidth: 80,   // 右滑露 "取消"
    disabled: !!isDesktop,
  });

  async function quickAction(action: "complete" | "cancel") {
    if (actionLoading) return;
    setActionLoading(action);
    try {
      await fetch(`/api/follow-ups/${task.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action }),
      });
      swipe.close();
      router.refresh();
    } finally {
      setActionLoading(null);
    }
  }

  // B3: 单一容器 (无 Card 包裹); left/right 边距留给父级 (过滤 chip 区/列表区)
  const cardContent = (
    <div
      className={cn(
        "px-3 py-3",
        overdue && "bg-danger-surface/30"
      )}
    >
      <div className="flex items-start gap-3">
        <div
          className={cn(
            "h-9 w-9 rounded-full flex items-center justify-center shrink-0",
            overdue ? "bg-danger-light text-danger" : "bg-warning-surface text-warning"
          )}
        >
          <Bell className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between gap-2">
            {customerName ? (
              <Link
                href={`/admin/customers/${task.customerId}`}
                className="text-body-lg font-medium text-content-primary hover:underline truncate"
              >
                {customerName}
              </Link>
            ) : (
              <span className="text-body-lg font-medium text-content-primary">
                客户 {task.customerId}
              </span>
            )}
            <Badge
              variant={overdue ? "destructive" : "outline"}
              className="text-caption shrink-0"
            >
              {overdue ? "已逾期" : formatDate(task.dueAt)}
            </Badge>
          </div>
          <p className="text-body text-content-secondary mt-1 line-clamp-2">
            {task.reason}
          </p>
          {task.aiSuggestion && (
            <div className="mt-2 p-2.5 bg-brand-surface border border-brand-light rounded-md text-caption text-content-primary whitespace-pre-wrap">
              <span className="font-medium text-brand">AI 建议: </span>
              {task.aiSuggestion}
            </div>
          )}
          {/* 桌面端: 显完整按钮组 (md+) */}
          <div className="mt-2 hidden md:flex items-center justify-end">
            <CompleteFollowUpButton taskId={task.id} />
          </div>

          {/* 移动端: 提示滑动 */}
          {swipe.isOpen ? null : (
            <p className="text-caption text-content-tertiary mt-1.5 md:hidden">
              ← 左滑标记完成 · 右滑取消 →
            </p>
          )}
        </div>
      </div>
    </div>
  );

  // 桌面: 直接渲染, 不包 swipe
  if (isDesktop) {
    return <div className="space-y-2">{cardContent}</div>;
  }

  return (
    <div className="relative md:static">
      {/* 背景 action 按钮 (左滑 = 露出右, 右滑 = 露出左) */}
      {/* 左 action: 取消 (背景, 左侧 absolute) */}
      <button
        type="button"
        onClick={() => quickAction("cancel")}
        disabled={!!actionLoading}
        className={cn(
          "md:hidden absolute inset-y-0 left-0 w-20 bg-warning text-white",
          "flex flex-col items-center justify-center gap-1",
          "active:bg-warning transition-colors",
          "rounded-l-lg"
        )}
        aria-label="取消跟进"
      >
        <X className="h-5 w-5" />
        <span className="text-caption font-medium">取消</span>
      </button>

      {/* 右 action: 标记完成 (背景, 右侧 absolute) */}
      <button
        type="button"
        onClick={() => quickAction("complete")}
        disabled={!!actionLoading}
        className={cn(
          "md:hidden absolute inset-y-0 right-0 w-20 bg-success text-white",
          "flex flex-col items-center justify-center gap-1",
          "active:bg-success transition-colors",
          "rounded-r-lg"
        )}
        aria-label="标记完成"
      >
        <Check className="h-5 w-5" />
        <span className="text-caption font-medium">完成</span>
      </button>

      {/* 可滑动主体 */}
      <Swipeable swipe={swipe} className="bg-background relative z-10">
        {cardContent}
      </Swipeable>

      {/* 打开态: 浮一个 "点这儿完成" 的视觉提示 (可选) */}
      {swipe.isOpen === "right" && actionLoading !== "complete" && (
        <div className="md:hidden absolute inset-y-0 right-0 w-20 pointer-events-none flex items-center justify-center">
          <div className="bg-success text-white text-caption px-2 py-1 rounded animate-pulse">
            松开完成
          </div>
        </div>
      )}
    </div>
  );
}