"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Users, Heart, Bell, FileText, Sparkles, BarChart3, Upload, MessageCircle, Brain, Download, Wrench, Activity } from "lucide-react";
import { cn } from "@/lib/utils";

const navItems = [
  { href: "/admin", label: "仪表盘", icon: FileText, exact: true },
  { href: "/admin/customers", label: "客户管理", icon: Users },
  { href: "/admin/wellness-records", label: "养生记录", icon: Heart },
  { href: "/admin/follow-ups", label: "跟进任务", icon: Bell },
  { href: "/admin/interactions", label: "联系记录", icon: MessageCircle },
  { href: "/admin/reports", label: "报表中心", icon: BarChart3 },
  // 使用数据 (2026-09-22 web admin 解冻后首个新页面, ADR-0017 + CHARTER §4.4.5)
  { href: "/admin/usage", label: "使用数据", icon: Activity },
  { href: "/admin/import", label: "导入客户", icon: Upload },
  { href: "/admin/ai", label: "AI 助手", icon: Brain },
  { href: "/admin/download", label: "App 下载", icon: Download },
];

// 主人 2026-09-14 override 拍板 (v0.1.4 master-decide, AGENTS §3 反模式“mobile-only 阶段加 web admin 新功能” 主人在此场景显式拍板例外):
// 在 admin 侧栏加 /admin/dev 入口, 让主人一键从销售员产品 admin 跳到开发工具门户. 不影响 /admin/* 冻结规则的其他页
// - /dev 工具门户在 v0.1.4 已迁到 /admin/dev/ (物理位置: src/app/admin/dev/), 这里 href 同步更新
// - /dev 老 URL 重定向到 /admin/dev (per src/app/dev/page.tsx)
// - 定位: “工具”类别, 区别于 8 个产品 nav, 视觉上分隔
const toolNavItem = { href: "/admin/dev", label: "开发工具", icon: Wrench };

export function AdminSidebar() {
  const pathname = usePathname();

  return (
    <aside className="hidden md:block w-60 shrink-0 border-r bg-background">
      <div className="flex h-14 items-center gap-2 border-b px-6">
        <Sparkles className="h-5 w-5 text-primary" />
        <div>
          <h1 className="text-lg font-bold text-primary leading-none">暖客宝</h1>
          <p className="text-xs text-muted-foreground leading-none mt-1">
            大健康 CRM
          </p>
        </div>
      </div>
      <nav className="px-3 py-4 space-y-1">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = item.exact
            ? pathname === item.href
            : pathname === item.href ||
              pathname.startsWith(item.href + "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors",
                isActive
                  ? "bg-primary text-primary-foreground"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
              )}
            >
              <Icon className="h-4 w-4" />
              {item.label}
            </Link>
          );
        })}
        {/* 工具分隔: 主人 2026-09-14 override, 加 /admin/dev 入口 (v0.1.4 master-decide) */}
        <div className="my-3 border-t border-border/60" aria-hidden="true" />
        {(() => {
          const Icon = toolNavItem.icon;
          const isActive =
            pathname === toolNavItem.href ||
            pathname.startsWith(toolNavItem.href + "/");
          return (
            <Link
              href={toolNavItem.href}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors",
                isActive
                  ? "bg-primary text-primary-foreground"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
              )}
            >
              <Icon className="h-4 w-4" />
              {toolNavItem.label}
            </Link>
          );
        })()}
      </nav>
      <div className="absolute bottom-4 left-3 right-3 text-xs text-muted-foreground">
        <p className="px-3">v0.1 · Phase 1 W1</p>
      </div>
    </aside>
  );
}