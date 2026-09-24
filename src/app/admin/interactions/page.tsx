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
        /* B3b: 统一行列表 — divide-y 分隔线 (与 customers/wellness-records/follow-ups 同一套);
           原 timeline 视觉改为行内 icon leading element (小图标 + 主行 + 副时间), 保留分组标题 */
        <div className="space-y-section-y">
          {groups.map(([dateKey, items]) => (
            <Section
              key={dateKey}
              title={`${relativeDay(dateKey, today)} · ${dateKey}`}
            >
              <ul className="divide-y divide-divider">
                {items.map((i) => {
                  const meta = TYPE_META[i.type] ?? TYPE_META.other;
                  const Icon = meta.icon;
                  const time = new Date(i.createdAt)
                    .toISOString()
                    .split("T")[1]
                    ?.slice(0, 5); // HH:MM
                  return (
                    <li key={i.id.toString()} className="py-2 min-h-row">
                      <div className="flex items-center gap-3">
                        {/* 行内 icon leading (替代原 timeline 竖线 + 圆点) */}
                        <div
                          className={cn(
                            "h-9 w-9 rounded-full flex items-center justify-center shrink-0",
                            meta.tone
                          )}
                          aria-hidden="true"
                        >
                          <Icon className="h-4 w-4" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between gap-2">
                            <span className="text-body-lg text-content-primary truncate">
                              {meta.label}
                              <span className="text-caption text-content-tertiary ml-1.5 tabular-nums">
                                客户 #{i.customerId.toString()}
                              </span>
                            </span>
                            <span className="text-caption text-content-tertiary tabular-nums shrink-0">
                              {time}
                            </span>
                          </div>
                          {i.summaryEncrypted && (
                            <p className="text-caption text-content-tertiary mt-0.5 italic line-clamp-1">
                              (内容已加密,详情见客户详情页)
                            </p>
                          )}
                        </div>
                      </div>
                    </li>
                  );
                })}
              </ul>
            </Section>
          ))}
        </div>
      )}

      <div className="h-16 md:hidden" aria-hidden="true" />
    </div>
  );
}