import Link from "next/link";
import { listFollowUpTasks } from "@/lib/db/queries/follow-up-task";
import { getCustomerById } from "@/lib/db/queries/customer";
import { PageHeader } from "@/components/ui/page-header";
import { cn } from "@/lib/utils";
import { FollowUpSwipeableCard } from "@/components/business/follow-up-swipeable-card";

export const dynamic = "force-dynamic";

type Filter = "today" | "week" | "overdue" | "all";

function classifyBucket(dueMs: number, now: number): "today" | "week" | "overdue" | "future" {
  if (dueMs < now) return "overdue";
  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  const endOfToday = startOfToday.getTime() + 24 * 3600 * 1000;
  if (dueMs >= startOfToday.getTime() && dueMs < endOfToday) return "today";
  const endOfWeek = startOfToday.getTime() + 7 * 24 * 3600 * 1000;
  if (dueMs < endOfWeek) return "week";
  return "future";
}

const FILTERS: { value: Filter; label: string }[] = [
  { value: "today", label: "今天" },
  { value: "week", label: "本周" },
  { value: "overdue", label: "逾期" },
  { value: "all", label: "全部" },
];

export default async function FollowUpsPage({
  searchParams,
}: {
  searchParams: Promise<{ filter?: string }>;
}) {
  const { filter: filterParam } = await searchParams;
  const activeFilter = (FILTERS.some(f => f.value === filterParam) ? filterParam : "today") as Filter;

  const { items } = await listFollowUpTasks({ status: "pending", limit: 100 });

  // 批量取客户名
  const customerIds = Array.from(new Set(items.map((t) => t.customerId)));
  const customers = await Promise.all(
    customerIds.map((id) => getCustomerById(BigInt(id)))
  );
  const customerMap = new Map(customers.filter(Boolean).map((c) => [c!.id, c!]));

  const now = Date.now();

  // 按 filter 分类 (只往 today/week/overdue 推, all 复用原数组)
  const buckets: Record<"today" | "week" | "overdue", typeof items> = {
    today: [],
    week: [],
    overdue: [],
  };
  for (const t of items) {
    const dueMs = new Date(t.dueAt).getTime();
    if (Number.isNaN(dueMs)) continue;  // 保护 NaN
    const f = classifyBucket(dueMs, now);
    if (f === "future") continue;  // 不属于 today/week/overdue 任一桶
    buckets[f].push(t);
  }
  const filtered: typeof items =
    activeFilter === "all"
      ? items
      : activeFilter === "overdue"
        ? buckets.overdue
        : activeFilter === "week"
          ? buckets.week
          : buckets.today;

  const descriptionText =
    activeFilter === "today" ? `今天 ${buckets.today.length} 个待办` :
    activeFilter === "week" ? `本周 ${buckets.week.length} 个待办` :
    activeFilter === "overdue" ? `已逾期 ${buckets.overdue.length} 个 (需立即处理)` :
    `全部 ${items.length} 个待跟进`;

  return (
    <div className="space-y-section-y">
      <PageHeader
        title="跟进任务"
        description={descriptionText}
      />

      {/* B3: FilterBar + filter chips (FilterChip 是 button; 这里用 Link 实现 URL 切换,
          视觉对齐 chip 规范: active 主色实底 + 反白, inactive 中性浅底, 不要描边) */}
      <div className="flex flex-wrap items-center gap-2 border-b border-divider pb-3">
        {FILTERS.map((f) => {
          const count =
            f.value === "all" ? items.length : buckets[f.value].length;
          const isActive = activeFilter === f.value;
          return (
            <Link
              key={f.value}
              href={f.value === "today" ? "/admin/follow-ups" : `/admin/follow-ups?filter=${f.value}`}
              aria-pressed={isActive}
              className={cn(
                "inline-flex items-center gap-1.5 rounded-chip h-7 px-3 text-caption font-medium",
                "transition-colors min-h-control-sm",
                isActive
                  ? "bg-brand text-brand-foreground"
                  : "bg-surface-subtle text-content-secondary hover:bg-surface-sunken"
              )}
            >
              <span>{f.label}</span>
              <span
                className={cn(
                  "tabular-nums opacity-70",
                  isActive && "text-brand-foreground"
                )}
              >
                ({count})
              </span>
            </Link>
          );
        })}
      </div>

      {filtered.length === 0 ? (
        <div className="py-10 text-center text-body text-content-secondary">
          {activeFilter === "today" && "今天没有待跟进任务 🎉"}
          {activeFilter === "week" && "本周剩余没有待跟进任务"}
          {activeFilter === "overdue" && "没有逾期任务, 保持得很好 ✓"}
          {activeFilter === "all" && "暂无待跟进任务"}
        </div>
      ) : (
        <div className="space-y-2 md:space-y-3">
          {filtered.map((t) => {
            const customer = customerMap.get(t.customerId);
            const dueMs = new Date(t.dueAt).getTime();
            const overdue = dueMs < now;
            return (
              <FollowUpSwipeableCard
                key={t.id}
                task={{
                  id: t.id,
                  customerId: t.customerId.toString(),
                  reason: t.reason,
                  aiSuggestion: t.aiSuggestion,
                  dueAt: typeof t.dueAt === "string" ? t.dueAt : t.dueAt.toISOString(),
                  status: t.status,
                  createdAt: t.createdAt.toString(),
                }}
                customerName={customer?.name ?? null}
                overdue={overdue}
                isDesktop={false}
              />
            );
          })}
        </div>
      )}

      <div className="h-16 md:hidden" aria-hidden="true" />
    </div>
  );
}