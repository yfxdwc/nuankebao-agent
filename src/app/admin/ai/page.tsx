import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import { isNull, desc } from "drizzle-orm";
import { PageHeader } from "@/components/ui/page-header";
import { Section } from "@/components/ui/section";
import Link from "next/link";
import { Brain, Sparkles, ChevronRight } from "lucide-react";
import { AIAssistantPanel } from "@/components/business/ai-assistant-panel";
import { cn } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function AIPage({
  searchParams,
}: {
  searchParams: Promise<{ customerId?: string }>;
}) {
  const { customerId: preselected } = await searchParams;

  const customers = await db
    .select({
      id: customer.id,
      name: customer.name,
      createdAt: customer.createdAt,
    })
    .from(customer)
    .where(isNull(customer.deletedAt))
    .orderBy(desc(customer.createdAt))
    .limit(50);

  return (
    <div className="space-y-section-y">
      <PageHeader
        title="AI 助手"
        description="基于客户档案 + 历史记录, AI 生成客户画像 / 跟进话术"
      />

      {/* 客户选择: 移动横滑 chip, 桌面 wrap */}
      {customers.length > 0 && (
        <Section title="选择客户" description={`共 ${customers.length} 位`}>
          <div className="flex md:flex-wrap gap-2 overflow-x-auto pb-1 -mx-1 px-1">
            {customers.map((c) => {
              const isActive = preselected === c.id.toString();
              return (
                <Link
                  key={c.id.toString()}
                  href={`/admin/ai?customerId=${c.id}`}
                  className={cn(
                    "shrink-0 inline-flex items-center gap-1 px-3 py-1.5 rounded-full text-body font-medium transition-colors min-h-control-sm",
                    isActive
                      ? "bg-brand text-brand-foreground"
                      : "bg-surface-subtle text-content-secondary hover:bg-surface-sunken"
                  )}
                >
                  {c.name}
                  {isActive && <ChevronRight className="h-3 w-3" />}
                </Link>
              );
            })}
          </div>
        </Section>
      )}

      {customers.length === 0 && (
        <div className="py-10 text-center text-body text-content-secondary">
          暂无客户, 先在「客户」页添加
        </div>
      )}

      {/* AI 洞察: 选客户才显示, 选前是引导卡 */}
      {preselected ? (
        <Section
          title="AI 客户洞察"
          description={customers.find(c => c.id.toString() === preselected)?.name ?? ""}
          action={<Sparkles className="h-4 w-4 text-brand" />}
        >
          <AIAssistantPanel customerId={preselected} />
        </Section>
      ) : (
        customers.length > 0 && (
          <Section>
            <div className="flex flex-col items-center text-center py-6 px-card-y">
              <Sparkles className="h-8 w-8 text-brand/40 mb-2" />
              <p className="text-body text-content-secondary">
                从上方选择一位客户, AI 自动生成:
              </p>
              <ul className="text-caption text-content-secondary space-y-0.5 mt-2">
                <li>· 客户画像 (健康趋势 / 偏好)</li>
                <li>· 跟进话术 (考虑客户性格 + 距上次到店时间)</li>
                <li>· 风险预警 (流失 / 异常反应)</li>
              </ul>
            </div>
          </Section>
        )
      )}

      <div className="h-16 md:hidden" aria-hidden="true" />
    </div>
  );
}