// force-dynamic for build (sandbox EAGAIN on static prerender)
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/ui/page-header";
import { CustomerForm } from "@/components/business/customer-form";
import { ArrowLeft } from "lucide-react";

export const dynamic = "force-dynamic";

export default function NewCustomerPage() {
  return (
    <div className="space-y-section-y max-w-2xl">
      <PageHeader
        title="新增客户"
        actions={
          <Button variant="ghost" size="sm" asChild>
            <Link href="/admin/customers">
              <ArrowLeft className="h-4 w-4 mr-1" />
              返回列表
            </Link>
          </Button>
        }
      />
      <CustomerForm mode="create" />
    </div>
  );
}