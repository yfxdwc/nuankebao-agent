"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useSwipe, Swipeable } from "@/hooks/use-swipe";
import { Bell, Check, X, MessageCircle } from "lucide-react";
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
 * API: PATCH /api/follow-ups/[id] { action: 'complete' | 'cancel' }
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

  const cardContent = (
    <Card className={cn("overflow-hidden", overdue && "border-rose-200")}>
      <CardContent className="p-3 md:p-4">
        <div className="flex items-start gap-3">
          <div
            className={cn(
              "h-9 w-9 md:h-10 md:w-10 rounded-full flex items-center justify-center shrink-0",
              overdue ? "bg-rose-100 text-rose-700" : "bg-amber-100 text-amber-700"
            )}
          >
            <Bell className="h-4 w-4 md:h-5 md:w-5" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center justify-between gap-2">
              {customerName ? (
                <Link
                  href={`/admin/customers/${task.customerId}`}
                  className="text-sm md:text-base font-medium hover:underline truncate"
                >
                  {customerName}
                </Link>
              ) : (
                <span className="text-sm md:text-base font-medium">
                  客户 {task.customerId}
                </span>
              )}
              <Badge
                variant={overdue ? "destructive" : "outline"}
                className="text-[10px] md:text-xs shrink-0"
              >
                {overdue ? "已逾期" : formatDate(task.dueAt)}
              </Badge>
            </div>
            <p className="text-xs md:text-sm text-muted-foreground mt-1 line-clamp-2">
              {task.reason}
            </p>
            {task.aiSuggestion && (
              <div className="mt-2 p-2 md:p-3 bg-primary/5 border border-primary/10 rounded-md text-[10px] md:text-xs text-foreground/80 whitespace-pre-wrap">
                <span className="font-medium text-primary">AI 建议: </span>
                {task.aiSuggestion}
              </div>
            )}
            {/* 桌面端: 显完整按钮组 (md+) */}
            <div className="mt-2 md:mt-3 hidden md:flex items-center justify-end">
              <CompleteFollowUpButton taskId={task.id} />
            </div>

            {/* 移动端: 提示滑动 */}
            {swipe.isOpen ? null : (
              <p className="text-[10px] text-muted-foreground mt-1.5 md:hidden">
                ← 左滑标记完成 · 右滑取消 →
              </p>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
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
          "md:hidden absolute inset-y-0 left-0 w-20 bg-amber-500 text-white",
          "flex flex-col items-center justify-center gap-1",
          "active:bg-amber-600 transition-colors",
          "rounded-l-lg"
        )}
        aria-label="取消跟进"
      >
        <X className="h-5 w-5" />
        <span className="text-[10px] font-medium">取消</span>
      </button>

      {/* 右 action: 标记完成 (背景, 右侧 absolute) */}
      <button
        type="button"
        onClick={() => quickAction("complete")}
        disabled={!!actionLoading}
        className={cn(
          "md:hidden absolute inset-y-0 right-0 w-20 bg-emerald-500 text-white",
          "flex flex-col items-center justify-center gap-1",
          "active:bg-emerald-600 transition-colors",
          "rounded-r-lg"
        )}
        aria-label="标记完成"
      >
        <Check className="h-5 w-5" />
        <span className="text-[10px] font-medium">完成</span>
      </button>

      {/* 可滑动主体 */}
      <Swipeable swipe={swipe} className="bg-background relative z-10">
        {cardContent}
      </Swipeable>

      {/* 打开态: 浮一个 "点这儿完成" 的视觉提示 (可选) */}
      {swipe.isOpen === "right" && actionLoading !== "complete" && (
        <div className="md:hidden absolute inset-y-0 right-0 w-20 pointer-events-none flex items-center justify-center">
          <div className="bg-emerald-500 text-white text-[10px] px-2 py-1 rounded animate-pulse">
            松开完成
          </div>
        </div>
      )}
    </div>
  );
}
