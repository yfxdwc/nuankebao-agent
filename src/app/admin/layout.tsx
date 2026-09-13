import { AdminSidebar } from "@/components/admin/sidebar";
import { AdminTopbar } from "@/components/admin/topbar";
import { MobileBottomTab } from "@/components/admin/mobile-bottom-tab";

// admin 全部强制 SSR, 绕过 build 时静态生成 (sandbox spawn EAGAIN 限制)
// 生产环境运行时仍正常, 只是不在 build 时 prerender
export const dynamic = "force-dynamic";

export default function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="relative flex min-h-screen bg-muted/30">
      <AdminSidebar />
      <div className="flex flex-1 flex-col min-w-0">
        <AdminTopbar />
        {/* 移动端: p-3 紧凑 + pb-24 留底部 Tab Bar 空间
            桌面端: p-6 宽松 */}
        <main className="flex-1 p-3 md:p-6 pb-24 md:pb-6">{children}</main>
      </div>
      {/* 移动端底部 Tab Bar (md+ 隐藏) */}
      <MobileBottomTab />
    </div>
  );
}
