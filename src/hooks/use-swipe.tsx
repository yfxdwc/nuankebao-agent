"use client";

import { useRef, useState, useCallback, useEffect } from "react";
import { cn } from "@/lib/utils";

/**
 * 暖客宝 移动端水平滑动 hook (W17)
 *
 * 行为 (参考 iOS Mail / Telegram):
 *   - 左滑: 显示右侧 action (例: 标记完成 / 删除)
 *   - 右滑: 显示左侧 action (例: 标记紧急)
 *   - 滑动超过阈值 (40% 宽) → 弹到"打开"态
 *   - 没超阈值 → 弹回
 *   - 上下滑 → 不触发 (避免误触滚动)
 *
 * 参数:
 *   - threshold: 0-1, 触发"打开"的比例 (默认 0.4 = 40%)
 *   - leftWidth / rightWidth: 左右 action 露出宽度 (px)
 *
 * 返回:
 *   - ref: 绑到要滑的元素
 *   - translateX: 当前 X 偏移 (受控, 用于背景按钮)
 *   - isOpen: 是否处于"打开"态
 *   - close: 强制关闭
 *   - handlers: { onTouchStart, onTouchMove, onTouchEnd }
 */
interface Options {
  threshold?: number;
  leftWidth?: number;   // 右滑露出的左 action 宽
  rightWidth?: number;  // 左滑露出的右 action 宽
  disabled?: boolean;
}

export function useSwipe({
  threshold = 0.4,
  leftWidth = 80,
  rightWidth = 80,
  disabled = false,
}: Options = {}) {
  const ref = useRef<HTMLDivElement | null>(null);
  const startX = useRef(0);
  const startY = useRef(0);
  const widthRef = useRef(0);
  const isHorizontal = useRef<boolean | null>(null);
  const [translateX, setTranslateX] = useState(0);
  const [isOpen, setIsOpen] = useState<"left" | "right" | null>(null);

  const maxLeft = leftWidth;     // 最大可右滑 (露出 left action)
  const maxRight = rightWidth;   // 最大可左滑 (露出 right action)

  function getX() {
    return translateX;
  }

  const onTouchStart = useCallback(
    (e: React.TouchEvent) => {
      if (disabled) return;
      const t = e.touches[0];
      startX.current = t.clientX;
      startY.current = t.clientY;
      widthRef.current = ref.current?.offsetWidth ?? 0;
      isHorizontal.current = null;  // 重置
    },
    [disabled]
  );

  const onTouchMove = useCallback(
    (e: React.TouchEvent) => {
      if (disabled) return;
      const t = e.touches[0];
      const dx = t.clientX - startX.current;
      const dy = t.clientY - startY.current;

      // 首帧决定方向 (避免上下滚动被误判)
      if (isHorizontal.current === null) {
        if (Math.abs(dx) > 5 || Math.abs(dy) > 5) {
          isHorizontal.current = Math.abs(dx) > Math.abs(dy);
        }
        return;
      }

      if (!isHorizontal.current) return;  // 上下滚, 不处理

      // 限制范围
      let x = dx;
      if (x > maxLeft) x = maxLeft + (x - maxLeft) * 0.3;  // 阻力
      if (x < -maxRight) x = -maxRight + (x + maxRight) * 0.3;
      setTranslateX(x);
    },
    [disabled, maxLeft, maxRight]
  );

  const onTouchEnd = useCallback(() => {
    if (disabled) return;
    if (isHorizontal.current !== true) return;
    const x = getX();
    const w = widthRef.current;
    const openLeft = x > w * threshold;       // 右滑超过阈值
    const openRight = x < -w * threshold;     // 左滑超过阈值

    if (openLeft) {
      setTranslateX(maxLeft);
      setIsOpen("left");
    } else if (openRight) {
      setTranslateX(-maxRight);
      setIsOpen("right");
    } else {
      setTranslateX(0);
      setIsOpen(null);
    }
    isHorizontal.current = null;
  }, [disabled, threshold, maxLeft, maxRight]);

  const close = useCallback(() => {
    setTranslateX(0);
    setIsOpen(null);
  }, []);

  // 点击外部关闭 (简单的 fallback)
  useEffect(() => {
    if (!isOpen) return;
    function onClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        close();
      }
    }
    document.addEventListener("click", onClick);
    return () => document.removeEventListener("click", onClick);
  }, [isOpen, close]);

  return {
    ref,
    translateX,
    isOpen,
    close,
    handlers: { onTouchStart, onTouchMove, onTouchEnd },
  };
}

/**
 * Swipeable 容器 (用于包装 swipe 卡片)
 * 自动应用 transform + transition
 */
export function Swipeable({
  children,
  swipe,
  className,
}: {
  children: React.ReactNode;
  swipe: ReturnType<typeof useSwipe>;
  className?: string;
}) {
  return (
    <div
      ref={swipe.ref}
      {...swipe.handlers}
      style={{
        transform: `translateX(${swipe.translateX}px)`,
        transition: swipe.translateX === 0 && !swipe.isOpen ? "transform 0.2s ease-out" : "none",
      }}
      className={cn("will-change-transform", className)}
    >
      {children}
    </div>
  );
}
