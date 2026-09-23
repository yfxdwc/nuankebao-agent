// /admin/settings/insight — 客户管理参数调节 (主人 2026-09-23 拍)
//
// 主人原话: 「在 admin 里增加管理、调节页面, 让评分规则及其他客户管理中的参数
//   可在管理页面进行调节」
//
// 数据走 /api/admin/insight-config* (服务端 admin 鉴权); 本页只负责渲染。
// 参数元数据真相源: src/lib/customer/insight-param-meta.ts (区间与后端夹取范围一致, 有测试锁)

import { PageHeader } from "@/components/ui/page-header";
import { InsightConfigEditor } from "@/components/business/insight-config-editor";

export const dynamic = "force-dynamic";

export default function InsightSettingsPage() {
  return (
    <div className="space-y-section-y">
      <PageHeader
        title="客户管理参数"
        description="评分规则、行动提醒阈值等客户管理参数都集中在这里调节"
      />
      <InsightConfigEditor />
    </div>
  );
}