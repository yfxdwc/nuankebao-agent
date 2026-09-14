// ============================================
// AdminTopbar — 顶部导航栏 (整个 /admin/* 域共享, per /admin/layout.tsx)
//
// v0.1.4 主人 2026-09-14 拍板 (master-decide, AGENTS §3 master-override):
// 1. 移除原桌面左侧 "暖客宝 v0.1 · Phase 1 W2.2" 版本文字 (主人反馈: 太长, 跟子页 tab 重复)
// 2. 改用 DevTabsNav 条件渲染: 路径以 /admin/dev 开头时显 4 个 tab (总览/架构/部署/快照)
//
// 移动端: 显 logo + 暖客宝 (沿用原设计, 方便移动端辨认)
// 桌面端:
//   - /admin/* (非 dev) 页: 左侧空, 右侧 退出登录
//   - /admin/dev/* 页: 左侧 DevTabsNav (替代版本文字), 右侧 退出登录
//
// DevTabsNav 内部判断 active, 这里只负责"要不要显示"。
// ============================================

"use client";

import { usePathname } from "next/navigation";
import { signOut } from "next-auth/react";
import { Sparkles, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DevTabsNav } from "@/components/dev/dev-tabs-nav";

export function AdminTopbar() {
  const pathname = usePathname();
  // /admin/dev 与 /admin/dev/* 都要显 tab (snapshot/[tag] 也是 dev 子页)
  const isDevPage = pathname?.startsWith("/admin/dev") ?? false;

  return (
    <header className="sticky top-0 z-30 flex h-12 md:h-14 shrink-0 items-center justify-between border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80 px-3 md:px-6">
      {/* 左: 移动显 logo, 桌面: dev 页面显 tab (替代原版本文字) */}
      <div className="flex items-center gap-2 min-w-0">
        <Sparkles className="h-4 w-4 md:hidden text-primary shrink-0" />
        <span className="md:hidden text-sm font-bold text-primary truncate">
          暖客宝
        </span>
        {isDevPage && <DevTabsNav className="hidden md:flex" />}
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
