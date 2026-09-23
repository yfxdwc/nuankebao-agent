import { listInteractionsByCustomer } from "@/lib/db/queries/interaction";
import { db } from "@/lib/db";
import { interaction } from "@/lib/db/schema";
import { desc } from "drizzle-orm";
import { Phone, MessageCircle, MapPin, Gift, MoreHorizontal } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Section } from "@/components/ui/section";
import { formatDate } from "@/lib/utils";
import { cn } from "@/lib/utils";

export const dynamic = "force-dynamic";

const TYPE_META: Record<
  string,
  { label: string; icon: React.ComponentType<{ className?: string }>; tone: string }
> = {
  phone: { label: "电话", icon: Phone, tone: "bg-info-light text-brand" },
  wechat: { label: "微信", icon: MessageCircle, tone: "bg-success-light text-success" },
  visit: { label: "到店", icon: MapPin, tone: "bg-danger-light text-danger" },
  holiday_greeting: { label: "节日", icon: Gift, tone: "bg-warning-surface text-warning" },
  other: { label: "其他", icon: MoreHorizontal, tone: "bg-surface-subtle text-content-secondary" },
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
    <div className="space-y-section-y">
      <PageHeader
        title="联系记录"
        description={`最近 ${recent.length} 条 · 按时间倒序`}
      />

      {recent.length === 0 ? (
        <div className="py-10 text-center text-body text-content-secondary">
          暂无联系记录
        </div>
      ) : (
        <div className="space-y-section-y">
          {groups.map(([dateKey, items]) => (
            <Section
              key={dateKey}
              title={`${relativeDay(dateKey, today)} · ${dateKey}`}
            >
              {/* 时间线 (左侧竖线 + 节点圆点), 内容用 divide-y 分隔线列表 (无 Card) */}
              <ol className="relative ml-3 md:ml-4">
                {/* 竖线 */}
                <div
                  className="absolute left-2.5 md:left-3 top-3 bottom-3 w-px bg-divider"
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
                    <li
                      key={i.id.toString()}
                      className="relative pl-8 md:pl-10 py-3 first:pt-0 last:pb-0"
                    >
                      {/* 节点圆点 */}
                      <div
                        className={cn(
                          "absolute left-0 top-3 h-5 w-5 md:h-6 md:w-6 rounded-full flex items-center justify-center ring-2 ring-background",
                          meta.tone
                        )}
                        aria-hidden="true"
                      >
                        <Icon className="h-3 w-3 md:h-3.5 md:w-3.5" />
                      </div>
                      {/* 内容 (无 bg-card border 包裹; 同质列表 = divide-y) */}
                      <div className="flex items-center justify-between gap-2">
                        <div className="flex items-center gap-2 min-w-0">
                          <span className="text-body-lg text-content-primary">
                            {meta.label}
                          </span>
                          <span className="text-caption text-content-tertiary tabular-nums">
                            客户 #{i.customerId.toString()}
                          </span>
                        </div>
                        <span className="text-caption text-content-tertiary tabular-nums shrink-0">
                          {time}
                        </span>
                      </div>
                      {i.summaryEncrypted && (
                        <p className="text-caption text-content-tertiary mt-1 italic">
                          (内容已加密,详情见客户详情页)
                        </p>
                      )}
                    </li>
                  );
                })}
              </ol>
            </Section>
          ))}
        </div>
      )}

      <div className="h-16 md:hidden" aria-hidden="true" />
    </div>
  );
}