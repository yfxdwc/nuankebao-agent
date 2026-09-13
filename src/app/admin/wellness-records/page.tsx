import Link from "next/link";
import { listWellnessRecords } from "@/lib/db/queries/wellness-record";
import { getCustomerById } from "@/lib/db/queries/customer";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Fab } from "@/components/ui/fab";
import { formatDate } from "@/lib/utils";
import { Heart, ArrowRight } from "lucide-react";

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
    <div className="space-y-3 md:space-y-6">
      <div>
        <h1 className="text-xl md:text-3xl font-bold tracking-tight">
          养生记录
        </h1>
        <p className="text-xs md:text-sm text-muted-foreground mt-0.5 md:mt-1">
          共 {records.total} 条{customerId && " (按客户筛选)"}
        </p>
      </div>

      {/* 客户筛选 chip (按客户查看时显示清除) */}
      {customerId && (
        <Link
          href="/admin/wellness-records"
          className="inline-flex items-center gap-1.5 text-xs text-primary px-3 py-1.5 rounded-full bg-primary/10 hover:bg-primary/20 active:scale-95 transition-all"
        >
          <span>正在按客户筛选 (ID: {customerId})</span>
          <span className="font-medium">×</span>
        </Link>
      )}

      {records.items.length === 0 ? (
        <Card>
          <CardContent className="py-8 md:py-12 text-center text-muted-foreground text-sm">
            暂无养生记录
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2 md:space-y-3">
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
              <Link
                key={r.id}
                href={`/admin/wellness-records/${r.id}`}
                className="block active:scale-[0.99] transition-transform"
              >
                <Card className="hover:shadow-md transition-shadow cursor-pointer">
                  <CardContent className="p-3 md:p-4">
                    {/* 头: 客户 + 日期 */}
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <h3 className="text-sm md:text-base font-medium truncate">
                          {customer?.name ?? `客户 ${r.customerId}`}
                        </h3>
                        <p className="text-[10px] md:text-xs text-muted-foreground mt-0.5">
                          {formatDate(r.serviceDate)}
                        </p>
                      </div>
                      <Badge variant="outline" className="text-[10px] md:text-xs shrink-0">
                        {serviceMap.get(r.serviceItemId) ?? `项目 ${r.serviceItemId}`}
                      </Badge>
                    </div>

                    {/* 部位 tags */}
                    {r.bodyPartIds.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-2">
                        {r.bodyPartIds.slice(0, 3).map((id) => (
                          <Badge
                            key={id}
                            variant="secondary"
                            className="text-[10px] md:text-xs"
                          >
                            {bodyPartMap.get(id) ?? `#${id}`}
                          </Badge>
                        ))}
                        {r.bodyPartIds.length > 3 && (
                          <span className="text-[10px] text-muted-foreground self-center">
                            +{r.bodyPartIds.length - 3}
                          </span>
                        )}
                      </div>
                    )}

                    {/* 效果对比: 疼痛 + 睡眠 (移动极简, 桌面详细) */}
                    {hasMetrics && (
                      <div className="mt-2 flex items-center gap-3 text-[10px] md:text-xs">
                        {painBefore !== undefined || painAfter !== undefined ? (
                          <span className="text-rose-700">
                            疼痛 {String(painBefore ?? "-")} → {String(painAfter ?? "-")}
                          </span>
                        ) : null}
                        {sleepBefore !== undefined || sleepAfter !== undefined ? (
                          <span className="text-indigo-700">
                            睡眠 {String(sleepBefore ?? "-")} → {String(sleepAfter ?? "-")}
                          </span>
                        ) : null}
                      </div>
                    )}

                    {/* 反馈 (line-clamp 1) */}
                    {r.customerFeedback && (
                      <p className="text-[10px] md:text-xs text-muted-foreground line-clamp-1 mt-1.5 italic">
                        "{r.customerFeedback}"
                      </p>
                    )}
                  </CardContent>
                </Card>
              </Link>
            );
          })}
        </div>
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
