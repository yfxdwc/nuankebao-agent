"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import {
  Home,
  Users,
  Heart,
  Bell,
  BarChart3,
  Upload,
  MessageCircle,
  Brain,
  Download,
  LogOut,
  X,
  ChevronRight,
  Activity,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { signOut } from "next-auth/react";

/**
 * 暖客宝 移动端底部 Tab Bar (W16)
 *
 * 设计原则 (AGENTS.md §1):
 *   - mobile-first: 养生销售员手机重度使用, 拇指操作
 *   - 4 主 Tab + 1 "更多" 入口, iOS-style 底部导航
 *   - safe-area-inset-bottom (刘海/灵动岛手机)
 *   - ≥44px 触摸目标 (中年女性手指粗, Apple HIG)
 *   - 不暗色 (AGENTS.md §1 反 vibe)
 *   - 暖绿 (hsl 142 60% 35%) 主色
 *
 * 仅 <md 显示, md+ 走 sidebar (隐藏在 sidebar.tsx 的 hidden md:block)
 */

// 4 个主 Tab (最常用)
const PRIMARY_TABS = [
  { href: "/admin", label: "首页", icon: Home, exact: true },
  { href: "/admin/customers", label: "客户", icon: Users },
  { href: "/admin/wellness-records", label: "养生", icon: Heart },
  { href: "/admin/follow-ups", label: "跟进", icon: Bell },
];

// "更多" 里的次要项
const MORE_ITEMS = [
  { href: "/admin/interactions", label: "联系记录", icon: MessageCircle, desc: "总联系次数" },
  { href: "/admin/reports", label: "报表中心", icon: BarChart3, desc: "客户/养生/月度报表" },
  // 使用数据 (2026-09-22 web admin 解冻后首个新页面; 手机端从「更多」进)
  { href: "/admin/usage", label: "使用数据", icon: Activity, desc: "谁在用 / AI 点击 / 漏斗" },
  { href: "/admin/import", label: "导入客户", icon: Upload, desc: "Excel 批量导入" },
  { href: "/admin/ai", label: "AI 助手", icon: Brain, desc: "跟进建议 + 话术生成" },
  { href: "/admin/download", label: "App 下载", icon: Download, desc: "暖客宝 APK" },
];

