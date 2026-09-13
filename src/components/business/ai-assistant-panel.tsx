"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { Loader2, Sparkles, RefreshCw, Copy, User, MessageCircle, TrendingDown, BarChart3, ArrowRight } from "lucide-react";

type Scenario = "profile" | "followup" | "repurchase" | "effect";

interface ScenarioMeta {
  value: Scenario;
  label: string;
  desc: string;
  icon: React.ComponentType<{ className?: string }>;
  tone: string;
}

const SCENARIOS: ScenarioMeta[] = [
  {
    value: "profile",
    label: "客户画像",
    desc: "健康趋势 / 偏好 / 风险标签",
    icon: User,
    tone: "from-blue-500/10 to-blue-500/5 text-blue-700 border-blue-200",
  },
  {
    value: "followup",
    label: "跟进话术",
    desc: "基于距上次到店 + 性格生成",
    icon: MessageCircle,
    tone: "from-emerald-500/10 to-emerald-500/5 text-emerald-700 border-emerald-200",
  },
  {
    value: "repurchase",
    label: "复购预测",
    desc: "客户流失风险 + 复购概率",
    icon: TrendingDown,
    tone: "from-rose-500/10 to-rose-500/5 text-rose-700 border-rose-200",
  },
  {
    value: "effect",
    label: "效果分析",
    desc: "近 N 次理疗效果趋势",
    icon: BarChart3,
    tone: "from-amber-500/10 to-amber-500/5 text-amber-700 border-amber-200",
  },
];

interface AIAssistantPanelProps {
  customerId: string;
}

export function AIAssistantPanel({ customerId }: AIAssistantPanelProps) {
  const [scenario, setScenario] = useState<Scenario | null>(null);
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    if (!scenario) return;
    setLoading(true);
    setError(null);
    setData(null);
    try {
      let url: string;
      let method: "GET" | "POST" = "GET";
      let body: string | undefined;

      switch (scenario) {
        case "profile":
          url = `/api/ai/profile/${customerId}`;
          break;
        case "followup":
          url = `/api/ai/follow-up`;
          method = "POST";
          body = JSON.stringify({ customerId });
          break;
        case "repurchase":
          url = `/api/ai/repurchase-prediction/${customerId}`;
          break;
        case "effect":
          url = `/api/ai/effect-analysis/${customerId}`;
          break;
      }

      const res = await fetch(url, {
        method,
        headers: method === "POST" ? { "Content-Type": "application/json" } : undefined,
        body,
      });
      if (!res.ok) {
        const d = await res.json().catch(() => ({}));
        throw new Error(d.error || `生成失败 (HTTP ${res.status})`);
      }
      setData(await res.json());
    } catch (err) {
      setError(err instanceof Error ? err.message : "生成失败");
    } finally {
      setLoading(false);
    }
  }

  // 切场景时清空旧数据 (避免不同 scenario 数据混淆)
  function pickScenario(s: Scenario) {
    if (s === scenario) return;  // 同一场景不动
    setScenario(s);
    setData(null);
    setError(null);
  }

  const activeMeta = SCENARIOS.find((s) => s.value === scenario);

  return (
    <div className="space-y-3 md:space-y-4">
      {/* 场景选择: 2x2 卡片 (移动单列 stack) */}
      <div className="grid grid-cols-2 gap-2 md:gap-3">
        {SCENARIOS.map((s) => {
          const Icon = s.icon;
          const isActive = scenario === s.value;
          return (
            <button
              key={s.value}
              type="button"
              onClick={() => pickScenario(s.value)}
              className={cn(
                "text-left p-2.5 md:p-3 rounded-lg border transition-all",
                "active:scale-[0.98] min-h-[68px] md:min-h-0",
                isActive
                  ? `bg-gradient-to-br ${s.tone} ring-2 ring-primary/30 shadow-sm`
                  : "bg-card border-border hover:bg-muted/50"
              )}
            >
              <div className="flex items-start gap-2">
                <div
                  className={cn(
                    "h-7 w-7 md:h-8 md:w-8 rounded-md flex items-center justify-center shrink-0",
                    isActive ? "bg-current/10" : "bg-muted"
                  )}
                >
                  <Icon className={cn("h-3.5 w-3.5 md:h-4 md:w-4", isActive ? "" : "text-muted-foreground")} />
                </div>
                <div className="min-w-0 flex-1">
                  <p
                    className={cn(
                      "text-xs md:text-sm font-medium leading-tight",
                      isActive ? "" : "text-foreground"
                    )}
                  >
                    {s.label}
                  </p>
                  <p className="text-[10px] md:text-xs text-muted-foreground mt-0.5 line-clamp-2 leading-snug">
                    {s.desc}
                  </p>
                </div>
              </div>
            </button>
          );
        })}
      </div>

      {/* 选场景后才显示运行区 */}
      {scenario && (
        <div className="rounded-lg border bg-muted/30 p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between gap-2">
            <div className="flex items-center gap-2 min-w-0">
              {activeMeta && <activeMeta.icon className="h-4 w-4 text-primary shrink-0" />}
              <span className="text-sm font-medium truncate">
                {activeMeta?.label} · 客户 #{customerId}
              </span>
            </div>
            {data && !loading && (
              <Button
                size="sm"
                variant="ghost"
                onClick={load}
                className="h-8 px-2 text-xs"
              >
                <RefreshCw className="h-3 w-3 mr-1" />
                重新生成
              </Button>
            )}
          </div>

          {error && (
            <p className="text-sm text-destructive bg-destructive/10 rounded-md p-2">
              {error}
            </p>
          )}

          {!data && !loading && !error && (
            <Button onClick={load} className="w-full h-11">
              <Sparkles className="h-4 w-4 mr-2" />
              生成 {activeMeta?.label}
              <ArrowRight className="h-4 w-4 ml-2" />
            </Button>
          )}

          {loading && (
            <div className="flex items-center justify-center gap-2 py-6 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" />
              AI 分析中...
            </div>
          )}

          {data && !loading && <ScenarioResult scenario={scenario} data={data} />}
        </div>
      )}

      {!scenario && (
        <p className="text-xs text-muted-foreground text-center py-2">
          ↑ 选择一个分析场景开始
        </p>
      )}
    </div>
  );
}

