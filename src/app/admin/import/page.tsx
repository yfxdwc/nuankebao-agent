// force-dynamic for build (sandbox EAGAIN on static prerender)
import { ImportCustomers } from "@/components/business/import-customers";

export const dynamic = "force-dynamic";

export default function ImportPage() {
  return (
    <div className="space-y-6 max-w-3xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">导入客户</h1>
        <p className="text-sm text-muted-foreground mt-1">
          从 Excel/CSV 批量导入客户信息,自动去重 + 字段校验 + 加密入库
        </p>
      </div>
      <ImportCustomers />
    </div>
  );
}