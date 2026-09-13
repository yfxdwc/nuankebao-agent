import { notFound } from "next/navigation";
import Link from "next/link";
import { getCustomerById } from "@/lib/db/queries/customer";
import { listWellnessRecords } from "@/lib/db/queries/wellness-record";
import { listInteractionsByCustomer } from "@/lib/db/queries/interaction";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { Button } from "@/components/ui/button";
import { ArrowLeft } from "lucide-react";
import { CustomerDetailTabs } from "@/components/business/customer-detail-tabs";

export const dynamic = "force-dynamic";

export default async function CustomerDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const customerId = BigInt(id);

  const customer = await getCustomerById(customerId);
  if (!customer) notFound();

  const [wellnessRecords, interactions, dict] = await Promise.all([
    listWellnessRecords({ customerId: id, limit: 50 }),
    listInteractionsByCustomer(id),
    listAllDictionaries(),
  ]);

  const serviceMap = Object.fromEntries(
    dict.serviceItems.map((s) => [s.id, s.name])
  );
  const bodyPartMap = Object.fromEntries(
    dict.bodyParts.map((b) => [b.id, b.name])
  );

  return (
    <div className="space-y-3 md:space-y-6">
      {/* 顶栏: 返回 + 名字 + (桌面) 编辑 */}
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 md:gap-3 min-w-0">
          <Button variant="ghost" size="icon" asChild className="shrink-0 h-9 w-9 md:h-10 md:w-10">
            <Link href="/admin/customers" aria-label="返回客户列表">
              <ArrowLeft className="h-4 w-4 md:h-5 md:w-5" />
            </Link>
          </Button>
          <div className="min-w-0">
            <h1 className="text-lg md:text-3xl font-bold tracking-tight truncate">
              {customer.name}
            </h1>
            <p className="text-[10px] md:text-sm text-muted-foreground truncate">
              注册于 {new Date(customer.createdAt).toISOString().split("T")[0]}
            </p>
          </div>
        </div>
      </div>

      {/* Tab 内容 */}
      <CustomerDetailTabs
        customer={{
          id: customer.id.toString(),
          name: customer.name,
          phone: customer.phone,
          gender: customer.gender,
          birthYear: customer.birthYear,
          healthTags: customer.healthTags,
          diseaseHistory: customer.diseaseHistory,
          notes: customer.notes,
          createdAt: customer.createdAt,
        }}
        wellnessRecords={{
          items: wellnessRecords.items.map((r) => ({
            id: r.id,
            serviceDate: r.serviceDate,
            serviceItemId: r.serviceItemId,
            bodyPartIds: r.bodyPartIds,
            customerFeedback: r.customerFeedback,
          })),
          total: wellnessRecords.total,
        }}
        interactions={interactions.map((i) => ({
          id: i.id.toString(),
          type: i.type,
          summary: i.summary ?? null,
          createdAt: i.createdAt,
        }))}
        serviceMap={serviceMap}
        bodyPartMap={bodyPartMap}
      />

      <div className="h-16 md:hidden" aria-hidden="true" />
    </div>
  );
}
