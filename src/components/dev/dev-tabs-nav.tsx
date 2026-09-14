// ============================================
// DevTabsNav — /admin/dev/* 子页统一顶部 tab 导航栏
//
// v0.1.4 主人 2026-09-14 拍板:
// 开发工具以"顶部导航栏 tab"方式呈现, 替代原 /admin/dev 入口卡片列表.
// - 总览 tab → /admin/dev (3+4 模块卡片)
// - 架构 tab → /admin/dev/architecture (架构图)
// - 部署 tab → /admin/dev/deploy (部署 + 备份状态)
// - 快照 tab → /admin/dev/snapshot (任务快照列表)
//
// 设计要点:
// - 用 <Link> 而非 client state: URL 干净, 可分享, 浏览器 back/forward 工作
// - usePathname 判断 active (前缀匹配, /admin/dev/architecture/c4 也高亮"架构")
// - sticky top-12 (admin/topbar h-12 下面)
// - 移动: 横向滚动 + 小标签; 桌面: 4 tab 均匀分布
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

export function DevTabsNav() {
  const pathname = usePathname();

  return (
    <nav
      className="sticky top-12 z-20 -mx-3 md:-mx-6 mb-4 md:mb-6 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80 px-3 md:px-6"
      aria-label="开发工具子模块"
    >
      <div className="flex gap-1 overflow-x-auto -mb-px">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          // active 判断:
          // - exact tab (总览): pathname === href (不允许前缀匹配, 避免 /admin/dev/architecture 也让总览 active)
          // - prefix tab (架构/部署/快照): pathname 等于 prefix 本身 或 以 prefix + "/" 开头
          const prefix = tab.matchPrefix ?? tab.href;
          const isActive = tab.exact
            ? pathname === tab.href
            : pathname === prefix || pathname.startsWith(prefix + "/");
          return (
            <Link
              key={tab.href}
              href={tab.href}
              className={cn(
                "flex items-center gap-1.5 md:gap-2 px-3 md:px-4 py-2.5 text-sm font-medium border-b-2 transition-colors whitespace-nowrap shrink-0",
                isActive
                  ? "border-primary text-primary"
                  : "border-transparent text-muted-foreground hover:text-foreground hover:border-muted"
              )}
              aria-current={isActive ? "page" : undefined}
            >
              <Icon className="h-4 w-4" />
              {tab.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}