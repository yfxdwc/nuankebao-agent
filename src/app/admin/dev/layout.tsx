// ============================================
// /admin/dev/layout.tsx — 开发工具子页 layout
//
// v0.1.4 主人 2026-09-14 拍板:
// 开发工具子模块以"顶部 tab 导航 + 内容区"方式呈现, 替代原入口卡片.
// 此 layout 包装 <DevTabsNav /> + {children}, 让所有 /admin/dev/* 子页共享顶部 tab.
//
// 父 layout /admin/layout.tsx 提供 AdminSidebar + AdminTopbar + MobileBottomTab,
// DevTabsNav sticky 在 AdminTopbar (h-12) 下面, 内容区继续渲染 page.tsx.
//
// 注意: 不能继承 /admin/layout.tsx 的同时, 删 sidebar — sidebar 还在,
// 因为 /admin/dev/* 是 /admin 子树, master-decide 集成是 v0.1.4 拍板.
// ============================================

import { DevTabsNav } from "@/components/dev/dev-tabs-nav";

export default function DevLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <>
      <DevTabsNav />
      {children}
    </>
  );
}