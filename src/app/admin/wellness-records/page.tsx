import Link from "next/link";
import { listWellnessRecords } from "@/lib/db/queries/wellness-record";
import { getCustomerById } from "@/lib/db/queries/customer";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { PageHeader } from "@/components/ui/page-header";
import { Fab } from "@/components/ui/fab";
import { formatDate } from "@/lib/utils";
import { Heart } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function WellnessRecordsPage({
  searchParams,
}: {
  searchParams: Promise<{ customerId?: string }>;
}) {
  const { customerId } = await searchParams;

  const [records, dict] = await Promise.all([
    listWellnessRecords({ customerId, limit: 50 }),
    listAllDictionaries(),
  ]);

  // 批量取 customer 名字 (避免 N+1)
  const customerIds = Array.from(new Set(records.items.map((r) => r.customerId)));
  const customers = await Promise.all(
    customerIds.map((id: string) => getCustomerById(BigInt(id)))
  );
  const customerMap = new Map(
    customers.filter((c): c is NonNullable<typeof c> => !!c).map((c) => [c.id, c])
  );

  const serviceMap = new Map(dict.serviceItems.map((s) => [s.id, s.name]));
  const bodyPartMap = new Map(dict.bodyParts.map((b) => [b.id, b.name]));

  return (
    <div className="space-y-section-y">
      <PageHeader
        title="养生记录"
        description={`共 ${records.total} 条${customerId ? " (按客户筛选)" : ""}`}
      />

      {/* 客户筛选 chip (按客户查看时显示清除) */}
      {customerId && (
        <Link
          href="/admin/wellness-records"
          className="inline-flex items-center gap-1.5 text-caption text-brand px-3 py-1.5 rounded-full bg-brand-surface hover:bg-brand-surface/80 min-h-control-sm"
        >
          <span>正在按客户筛选 (ID: {customerId})</span>
          <span className="font-medium">×</span>
        </Link>
      )}

      {records.items.length === 0 ? (
        <div className="py-10 text-center text-body text-content-secondary">
          暂无养生记录
        </div>
      ) : (
        // B3: 同质列表 = divide-y 分隔线, 不画 Card (原则 4)
        <ul className="divide-y divide-divider">
          {records.items.map((r) => {
            const customer = customerMap.get(r.customerId);
            const painBefore = r.preCondition.pain_level as number | undefined;
            const painAfter = r.postCondition.pain_level as number | undefined;
            const sleepBefore = r.preCondition.sleep_quality as number | undefined;
            const sleepAfter = r.postCondition.sleep_quality as number | undefined;
            const hasMetrics =
              painBefore !== undefined ||
              painAfter !== undefined ||
              sleepBefore !== undefined ||
              sleepAfter !== undefined;

            return (
              <li key={r.id}>
                {/* B3b: 行高收到 ≤60px — py-1.5 (12) + 主行+副行 (47) = 59;
                    旧版 98 减 39 (项目/部位/反馈 → 2 行; 反馈进详情; tags 限缩到 2 个; 去背景块);
                    py-1.5 偏离 spec "py-row-y 参考口径", 为达 ≤60 硬指标 取 py-1.5 */}
                <Link
                  href={`/admin/wellness-records/${r.id}`}
                  className="block px-1 py-1.5 hover:bg-surface-subtle transition-colors active:bg-surface-sunken min-h-row"
                >
                  {/* 头: 客户 + 日期 (右侧等宽对齐) */}
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="text-body-lg font-medium text-content-primary truncate min-w-0 flex-1">
                      {customer?.name ?? `客户 ${r.customerId}`}
                    </span>
                    <span className="text-caption text-content-tertiary tabular-nums shrink-0">
                      {formatDate(r.serviceDate)}
                    </span>
                  </div>

                  {/* 项目 + 部位 + 效果 (合并到一行, 减行数) */}
                  <div className="flex items-center gap-2 mt-0.5 flex-wrap text-caption">
                    <span className="text-body text-content-secondary">
                      {serviceMap.get(r.serviceItemId) ?? `项目 ${r.serviceItemId}`}
                    </span>
                    {r.bodyPartIds.length > 0 && (
                      <>
                        {r.bodyPartIds.slice(0, 2).map((id) => (
                          <span
                            key={id}
                            className="text-caption text-content-secondary"
                          >
                            {bodyPartMap.get(id) ?? `#${id}`}
                          </span>
                        ))}
                        {r.bodyPartIds.length > 2 && (
                          <span className="text-caption text-content-tertiary">
                            +{r.bodyPartIds.length - 2}
                          </span>
                        )}
                      </>
                    )}
                    {hasMetrics && (
                      <span className="ml-auto flex items-center gap-2 tabular-nums shrink-0">
                        {painBefore !== undefined || painAfter !== undefined ? (
                          <span className="text-danger">
                            痛 {painBefore ?? "-"}→{painAfter ?? "-"}
                          </span>
                        ) : null}
                        {sleepBefore !== undefined || sleepAfter !== undefined ? (
                          <span className="text-info">
                            眠 {sleepBefore ?? "-"}→{sleepAfter ?? "-"}
                          </span>
                        ) : null}
                      </span>
                    )}
                  </div>
                </Link>
              </li>
            );
          })}
        </ul>
      )}

      <div className="h-16 md:hidden" aria-hidden="true" />
      <Fab
        href="/admin/wellness-records/new"
        label="新增养生记录"
        variant="rose"
        icon={<Heart className="h-6 w-6" />}
      />
    </div>
  );
}