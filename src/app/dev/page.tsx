// ============================================
// /dev → /admin/dev redirect
//
// v0.1.4 主人 2026-09-14 拍板 (master-decide, AGENTS §3 反模式 master-override 例外):
// /dev 工具门户集成到 /admin 域下, 路由改为 /admin/dev/*.
// 老 URL /dev 自动重定向到 /admin/dev (deep link / 书签兼容).
//
// 移动历史: src/app/dev/* → src/app/admin/dev/* (per git mv --follow 历史可追).
// 涉及的子页 (12 个) + 注释 + 内部 link 全部更新, 详见 commit。
// ============================================

import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default function DevRedirectPage() {
  redirect("/admin/dev");
}
