// /dev/layout.tsx — 开发工具门户布局
//
// 主人 2026-09-14 拍板 (v0.1.4 override):
// 把 /dev 集成到 /admin 的视觉上下文 (复用 AdminSidebar + AdminTopbar + MobileBottomTab),
// 让主人从 /admin 点侧栏 "开发工具" 进入 /dev 时保持侧栏导航, 不丢上下文.
//
// 为什么用 admin 的 layout 而不是单独的?
// - /dev 跟 /admin 在同一棵 React tree, 共享同一套 layout 资源
// - AdminSidebar 已经加了 /dev 入口 (sidebar.tsx v0.1.4), 从 /dev 也能点回 /admin/*
// - 复用 admin 的 topbar (版本号显示 + 用户菜单) + mobile bottom tab
// - 不增加新 layout 文件, 不引入新视觉差异
//
// 冻结规则例外: 这是 owner 显式 override (AGENTS §3 反模式 "mobile-only 阶段加 web admin 新功能"
// 在本场景由主人在 v0.1.4 拍板例外, 理由: /dev 入口让主人 vibe coding 时一键切到开发工具,
// 不增加 admin 域本身的页面 / 交互, 只在侧栏加 1 个 nav item).

import { AdminSidebar } from "@/components/admin/sidebar";
import { AdminTopbar } from "@/components/admin/topbar";
import { MobileBottomTab } from "@/components/admin/mobile-bottom-tab";

export const dynamic = "force-dynamic";

export default function DevLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="relative flex min-h-screen bg-muted/30">
      <AdminSidebar />
      <div className="flex flex-1 flex-col min-w-0">
        <AdminTopbar />
        <main className="flex-1 p-3 md:p-6 pb-24 md:pb-6">{children}</main>
      </div>
      <MobileBottomTab />
    </div>
  );
}