export function MobileBottomTab() {
  const pathname = usePathname();
  const [moreOpen, setMoreOpen] = useState(false);

  // 判断"更多"是否激活 (moreOpen 或 pathname 命中 MORE_ITEMS)
  const isMoreActive =
    moreOpen ||
    MORE_ITEMS.some(
      (i) => pathname === i.href || pathname.startsWith(i.href + "/")
    );

  return (
    <>
      {/* 底部 Tab Bar */}
      <nav
        className={cn(
          "fixed bottom-0 left-0 right-0 z-40 md:hidden",
          "bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80",
          "border-t border-border",
          // iOS safe area
          "pb-[env(safe-area-inset-bottom)]"
        )}
      >
        <div className="grid grid-cols-5 h-16">
          {PRIMARY_TABS.map((tab) => {
            const Icon = tab.icon;
            const isActive = tab.exact
              ? pathname === tab.href
              : pathname === tab.href || pathname.startsWith(tab.href + "/");
            return (
              <Link
                key={tab.href}
                href={tab.href}
                className={cn(
                  "flex flex-col items-center justify-center gap-0.5",
                  "min-h-tap-compact min-w-tap-compact",  // Apple HIG
                  "transition-colors",
                  isActive
                    ? "text-primary"
                    : "text-muted-foreground active:text-foreground"
                )}
                aria-label={tab.label}
                aria-current={isActive ? "page" : undefined}
              >
                <Icon
                  className={cn(
                    "h-5 w-5",
                    isActive && "fill-primary/20"
                  )}
                  strokeWidth={isActive ? 2.5 : 2}
                />
                <span className={cn("text-xxs", isActive && "font-medium")}>
                  {tab.label}
                </span>
              </Link>
            );
          })}

          {/* 更多 Tab */}
          <button
            type="button"
            onClick={() => setMoreOpen(true)}
            className={cn(
              "flex flex-col items-center justify-center gap-0.5",
              "min-h-tap-compact min-w-tap-compact",
              "transition-colors",
              isMoreActive
                ? "text-primary"
                : "text-muted-foreground active:text-foreground"
            )}
            aria-label="更多菜单"
            aria-expanded={moreOpen}
          >
            <svg
              className="h-5 w-5"
              viewBox="0 0 24 24"
              fill={isMoreActive ? "currentColor" : "none"}
              stroke="currentColor"
              strokeWidth={isMoreActive ? 2.5 : 2}
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <circle cx="5" cy="12" r="1.5" />
              <circle cx="12" cy="12" r="1.5" />
              <circle cx="19" cy="12" r="1.5" />
            </svg>
            <span className={cn("text-xxs", isMoreActive && "font-medium")}>
              更多
            </span>
          </button>
        </div>
      </nav>

      {/* 更多菜单 Sheet (从底部滑出) */}
      {moreOpen && (
        <>
          {/* 背景遮罩 */}
          <button
            type="button"
            onClick={() => setMoreOpen(false)}
            className="fixed inset-0 z-50 bg-black/40 backdrop-blur-sm md:hidden animate-in fade-in"
            aria-label="关闭菜单"
          />

          {/* 抽屉 */}
          <div
            className={cn(
              "fixed bottom-0 left-0 right-0 z-50 md:hidden",
              "bg-background rounded-t-2xl shadow-2xl",
              "pb-[env(safe-area-inset-bottom)]",
              "animate-in slide-in-from-bottom duration-200"
            )}
            role="dialog"
            aria-modal="true"
            aria-label="更多菜单"
          >
            {/* 把手 */}
            <div className="flex justify-center pt-3 pb-1">
              <div className="h-1 w-10 rounded-full bg-muted-foreground/30" />
            </div>

            {/* 标题栏 */}
            <div className="flex items-center justify-between px-5 py-3 border-b">
              <div>
                <h2 className="text-lg font-semibold text-foreground">
                  更多功能
                </h2>
                <p className="text-xs text-muted-foreground mt-0.5">
                  暖客宝 · 销售助手
                </p>
              </div>
              <button
                type="button"
                onClick={() => setMoreOpen(false)}
                className="p-2 -m-2 text-muted-foreground active:text-foreground"
                aria-label="关闭"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            {/* 菜单列表 */}
            <nav className="px-2 py-2 max-h-[60vh] overflow-y-auto">
              {MORE_ITEMS.map((item) => {
                const Icon = item.icon;
                const isActive =
                  pathname === item.href ||
                  pathname.startsWith(item.href + "/");
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    onClick={() => setMoreOpen(false)}
                    className={cn(
                      "flex items-center gap-3 px-3 py-3 rounded-lg",
                      "min-h-control-lg",  // 大触摸区
                      "transition-colors",
                      isActive
                        ? "bg-primary/10 text-primary"
                        : "text-foreground active:bg-muted"
                    )}
                  >
                    <div
                      className={cn(
                        "flex h-10 w-10 items-center justify-center rounded-lg shrink-0",
                        isActive
                          ? "bg-primary text-primary-foreground"
                          : "bg-muted text-muted-foreground"
                      )}
                    >
                      <Icon className="h-5 w-5" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-medium">{item.label}</div>
                      <div className="text-xs text-muted-foreground truncate">
                        {item.desc}
                      </div>
                    </div>
                    <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />
                  </Link>
                );
              })}
            </nav>

            {/* 底部: 退出登录 (移动端单独放这里, 顶栏不显) */}
            <div className="px-3 py-3 border-t">
              <button
                type="button"
                onClick={() => {
                  setMoreOpen(false);
                  signOut({ callbackUrl: "/login" });
                }}
                className={cn(
                  "flex items-center justify-center gap-2 w-full",
                  "min-h-tap px-4 rounded-lg",
                  "text-sm font-medium",
                  "text-destructive active:bg-destructive/10",
                  "transition-colors"
                )}
              >
                <LogOut className="h-4 w-4" />
                退出登录
              </button>
            </div>
          </div>
        </>
      )}
    </>
  );
}
