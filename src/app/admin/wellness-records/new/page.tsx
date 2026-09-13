// force-dynamic for build (sandbox EAGAIN on static prerender)
import { Suspense } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { WellnessRecordForm } from "@/components/business/wellness-record-form";
import { ArrowLeft } from "lucide-react";

export const dynamic = "force-dynamic";

export default function NewWellnessRecordPage() {
  return (
    <div className="space-y-6 max-w-3xl">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" asChild>
          <Link href="/admin/wellness-records">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <h1 className="text-3xl font-bold tracking-tight">新增养生记录</h1>
      </div>
      <Suspense fallback={<div className="text-muted-foreground">加载中…</div>}>
        <WellnessRecordForm mode="create" />
      </Suspense>
    </div>
  );
}
