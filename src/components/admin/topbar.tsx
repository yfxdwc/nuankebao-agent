"use client";

import { signOut } from "next-auth/react";
import { Sparkles, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";

export function AdminTopbar() {
  return (
    <header className="sticky top-0 z-30 flex h-12 md:h-14 shrink-0 items-center justify-between border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80 px-3 md:px-6">
      {/* 左: 移动显 logo, 桌面显副标题 (vibe 营销员友好) */}
      <div className="flex items-center gap-2 min-w-0">
        <Sparkles className="h-4 w-4 md:hidden text-primary shrink-0" />
        <span className="md:hidden text-sm font-bold text-primary truncate">
          暖客宝
        </span>
        <span className="hidden md:inline text-sm text-muted-foreground">
          暖客宝 v0.1 · Phase 1 W2.2
        </span>
      </div>

      {/* 右: 移动只显 icon 按钮, 桌面显完整按钮 */}
      <Button
        variant="ghost"
        size="icon"
        className="md:hidden h-9 w-9 text-muted-foreground"
        onClick={() => signOut({ callbackUrl: "/login" })}
        aria-label="退出登录"
      >
        <LogOut className="h-4 w-4" />
      </Button>
      <Button
        variant="ghost"
        size="sm"
        className="hidden md:inline-flex"
        onClick={() => signOut({ callbackUrl: "/login" })}
      >
        <LogOut className="h-4 w-4 mr-2" />
        退出登录
      </Button>
    </header>
  );
}
