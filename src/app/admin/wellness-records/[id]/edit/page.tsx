import { Suspense } from "react";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { WellnessRecordForm } from "@/components/business/wellness-record-form";
import { getWellnessRecordById } from "@/lib/db/queries/wellness-record";
import { ArrowLeft } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function EditWellnessRecordPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const record = await getWellnessRecordById(BigInt(id));
  if (!record) notFound();

  return (
    <div className="space-y-6 max-w-3xl">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" asChild>
          <Link href={`/admin/wellness-records/${id}`}>
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <h1 className="text-3xl font-bold tracking-tight">编辑养生记录</h1>
      </div>
      <Suspense fallback={<div className="text-muted-foreground">加载中…</div>}>
        <WellnessRecordForm
          mode="edit"
          initial={{
            id: record.id,
            customerId: record.customerId,
            serviceDate: record.serviceDate,
            serviceItemId: record.serviceItemId,
            staffId: record.staffId,
            storeId: record.storeId,
            bodyPartIds: record.bodyPartIds,
            productUsages: record.productUsages.map((p) => ({
              productId: p.productId,
              quantity: p.quantity ? parseFloat(p.quantity) : undefined,
            })),
            preCondition: record.preCondition,
            postCondition: record.postCondition,
            processNote: record.processNote ?? undefined,
            customerFeedback: record.customerFeedback ?? undefined,
            nextAdviceDate: record.nextAdviceDate,
          }}
        />
      </Suspense>
    </div>
  );
}
