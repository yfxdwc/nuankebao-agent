"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Users,
  Heart,
  Bell,
  FileText,
  Sparkles,
  BarChart3,
  Upload,
  MessageCircle,
  Brain,
  Download,
  Wrench,
  Activity,
  SlidersHorizontal,
  ListChecks,
} from "lucide-react";
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
  { href: "/admin/settings/insight", label: "参数调节", icon: SlidersHorizontal },
];

// 主人 2026-09-14 override 拍板 (v0.1.4 master-decide, AGENTS §3 反模式"mobile-only 阶段加 web admin 新功能" 主人在此场景显式拍板例外):
// 在 admin 侧栏加 /admin/dev 入口, 让主人一键从销售员产品 admin 跳到开发工具门户. 不影响 /admin/* 冻结规则的其他页
// - /dev 工具门户在 v0.1.4 已迁到 /admin/dev/ (物理位置: src/app/admin/dev/), 这里 href 同步更新
// - /dev 老 URL 重定向到 /admin/dev (per src/app/dev/page.tsx)
// - 定位: "工具"类别, 区别于 8 个产品 nav, 视觉上分隔
const toolNavItems: { href: string; label: string; icon: typeof Wrench }[] = [
  // 开发计划 (v0.1.5 主人 2026-09-23 拍板 d3e7f2a1, ask_user 「admin 端增加开发计划模块」)
  // 位置选 a: 独立 /admin/plan, 跟 /admin/dev 平级, 跟"开发工具"同组 (都属于 admin 自用工具型菜单)
  // 排序: 计划(看接下来做什么) 在 工具(运维当前) 之前 — 读序优先
  { href: "/admin/plan", label: "开发计划", icon: ListChecks },
  { href: "/admin/dev", label: "开发工具", icon: Wrench },
];

export function AdminSidebar() {
  const pathname = usePathname();

  return (
    <aside className="hidden md:block w-56 shrink-0 border-r bg-background">
      {/* B3 重构 (2026-09-23):
          - logo 文字改 span (修 与 PageHeader h1 同页两个 h1 的 a11y 问题)
          - 高度统一 h-12 (topbar 同高)
          - 无 shadow, 1px border-r 兜底 */}
      <div className="flex h-12 items-center gap-2 border-b px-4">
        <Sparkles className="h-4 w-4 text-brand shrink-0" />
        <span className="text-body-lg font-semibold text-content-primary leading-none">
          暖客宝
        </span>
        <span className="text-caption text-content-tertiary leading-none ml-1">
          admin
        </span>
      </div>
      <nav className="px-3 py-3 space-y-0.5">
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
                // B 档: nav 项 text-body-lg(15) — active 走 bg-brand-surface + text-brand + font-medium (浅底)
                // 不用 SaaS 风的"实心块 bg-primary" (反 vibe)
                "flex items-center gap-2.5 rounded-md px-3 py-1.5 text-body-lg transition-colors min-h-control",
                isActive
                  ? "bg-brand-surface text-brand font-medium"
                  : "text-content-secondary hover:bg-surface-subtle hover:text-content-primary"
              )}
            >
              <Icon className="h-4 w-4 shrink-0" />
              {item.label}
            </Link>
          );
        })}

        {/* 工具分隔: 主人 2026-09-14 override, 加 /admin/dev 入口 (v0.1.4 master-decide)
            + 2026-09-23 主人拍板 (ask_user d3e7f2a1) 加 /admin/plan (v0.1.5)
            B3 重构: 分组标题用 text-caption text-content-tertiary (轻量) 而不是分隔线加粗 */}
        <p className="px-3 pt-4 pb-1 text-caption text-content-tertiary">
          工具
        </p>
        {toolNavItems.map((item) => {
          const Icon = item.icon;
          const isActive =
            pathname === item.href ||
            pathname.startsWith(item.href + "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-2.5 rounded-md px-3 py-1.5 text-body-lg transition-colors min-h-control",
                isActive
                  ? "bg-brand-surface text-brand font-medium"
                  : "text-content-secondary hover:bg-surface-subtle hover:text-content-primary"
              )}
            >
              <Icon className="h-4 w-4 shrink-0" />
              {item.label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}