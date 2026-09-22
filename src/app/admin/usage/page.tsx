// /admin/usage — 真实用户使用数据看板 (2026-09-22 web admin 解冻后首个新页面)
//
// 数据走 /api/admin/usage/* (服务端 admin 鉴权); 本页只负责渲染
// 采集侧: Flutter core/telemetry (release APK) → POST /api/usage/events

import { UsageDashboard } from "@/components/business/usage-dashboard";

export const dynamic = "force-dynamic";

export default function UsagePage() {
  return <UsageDashboard />;
}
