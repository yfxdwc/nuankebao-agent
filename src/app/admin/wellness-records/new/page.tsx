// force-dynamic for build (sandbox EAGAIN on static prerender)
import { Suspense } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/ui/page-header";
import { WellnessRecordForm } from "@/components/business/wellness-record-form";
import { ArrowLeft } from "lucide-react";

export const dynamic = "force-dynamic";

export default function NewWellnessRecordPage() {
  return (
    <div className="space-y-section-y max-w-3xl">
      <PageHeader
        title="新增养生记录"
        actions={
          <Button variant="ghost" size="sm" asChild>
            <Link href="/admin/wellness-records">
              <ArrowLeft className="h-4 w-4 mr-1" />
              返回列表
            </Link>
          </Button>
        }
      />
      <Suspense fallback={<div className="text-content-secondary">加载中…</div>}>
        <WellnessRecordForm mode="create" />
      </Suspense>
    </div>
  );
}