import { getOverviewReport } from "@/lib/db/queries/reports";
import { getServiceDistribution } from "@/lib/db/queries/dashboard";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
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
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">报表中心</h1>
        <p className="text-sm text-muted-foreground mt-1">
          月度趋势 + 复购周期 + 客户活跃度
        </p>
      </div>

      {/* 客户活跃度 */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card variant="outlined">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">本月新增客户</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{overview.customerActivity.newCustomersThis}</div>
          </CardContent>
        </Card>
        <Card variant="outlined">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">本月回访客户</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{overview.customerActivity.returningCustomers}</div>
          </CardContent>
        </Card>
        <Card variant="outlined">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">总活跃客户</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">
              {overview.customerActivity.totalActiveCustomers}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* 月度趋势 */}
      <Card variant="outlined">
        <CardHeader>
          <CardTitle className="text-base">最近 6 个月到店趋势</CardTitle>
        </CardHeader>
        <CardContent>
          <MonthlyTrendChart data={overview.monthlyVisits} />
        </CardContent>
      </Card>

      {/* 项目分布 */}
      {distribution.length > 0 && (
        <Card variant="outlined">
          <CardHeader>
            <CardTitle className="text-base">本月项目分布 (Top 5)</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {distribution.map((d) => (
                <div key={d.serviceItemId} className="flex items-center justify-between text-sm">
                  <span>{serviceMap.get(d.serviceItemId) ?? `#${d.serviceItemId}`}</span>
                  <Badge variant="secondary">{d.count} 次</Badge>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* 复购周期 */}
      <Card variant="outlined">
        <CardHeader>
          <CardTitle className="text-base">客户复购周期分布</CardTitle>
        </CardHeader>
        <CardContent>
          <RepurchaseChart data={overview.repurchaseIntervals} />
        </CardContent>
      </Card>
    </div>
  );
}