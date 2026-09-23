"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/section";
import { cn } from "@/lib/utils";
import { Loader2, Sparkles, RefreshCw, Copy, User, MessageCircle, TrendingDown, BarChart3, ArrowRight } from "lucide-react";

type Scenario = "profile" | "followup" | "repurchase" | "effect";

interface ScenarioMeta {
  value: Scenario;
  label: string;
  desc: string;
  icon: React.ComponentType<{ className?: string }>;
  /** 浅底 token, 不画彩图标底 (原则 5: 颜色是信号, 不是装饰) */
  surface: string;
}

const SCENARIOS: ScenarioMeta[] = [
  {
    value: "profile",
    label: "客户画像",
    desc: "健康趋势 / 偏好 / 风险标签",
    icon: User,
    surface: "bg-brand-surface text-brand",
  },
  {
    value: "followup",
    label: "跟进话术",
    desc: "基于距上次到店 + 性格生成",
    icon: MessageCircle,
    surface: "bg-success-light text-success",
  },
  {
    value: "repurchase",
    label: "复购预测",
    desc: "客户流失风险 + 复购概率",
    icon: TrendingDown,
    surface: "bg-warning-surface text-warning",
  },
  {
    value: "effect",
    label: "效果分析",
    desc: "近 N 次理疗效果趋势",
    icon: BarChart3,
    surface: "bg-info-light text-brand",
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
    <div className="space-y-section-y">
      {/* 场景选择: 2x2 网格 (移动单列 stack), active = 浅底 + 主色, 不画 ring + shadow (反 vibe) */}
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
                "text-left p-3 rounded-md transition-colors min-h-control-lg",
                isActive
                  ? `${s.surface} font-medium`
                  : "bg-surface-subtle text-content-secondary hover:bg-surface-sunken"
              )}
            >
              <div className="flex items-start gap-2">
                <Icon className={cn("h-4 w-4 shrink-0 mt-0.5", isActive ? "" : "text-content-tertiary")} />
                <div className="min-w-0 flex-1">
                  <p className={cn("text-body-lg leading-tight", isActive ? "text-current" : "text-content-primary")}>
                    {s.label}
                  </p>
                  <p className={cn("text-caption mt-0.5 line-clamp-2 leading-snug", isActive ? "opacity-80" : "text-content-tertiary")}>
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
        <Section
          title={`${activeMeta?.label} · 客户 #${customerId}`}
          action={
            data && !loading ? (
              <Button size="sm" variant="ghost" onClick={load}>
                <RefreshCw className="h-3 w-3 mr-1" />
                重新生成
              </Button>
            ) : undefined
          }
        >
          {error && (
            <p className="text-body text-danger bg-danger-surface rounded-md p-2 mb-2">
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
            <div className="flex items-center justify-center gap-2 py-6 text-body text-content-secondary">
              <Loader2 className="h-4 w-4 animate-spin" />
              AI 分析中...
            </div>
          )}

          {data && !loading && <ScenarioResult scenario={scenario} data={data} />}
        </Section>
      )}

      {!scenario && (
        <p className="text-caption text-content-tertiary text-center py-2">
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
            <span className="text-caption text-warning bg-warning-surface px-1.5 py-0.5 rounded">Mock 模式</span>
          )}
          {data.recentRecords?.length > 0 && (
            <span className="text-caption text-content-secondary border border-divider px-1.5 py-0.5 rounded">
              基于 {data.recentRecords.length} 条记录
            </span>
          )}
        </div>
        <div className="bg-surface-subtle rounded-md p-3 text-body-lg text-content-primary whitespace-pre-wrap">
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
            <span className="text-caption text-content-secondary bg-surface-subtle px-1.5 py-0.5 rounded">
              距上次 {data.daysSinceLastVisit} 天
            </span>
          )}
          {data.avgInterval !== null && (
            <span className="text-caption text-content-secondary border border-divider px-1.5 py-0.5 rounded">
              平均 {data.avgInterval} 天复购
            </span>
          )}
        </div>
        <div className="bg-surface-subtle rounded-md p-3 text-body-lg text-content-primary whitespace-pre-wrap">
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
            <span className="text-caption text-warning bg-warning-surface px-1.5 py-0.5 rounded">Mock 模式</span>
          )}
          {data.probability !== undefined && (
            <span className="text-caption text-content-secondary border border-divider px-1.5 py-0.5 rounded">
              复购概率 {Math.round((data.probability ?? 0) * 100)}%
            </span>
          )}
        </div>
        <div className="bg-surface-subtle rounded-md p-3 text-body-lg text-content-primary whitespace-pre-wrap">
          {data.summary || data.aiSummary || JSON.stringify(data, null, 2)}
        </div>
      </div>
    );
  }

  if (scenario === "effect") {
    return (
      <div className="bg-surface-subtle rounded-md p-3 text-body-lg text-content-primary whitespace-pre-wrap">
        {data.summary || data.aiSummary || JSON.stringify(data, null, 2)}
      </div>
    );
  }

  return null;
}