import Link from "next/link";
import {
  getDashboardStats,
  getServiceDistribution,
} from "@/lib/db/queries/dashboard";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { PageHeader } from "@/components/ui/page-header";
import { Section } from "@/components/ui/section";
import { StatRow, StatGroup } from "@/components/ui/stat-row";
import { Button } from "@/components/ui/button";
import { Plus, Activity, ArrowUpRight } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function AdminDashboardPage() {
  const [stats, distribution, dict] = await Promise.all([
    getDashboardStats(),
    getServiceDistribution(),
    listAllDictionaries(),
  ]);

  const serviceMap = new Map(dict.serviceItems.map((s) => [s.id, s.name]));

  return (
    <div className="space-y-section-y">
      {/* PageHeader (B 档: 20/600 + 描述 13) */}
      <PageHeader
        title="仪表盘"
        description={`暖客宝 v0.1 · 今天有 ${stats.pendingFollowUps} 位客户待跟进`}
        actions={
          <div className="flex gap-2">
            <Button asChild>
              <Link href="/admin/customers/new">
                <Plus className="h-4 w-4 mr-2" />
                新增客户
              </Link>
            </Button>
            <Button asChild variant="outline">
              <Link href="/admin/wellness-records/new">
                <Activity className="h-4 w-4 mr-2" />
                新增养生
              </Link>
            </Button>
          </div>
        }
      />

      {/* 统计条: StatGroup (divide-y 分隔线, 不画卡片; 原则 4) */}
      <StatGroup title="核心数据">
        <StatRow
          label={
            <Link
              href="/admin/customers"
              className="hover:underline flex items-center gap-1"
            >
              客户总数
              <ArrowUpRight className="h-3 w-3 text-content-tertiary" />
            </Link>
          }
          value={stats.customerCount}
        />
        <StatRow
          label={
            <Link
              href="/admin/wellness-records"
              className="hover:underline flex items-center gap-1"
            >
              本月到店
              <ArrowUpRight className="h-3 w-3 text-content-tertiary" />
            </Link>
          }
          value={stats.thisMonthVisits}
        />
        <StatRow
          label={
            <Link
              href="/admin/follow-ups"
              className="hover:underline flex items-center gap-1"
            >
              待跟进
              <ArrowUpRight className="h-3 w-3 text-content-tertiary" />
            </Link>
          }
          value={stats.pendingFollowUps}
          tone="warning"
        />
        <StatRow
          label={
            <Link
              href="/admin/interactions"
              className="hover:underline flex items-center gap-1"
            >
              联系记录
              <ArrowUpRight className="h-3 w-3 text-content-tertiary" />
            </Link>
          }
          value={stats.totalInteractions}
        />
      </StatGroup>

      {/* 本月项目分布 (Section + 同质列表 = divide-y; 无卡片) */}
      {distribution.length > 0 && (
        <Section title="本月项目分布 (Top 5)">
          {/* divide-y 分隔线列表 (无 Card 容器; 原则 4) */}
          <ul className="divide-y divide-divider -mx-1">
            {distribution.map((d) => {
              const maxCount = distribution[0]?.count || 1;
              const pct = Math.round((d.count / maxCount) * 100);
              return (
                <li key={d.serviceItemId} className="py-2.5">
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-body-lg text-content-primary truncate min-w-0 flex-1">
                      {serviceMap.get(d.serviceItemId) ?? `#${d.serviceItemId}`}
                    </span>
                    <span className="text-body tabular-nums text-content-secondary shrink-0">
                      {d.count} 次
                    </span>
                  </div>
                  {/* 进度条 (1.5px, bg-primary fill; 视觉分量小, 不抢主区) */}
                  <div className="h-1 bg-surface-sunken rounded-full overflow-hidden mt-1.5">
                    <div
                      className="h-full bg-brand rounded-full transition-all"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
        </Section>
      )}

      {/* 移动专属: 底部呼吸区, 避免最后一项贴 Tab Bar */}
      <div className="h-2 md:hidden" aria-hidden="true" />
    </div>
  );
}