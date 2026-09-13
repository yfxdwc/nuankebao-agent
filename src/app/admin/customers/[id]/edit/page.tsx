import { notFound } from "next/navigation";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { CustomerForm } from "@/components/business/customer-form";
import { getCustomerById } from "@/lib/db/queries/customer";
import { ArrowLeft } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function EditCustomerPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const customer = await getCustomerById(BigInt(id));
  if (!customer) notFound();

  return (
    <div className="space-y-6 max-w-2xl">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" asChild>
          <Link href={`/admin/customers/${id}`}>
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <h1 className="text-3xl font-bold tracking-tight">编辑客户</h1>
      </div>
      <CustomerForm
        mode="edit"
        initial={{
          id: customer.id,
          name: customer.name,
          phone: customer.phone,
          gender: customer.gender ?? undefined,
          birthYear: customer.birthYear ?? undefined,
          healthTags: customer.healthTags,
          diseaseHistory: customer.diseaseHistory ?? undefined,
          notes: customer.notes ?? undefined,
        }}
      />
    </div>
  );
}