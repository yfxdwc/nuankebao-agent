import Link from "next/link";
import {
  getDashboardStats,
  getServiceDistribution,
} from "@/lib/db/queries/dashboard";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Users, Heart, Bell, MessageCircle, ArrowUpRight, Plus, Activity } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function AdminDashboardPage() {
  const [stats, distribution, dict] = await Promise.all([
    getDashboardStats(),
    getServiceDistribution(),
    listAllDictionaries(),
  ]);

  const serviceMap = new Map(dict.serviceItems.map((s) => [s.id, s.name]));

  const statsCards = [
    {
      label: "客户总数",
      value: stats.customerCount,
      icon: Users,
      href: "/admin/customers",
      note: "查看全部客户",
      tone: "bg-blue-50 text-blue-700",
    },
    {
      label: "本月到店",
      value: stats.thisMonthVisits,
      icon: Heart,
      href: "/admin/wellness-records",
      note: "本月养生记录",
      tone: "bg-rose-50 text-rose-700",
    },
    {
      label: "待跟进",
      value: stats.pendingFollowUps,
      icon: Bell,
      href: "/admin/follow-ups",
      note: "需要联系的客户",
      tone: "bg-amber-50 text-amber-700",
    },
    {
      label: "联系记录",
      value: stats.totalInteractions,
      icon: MessageCircle,
      href: "/admin/interactions",
      note: "总联系次数",
      tone: "bg-emerald-50 text-emerald-700",
    },
  ];

  return (
    <div className="space-y-4 md:space-y-6">
      {/* 标题区: 移动短, 桌面详细 */}
      <div>
        <h1 className="text-xl md:text-3xl font-bold tracking-tight">
          仪表盘
        </h1>
        <p className="text-xs md:text-sm text-muted-foreground mt-0.5 md:mt-1">
          暖客宝 v0.1 · 今天有 {stats.pendingFollowUps} 位客户待跟进
        </p>
      </div>

      {/* 4 个 stat card:
          移动 1 列 (大触摸区)
          平板 2 列
          桌面 4 列 */}
      <div className="grid gap-3 grid-cols-1 sm:grid-cols-2 lg:grid-cols-4">
        {statsCards.map((s) => {
          const Icon = s.icon;
          return (
            <Link
              key={s.label}
              href={s.href}
              className="block active:scale-[0.98] transition-transform"
            >
              <Card className="hover:shadow-md transition-shadow cursor-pointer h-full">
                <CardContent className="p-3 md:p-6">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0 flex-1">
                      <p className="text-xs md:text-sm text-muted-foreground font-medium">
                        {s.label}
                      </p>
                      <p className="text-2xl md:text-3xl font-bold mt-1 md:mt-2 truncate">
                        {s.value}
                      </p>
                      <p className="text-[10px] md:text-xs text-muted-foreground mt-1 flex items-center">
                        {s.note}
                        <ArrowUpRight className="h-3 w-3 ml-0.5" />
                      </p>
                    </div>
                    <div
                      className={`h-9 w-9 md:h-10 md:w-10 rounded-lg flex items-center justify-center shrink-0 ${s.tone}`}
                    >
                      <Icon className="h-4 w-4 md:h-5 md:w-5" />
                    </div>
                  </div>
                </CardContent>
              </Card>
            </Link>
          );
        })}
      </div>

      {/* 快捷操作 (移动常驻, 桌面用): 大按钮 + 全宽 */}
      <div className="grid gap-2 md:gap-3 grid-cols-2 md:grid-cols-2">
        <Link
          href="/admin/customers/new"
          className="flex items-center gap-2 md:gap-3 p-3 md:p-4 border-2 border-dashed border-primary/30 bg-primary/5 rounded-lg hover:bg-primary/10 active:scale-[0.98] transition-all min-h-[56px] md:min-h-0"
        >
          <div className="h-9 w-9 md:h-10 md:w-10 rounded-full bg-primary text-primary-foreground flex items-center justify-center shrink-0">
            <Plus className="h-4 w-4 md:h-5 md:w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="text-sm md:text-base font-medium text-foreground leading-tight">
              新增客户
            </h3>
            <p className="text-[10px] md:text-xs text-muted-foreground mt-0.5 truncate">
              录入健康档案
            </p>
          </div>
        </Link>
        <Link
          href="/admin/wellness-records/new"
          className="flex items-center gap-2 md:gap-3 p-3 md:p-4 border-2 border-dashed border-rose-300 bg-rose-50/50 rounded-lg hover:bg-rose-50 active:scale-[0.98] transition-all min-h-[56px] md:min-h-0"
        >
          <div className="h-9 w-9 md:h-10 md:w-10 rounded-full bg-rose-500 text-white flex items-center justify-center shrink-0">
            <Activity className="h-4 w-4 md:h-5 md:w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="text-sm md:text-base font-medium text-foreground leading-tight">
              新增养生
            </h3>
            <p className="text-[10px] md:text-xs text-muted-foreground mt-0.5 truncate">
              理疗过程记录
            </p>
          </div>
        </Link>
      </div>

      {/* 本月项目分布 */}
      {distribution.length > 0 && (
        <Card>
          <CardHeader className="pb-2 md:pb-6">
            <CardTitle className="text-sm md:text-base">
              本月项目分布 (Top 5)
            </CardTitle>
          </CardHeader>
          <CardContent className="pb-3 md:pb-6">
            <div className="space-y-2 md:space-y-2.5">
              {distribution.map((d, idx) => {
                const maxCount = distribution[0]?.count || 1;
                const pct = Math.round((d.count / maxCount) * 100);
                return (
                  <div key={d.serviceItemId} className="space-y-1">
                    <div className="flex items-center justify-between text-xs md:text-sm">
                      <span className="truncate flex-1">
                        {serviceMap.get(d.serviceItemId) ?? `#${d.serviceItemId}`}
                      </span>
                      <Badge variant="secondary" className="ml-2 shrink-0">
                        {d.count} 次
                      </Badge>
                    </div>
                    <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                      {/* ui-style-allow-inline-style: 动态百分比宽度 */}
                      <div
                        className="h-full bg-primary rounded-full transition-all"
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>
      )}

      {/* 移动专属: 底部呼吸区, 避免最后一项贴 Tab Bar */}
      <div className="h-2 md:hidden" aria-hidden="true" />
    </div>
  );
}

