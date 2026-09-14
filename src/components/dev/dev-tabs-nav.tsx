// ============================================
// DevTabsNav — /admin/dev/* 子模块 tab 导航 (纯 tab 列表, 无外层 sticky 容器)
//
// v0.1.4 主人 2026-09-14 拍板 (第二轮改版):
// 把 dev 顶部 tab 从内容区搬到 topbar 内部, 替代原 topbar 的版本文字
// "暖客宝 v0.1 · Phase 1 W2.2". 视觉风格同步调整:
//   - 原: 底部 2px 绿线 (border-b-2 border-primary)
//   - 新: 圆角 + 浅绿底 (rounded-md + bg-primary/10), 适合 topbar 内部
//
// 用法 (由 AdminTopbar 条件渲染, 路径以 /admin/dev 开头时显示):
//   {isDevPage && <DevTabsNav className="hidden md:flex" />}
//
// 设计要点:
// - 用 <Link> 而非 client state: URL 干净, 可分享, 浏览器 back/forward 工作
// - usePathname 判断 active (前缀匹配, /admin/dev/architecture/c4 也高亮"架构")
// - 总览 tab 用 exact (避免子路径也高亮总览)
// - props.className 留给调用方控制显示/隐藏 + 间距 (e.g. "hidden md:flex")
// ============================================

"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import {
  LayoutGrid,
  Network,
  Database,
  History,
  type LucideIcon,
} from "lucide-react";

interface Tab {
  href: string;
  label: string;
  icon: LucideIcon;
  /** 路径前缀匹配, e.g. "/admin/dev/architecture" 让 /admin/dev/architecture/c4 也高亮 */
  matchPrefix?: string;
  /** strict 等值匹配 (总览 tab, 避免子路径也高亮) */
  exact?: boolean;
}

const tabs: Tab[] = [
  {
    href: "/admin/dev",
    label: "总览",
    icon: LayoutGrid,
    /** 总览只在 pathname 严格 == /admin/dev (不含子路径) 时 active */
    exact: true,
  },
  {
    href: "/admin/dev/architecture",
    label: "架构",
    icon: Network,
    matchPrefix: "/admin/dev/architecture",
  },
  {
    href: "/admin/dev/deploy",
    label: "部署",
    icon: Database,
    matchPrefix: "/admin/dev/deploy",
  },
  {
    href: "/admin/dev/snapshot",
    label: "快照",
    icon: History,
    matchPrefix: "/admin/dev/snapshot",
  },
];

interface DevTabsNavProps {
  className?: string;
}

export function DevTabsNav({ className }: DevTabsNavProps) {
  const pathname = usePathname();

  return (
    <div
      className={cn("flex gap-1 overflow-x-auto", className)}
      role="tablist"
      aria-label="开发工具子模块"
    >
      {tabs.map((tab) => {
        const Icon = tab.icon;
        // active 判断:
        // - exact tab (总览): pathname === href (不允许前缀匹配)
        // - prefix tab (架构/部署/快照): pathname 等于 prefix 本身 或 以 prefix + "/" 开头
        const prefix = tab.matchPrefix ?? tab.href;
        const isActive = tab.exact
          ? pathname === tab.href
          : pathname === prefix || pathname.startsWith(prefix + "/");
        return (
          <Link
            key={tab.href}
            href={tab.href}
            role="tab"
            aria-selected={isActive}
            className={cn(
              "flex items-center gap-1.5 md:gap-2 px-2.5 md:px-3 py-1 text-sm font-medium rounded-md transition-colors whitespace-nowrap shrink-0",
              isActive
                ? "bg-primary/10 text-primary"
                : "text-muted-foreground hover:text-foreground hover:bg-muted"
            )}
          >
            <Icon className="h-4 w-4" />
            {tab.label}
          </Link>
        );
      })}
    </div>
  );
}
