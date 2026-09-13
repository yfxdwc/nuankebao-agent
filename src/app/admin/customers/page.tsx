import { listCustomers } from "@/lib/db/queries/customer";
import { Fab } from "@/components/ui/fab";
import { CustomerSearch } from "@/components/business/customer-search";
import { CustomerListInfinite } from "@/components/business/customer-list-infinite";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 20;

export default async function CustomersPage({
  searchParams,
}: {
  searchParams: Promise<{ search?: string }>;
}) {
  const { search } = await searchParams;

  // SSR 首屏: 取第一页 (20 条, 满足初始滚动可见)
  const { items, total } = await listCustomers({ search, limit: PAGE_SIZE, offset: 0 });

  // 序列化为可序列化的 plain object (Date → ISO string)
  const initial = items.map((c) => ({
    ...c,
    createdAt: c.createdAt.toISOString(),
    updatedAt: c.updatedAt.toISOString(),
  }));

  return (
    <div className="space-y-3 md:space-y-6">
      <div>
        <h1 className="text-xl md:text-3xl font-bold tracking-tight">客户管理</h1>
        <p className="text-xs md:text-sm text-muted-foreground mt-0.5 md:mt-1">
          共 {total} 位客户
        </p>
      </div>

      <CustomerSearch initial={search ?? ""} />

      <CustomerListInfinite
        initial={initial}
        initialTotal={total}
        pageSize={PAGE_SIZE}
        search={search ?? ""}
      />

      <div className="h-16 md:hidden" aria-hidden="true" />
      <Fab href="/admin/customers/new" label="新增客户" />
    </div>
  );
}
