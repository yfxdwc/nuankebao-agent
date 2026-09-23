import { getOverviewReport } from "@/lib/db/queries/reports";
import { getServiceDistribution } from "@/lib/db/queries/dashboard";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { PageHeader } from "@/components/ui/page-header";
import { Section } from "@/components/ui/section";
import { StatGroup, StatRow } from "@/components/ui/stat-row";
import { MonthlyTrendChart, RepurchaseChart } from "@/components/business/charts";

export const dynamic = "force-dynamic";

export default async function ReportsPage() {
  const [overview, distribution, dict] = await Promise.all([
    getOverviewReport(),
    getServiceDistribution(),
    listAllDictionaries(),
  ]);

  const serviceMap = new Map<string, string>(
    dict.serviceItems.map((s: { id: string; name: string }) => [s.id, s.name])
  );

  return (
    <div className="space-y-section-y">
      <PageHeader
        title="报表中心"
        description="月度趋势 + 复购周期 + 客户活跃度"
      />

      {/* 客户活跃度 (StatGroup 横排; 不要 3 张卡片墙) */}
      <StatGroup title="客户活跃度">
        <StatRow label="本月新增客户" value={overview.customerActivity.newCustomersThis} />
        <StatRow label="本月回访客户" value={overview.customerActivity.returningCustomers} />
        <StatRow label="总活跃客户" value={overview.customerActivity.totalActiveCustomers} />
      </StatGroup>

      {/* 月度趋势 */}
      <Section title="最近 6 个月到店趋势">
        <MonthlyTrendChart data={overview.monthlyVisits} />
      </Section>

      {/* 项目分布 (Top 5) — 同质列表 = divide-y */}
      {distribution.length > 0 && (
        <Section title="本月项目分布 (Top 5)">
          <ul className="divide-y divide-divider">
            {distribution.map((d) => (
              <li key={d.serviceItemId} className="py-2.5 flex items-center justify-between gap-3">
                <span className="text-body-lg text-content-primary truncate min-w-0 flex-1">
                  {serviceMap.get(d.serviceItemId) ?? `#${d.serviceItemId}`}
                </span>
                <span className="text-caption text-content-tertiary tabular-nums shrink-0">
                  {d.count} 次
                </span>
              </li>
            ))}
          </ul>
        </Section>
      )}

      {/* 复购周期 */}
      <Section title="客户复购周期分布">
        <RepurchaseChart data={overview.repurchaseIntervals} />
      </Section>
    </div>
  );
}