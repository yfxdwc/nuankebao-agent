import Link from "next/link";
import { listFollowUpTasks } from "@/lib/db/queries/follow-up-task";
import { getCustomerById } from "@/lib/db/queries/customer";
import { Card, CardContent } from "@/components/ui/card";
import { FollowUpSwipeableCard } from "@/components/business/follow-up-swipeable-card";
import { cn } from "@/lib/utils";

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

const FILTERS: { value: Filter; label: string; tone: string }[] = [
  { value: "today", label: "今天", tone: "bg-warning-surface text-warning border-warning-light" },
  { value: "week", label: "本周", tone: "bg-info-surface text-info border-info-light" },
  { value: "overdue", label: "逾期", tone: "bg-danger-surface text-danger border-danger-light" },
  { value: "all", label: "全部", tone: "bg-muted text-foreground border-border" },
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

  return (
    <div className="space-y-3 md:space-y-6">
      <div>
        <h1 className="text-xl md:text-3xl font-bold tracking-tight">跟进任务</h1>
        <p className="text-xs md:text-sm text-muted-foreground mt-0.5 md:mt-1">
          {activeFilter === "today" && `今天 ${buckets.today.length} 个待办`}
          {activeFilter === "week" && `本周 ${buckets.week.length} 个待办`}
          {activeFilter === "overdue" && `已逾期 ${buckets.overdue.length} 个 (需立即处理)`}
          {activeFilter === "all" && `全部 ${items.length} 个待跟进`}
        </p>
      </div>

      {/* Filter chips (横向滚动, 移动友好) */}
      <div className="flex gap-2 overflow-x-auto pb-1 -mx-3 px-3 md:mx-0 md:px-0 md:flex-wrap">
        {FILTERS.map((f) => {
          const count =
            f.value === "all" ? items.length : buckets[f.value].length;
          const isActive = activeFilter === f.value;
          return (
            <Link
              key={f.value}
              href={f.value === "today" ? "/admin/follow-ups" : `/admin/follow-ups?filter=${f.value}`}
              className={cn(
                "shrink-0 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs md:text-sm font-medium transition-colors min-h-control-sm",
                isActive
                  ? f.tone + " shadow-sm"
                  : "bg-background text-muted-foreground hover:bg-muted"
              )}
            >
              <span>{f.label}</span>
              <span
                className={cn(
                  "inline-flex items-center justify-center min-w-badge-lg h-5 px-1.5 rounded-full text-micro font-semibold",
                  isActive ? "bg-white/60" : "bg-muted"
                )}
              >
                {count}
              </span>
            </Link>
          );
        })}
      </div>

      {filtered.length === 0 ? (
        <Card>
          <CardContent className="py-8 md:py-12 text-center text-muted-foreground text-sm">
            {activeFilter === "today" && "今天没有待跟进任务 🎉"}
            {activeFilter === "week" && "本周剩余没有待跟进任务"}
            {activeFilter === "overdue" && "没有逾期任务, 保持得很好 ✓"}
            {activeFilter === "all" && "暂无待跟进任务"}
          </CardContent>
        </Card>
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
