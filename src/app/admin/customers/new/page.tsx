// force-dynamic for build (sandbox EAGAIN on static prerender)
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { CustomerForm } from "@/components/business/customer-form";
import { ArrowLeft } from "lucide-react";

export const dynamic = "force-dynamic";

export default function NewCustomerPage() {
  return (
    <div className="space-y-6 max-w-2xl">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" asChild>
          <Link href="/admin/customers">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <h1 className="text-3xl font-bold tracking-tight">新增客户</h1>
      </div>
      <CustomerForm mode="create" />
    </div>
  );
}