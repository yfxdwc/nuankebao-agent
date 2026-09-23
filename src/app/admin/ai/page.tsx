import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import { isNull, desc } from "drizzle-orm";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
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
    <div className="space-y-3 md:space-y-6">
      {/* 标题 (移动小, 桌面大) */}
      <div>
        <h1 className="text-xl md:text-3xl font-bold tracking-tight flex items-center gap-2">
          <Brain className="h-5 w-5 md:h-7 md:w-7 text-primary" />
          AI 助手
        </h1>
        <p className="text-xs md:text-sm text-muted-foreground mt-0.5 md:mt-1">
          基于客户档案 + 历史记录, AI 生成客户画像 / 跟进话术
        </p>
      </div>

      {/* 客户选择: 移动横滑 chip, 桌面 wrap */}
      {customers.length > 0 && (
        <div className="-mx-3 md:mx-0">
          <p className="text-xs text-muted-foreground mb-2 px-3 md:px-0">
            选择客户 ({customers.length})
          </p>
          <div className="flex md:flex-wrap gap-2 overflow-x-auto pb-1 px-3 md:px-0">
            {customers.map((c) => {
              const isActive = preselected === c.id.toString();
              return (
                <Link
                  key={c.id.toString()}
                  href={`/admin/ai?customerId=${c.id}`}
                  className={cn(
                    "shrink-0 inline-flex items-center gap-1 px-3 py-1.5 rounded-full text-sm font-medium transition-colors min-h-control-sm",
                    isActive
                      ? "bg-primary text-primary-foreground"
                      : "bg-muted text-foreground hover:bg-muted/70"
                  )}
                >
                  {c.name}
                  {isActive && <ChevronRight className="h-3 w-3" />}
                </Link>
              );
            })}
          </div>
        </div>
      )}

      {customers.length === 0 && (
        <Card>
          <CardContent className="py-6 px-card-y text-center text-muted-foreground text-sm">
            暂无客户, 先在"客户"页添加
          </CardContent>
        </Card>
      )}

      {/* AI 洞察: 选客户才显示, 选前是引导卡 */}
      {preselected ? (
        <div className="rounded-lg border bg-card overflow-hidden">
          <div className="flex items-center gap-2 px-3 py-2 md:px-4 md:py-3 border-b bg-muted/30">
            <Sparkles className="h-4 w-4 text-primary" />
            <span className="text-sm font-medium">AI 客户洞察</span>
            <Badge variant="outline" className="text-micro ml-auto">
              {customers.find(c => c.id.toString() === preselected)?.name}
            </Badge>
          </div>
          <div className="p-3 md:p-4">
            <AIAssistantPanel customerId={preselected} />
          </div>
        </div>
      ) : (
        customers.length > 0 && (
          <Card className="border-dashed border-primary/30 bg-primary/5">
            <CardContent className="py-4 px-card-y text-center text-sm text-muted-foreground">
              <Sparkles className="h-8 w-8 text-primary/40 mx-auto mb-2" />
              <p>从上方选择一位客户, AI 自动生成:</p>
              <ul className="text-xs space-y-0.5 mt-2 inline-block text-left">
                <li>· 客户画像 (健康趋势 / 偏好)</li>
                <li>· 跟进话术 (考虑客户性格 + 距上次到店时间)</li>
                <li>· 风险预警 (流失 / 异常反应)</li>
              </ul>
            </CardContent>
          </Card>
        )
      )}

      <div className="h-16 md:hidden" aria-hidden="true" />
    </div>
  );
}
