import { listCustomers } from "@/lib/db/queries/customer";
import { Fab } from "@/components/ui/fab";
import { PageHeader } from "@/components/ui/page-header";
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
  //   R-9 第二条: 首页 includeTotal=true 保留, 后续页交给 client + includeTotal=false
  //   SSR 这里要拿 total 给 PageHeader 标题 (e.g. "共 87 位客户"), 所以走默认 includeTotal=true
  const { items, total } = await listCustomers({ search, limit: PAGE_SIZE, offset: 0 });

  // 序列化为可序列化的 plain object (Date → ISO string)
  const initial = items.map((c) => ({
    ...c,
    createdAt: c.createdAt.toISOString(),
    updatedAt: c.updatedAt.toISOString(),
  }));

  return (
    <div className="space-y-section-y">
      <PageHeader
        title="客户管理"
        // R-9: SSR 首屏 total 必为非 null (includeTotal=true), 但加个兜底防退化
        description={`共 ${total ?? items.length} 位客户`}
      />

      <CustomerSearch initial={search ?? ""} />

      <CustomerListInfinite
        initial={initial}
        // SSR 首屏 total 必为非 null (includeTotal=true); 但接口类型变了
        //   以 null 兜底防退化 (SSR 这里传 0 比传 null 更安全)
        initialTotal={total ?? initial.length}
        pageSize={PAGE_SIZE}
        search={search ?? ""}
      />

      <div className="h-16 md:hidden" aria-hidden="true" />
      <Fab href="/admin/customers/new" label="新增客户" />
    </div>
  );
}