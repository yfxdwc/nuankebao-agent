// force-dynamic for build (sandbox EAGAIN on static prerender)
import { PageHeader } from "@/components/ui/page-header";
import { ImportCustomers } from "@/components/business/import-customers";

export const dynamic = "force-dynamic";

export default function ImportPage() {
  return (
    <div className="space-y-section-y max-w-3xl">
      <PageHeader
        title="导入客户"
        description="从 Excel/CSV 批量导入客户信息,自动去重 + 字段校验 + 加密入库"
      />
      <ImportCustomers />
    </div>
  );
}