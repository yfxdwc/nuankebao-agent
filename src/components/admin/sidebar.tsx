"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Users, Heart, Bell, FileText, Sparkles, BarChart3, Upload, MessageCircle, Brain, Download } from "lucide-react";
import { cn } from "@/lib/utils";

const navItems = [
  { href: "/admin", label: "仪表盘", icon: FileText, exact: true },
  { href: "/admin/customers", label: "客户管理", icon: Users },
  { href: "/admin/wellness-records", label: "养生记录", icon: Heart },
  { href: "/admin/follow-ups", label: "跟进任务", icon: Bell },
  { href: "/admin/interactions", label: "联系记录", icon: MessageCircle },
  { href: "/admin/reports", label: "报表中心", icon: BarChart3 },
  { href: "/admin/import", label: "导入客户", icon: Upload },
  { href: "/admin/ai", label: "AI 助手", icon: Brain },
  { href: "/admin/download", label: "App 下载", icon: Download },
];

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
      </nav>
      <div className="absolute bottom-4 left-3 right-3 text-xs text-muted-foreground">
        <p className="px-3">v0.1 · Phase 1 W1</p>
      </div>
    </aside>
  );
}