function ScenarioResult({ scenario, data }: { scenario: Scenario; data: any }) {
  if (scenario === "profile") {
    return (
      <div className="space-y-2">
        <div className="flex flex-wrap gap-1.5">
          {data.aiMock && (
            <Badge className="bg-yellow-100 text-yellow-800 text-[10px]">Mock 模式</Badge>
          )}
          {data.recentRecords?.length > 0 && (
            <Badge variant="outline" className="text-[10px]">
              基于 {data.recentRecords.length} 条记录
            </Badge>
          )}
        </div>
        <div className="bg-card rounded-md p-3 text-sm whitespace-pre-wrap border">
          {data.aiSummary}
        </div>
      </div>
    );
  }

  if (scenario === "followup") {
    return (
      <div className="space-y-2">
        <div className="flex flex-wrap gap-1.5">
          {data.daysSinceLastVisit !== null && (
            <Badge variant="secondary" className="text-[10px]">
              距上次 {data.daysSinceLastVisit} 天
            </Badge>
          )}
          {data.avgInterval !== null && (
            <Badge variant="outline" className="text-[10px]">
              平均 {data.avgInterval} 天复购
            </Badge>
          )}
        </div>
        <div className="bg-card rounded-md p-3 text-sm whitespace-pre-wrap border">
          {data.suggestion}
        </div>
        <Button
          size="sm"
          variant="outline"
          onClick={() => navigator.clipboard.writeText(data.suggestion)}
          className="w-full h-10"
        >
          <Copy className="h-3.5 w-3.5 mr-2" />
          复制话术
        </Button>
      </div>
    );
  }

  if (scenario === "repurchase") {
    return (
      <div className="space-y-2">
        <div className="flex flex-wrap gap-1.5">
          {data.aiMock && (
            <Badge className="bg-yellow-100 text-yellow-800 text-[10px]">Mock 模式</Badge>
          )}
          {data.probability !== undefined && (
            <Badge variant="outline" className="text-[10px]">
              复购概率 {Math.round((data.probability ?? 0) * 100)}%
            </Badge>
          )}
        </div>
        <div className="bg-card rounded-md p-3 text-sm whitespace-pre-wrap border">
          {data.summary || data.aiSummary || JSON.stringify(data, null, 2)}
        </div>
      </div>
    );
  }

  if (scenario === "effect") {
    return (
      <div className="space-y-2">
        <div className="bg-card rounded-md p-3 text-sm whitespace-pre-wrap border">
          {data.summary || data.aiSummary || JSON.stringify(data, null, 2)}
        </div>
      </div>
    );
  }

  return null;
}
