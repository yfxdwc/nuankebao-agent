import { listInteractionsByCustomer } from "@/lib/db/queries/interaction";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { db } from "@/lib/db";
import { interaction } from "@/lib/db/schema";
import { desc } from "drizzle-orm";
import { Phone, MessageCircle, MapPin, Gift, MoreHorizontal } from "lucide-react";
import { formatDate } from "@/lib/utils";
import { cn } from "@/lib/utils";

export const dynamic = "force-dynamic";

const TYPE_META: Record<
  string,
  { label: string; icon: React.ComponentType<{ className?: string }>; tone: string }
> = {
  phone: { label: "电话", icon: Phone, tone: "bg-info-light text-info" },
  wechat: { label: "微信", icon: MessageCircle, tone: "bg-success-light text-success" },
  visit: { label: "到店", icon: MapPin, tone: "bg-danger-light text-danger" },
  holiday_greeting: { label: "节日", icon: Gift, tone: "bg-warning-surface text-warning" },
  other: { label: "其他", icon: MoreHorizontal, tone: "bg-muted text-muted-foreground" },
};

function groupByDate<T extends { createdAt: Date | string }>(items: T[]) {
  const groups = new Map<string, T[]>();
  for (const item of items) {
    const d = new Date(item.createdAt);
    const key = d.toISOString().split("T")[0];
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(item);
  }
  return Array.from(groups.entries()).sort((a, b) => b[0].localeCompare(a[0]));
}

function relativeDay(dateStr: string, today: Date): string {
  const d = new Date(dateStr);
  const diff = Math.floor(
    (today.getTime() - new Date(today.getTime()).setHours(0, 0, 0, 0)) / 86400000
  );
  // 简化: 用 today midnight 和 d midnight 差天数
  const todayMid = new Date(today);
  todayMid.setHours(0, 0, 0, 0);
  const dMid = new Date(d);
  dMid.setHours(0, 0, 0, 0);
  const dayDiff = Math.floor((todayMid.getTime() - dMid.getTime()) / 86400000);
  if (dayDiff === 0) return "今天";
  if (dayDiff === 1) return "昨天";
  if (dayDiff < 7) return `${dayDiff} 天前`;
  return formatDate(dateStr);
}

export default async function InteractionsPage() {
  const recent = await db
    .select()
    .from(interaction)
    .orderBy(desc(interaction.createdAt))
    .limit(50);

  const today = new Date();
  const groups = groupByDate(recent);

  return (
    <div className="space-y-4 md:space-y-6">
      <div>
        <h1 className="text-xl md:text-3xl font-bold tracking-tight">联系记录</h1>
        <p className="text-xs md:text-sm text-muted-foreground mt-0.5 md:mt-1">
          最近 {recent.length} 条 · 按时间倒序
        </p>
      </div>

      {recent.length === 0 ? (
        <div className="rounded-lg border border-dashed py-8 md:py-12 text-center text-muted-foreground text-sm">
          暂无联系记录
        </div>
      ) : (
        <div className="space-y-4 md:space-y-6">
          {groups.map(([dateKey, items]) => (
            <section key={dateKey}>
              {/* 日期标题 (sticky 效果: 移动滑动不丢上下文) */}
              <div className="sticky top-12 md:top-14 z-20 -mx-3 md:mx-0 px-3 md:px-0 py-2 bg-background/95 backdrop-blur">
                <h2 className="text-xs md:text-sm font-medium text-muted-foreground">
                  {relativeDay(dateKey, today)} · {dateKey}
                </h2>
              </div>

              {/* 时间线 (左侧竖线 + 节点圆点) */}
              <ol className="relative space-y-2 md:space-y-3 ml-3 md:ml-4">
                {/* 竖线 (absolute, 从第一个 item 到最后一个) */}
                <div
                  className="absolute left-2.5 md:left-3 top-3 bottom-3 w-px bg-border"
                  aria-hidden="true"
                />
                {items.map((i) => {
                  const meta = TYPE_META[i.type] ?? TYPE_META.other;
                  const Icon = meta.icon;
                  const time = new Date(i.createdAt)
                    .toISOString()
                    .split("T")[1]
                    ?.slice(0, 5); // HH:MM
                  return (
                    <li key={i.id.toString()} className="relative pl-8 md:pl-10">
                      {/* 节点圆点 */}
                      <div
                        className={cn(
                          "absolute left-0 top-1.5 md:top-2 h-5 w-5 md:h-6 md:w-6 rounded-full flex items-center justify-center ring-2 ring-background",
                          meta.tone
                        )}
                        aria-hidden="true"
                      >
                        <Icon className="h-3 w-3 md:h-3.5 md:w-3.5" />
                      </div>
                      {/* 内容 */}
                      <div className="bg-card border rounded-lg p-2.5 md:p-3">
                        <div className="flex items-center justify-between gap-2">
                          <div className="flex items-center gap-2 min-w-0">
                            <span className="text-xs md:text-sm font-medium">
                              {meta.label}
                            </span>
                            <span className="text-xxs md:text-xs text-muted-foreground">
                              客户 #{i.customerId.toString()}
                            </span>
                          </div>
                          <span className="text-xxs md:text-xs text-muted-foreground tabular-nums shrink-0">
                            {time}
                          </span>
                        </div>
                        {i.summaryEncrypted && (
                          <p className="text-xxs md:text-xs text-muted-foreground mt-1 italic">
                            (内容已加密,详情见客户详情页)
                          </p>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ol>
            </section>
          ))}
        </div>
      )}

      <div className="h-16 md:hidden" aria-hidden="true" />
    </div>
  );
}
