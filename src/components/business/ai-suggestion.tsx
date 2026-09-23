"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/section";
import { Sparkles, Loader2, RefreshCw, Copy } from "lucide-react";

interface AISuggestionResult {
  customerId: string;
  customerName: string;
  lastVisit: string | null;
  daysSinceLastVisit: number | null;
  avgInterval: number | null;
  reason: string;
  suggestion: string;
  aiMock: boolean;
}

export function AISuggestion({ customerId }: { customerId: string }) {
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<AISuggestionResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function generate() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/ai/follow-up", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ customerId, reason: "复购周期提醒" }),
      });
      if (!res.ok) {
        const d = await res.json();
        throw new Error(d.error || "生成失败");
      }
      const d = await res.json();
      setData(d);
    } catch (err) {
      setError(err instanceof Error ? err.message : "生成失败");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Section
      title="AI 跟进建议"
      action={
        <Button size="sm" onClick={generate} disabled={loading}>
          {loading ? (
            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
          ) : data ? (
            <RefreshCw className="h-4 w-4 mr-2" />
          ) : (
            <Sparkles className="h-4 w-4 mr-2" />
          )}
          {loading ? "生成中..." : data ? "重新生成" : "生成话术"}
        </Button>
      }
    >
      {error && <p className="text-body text-danger bg-danger-surface rounded-md p-2">{error}</p>}

      {!data && !error && !loading && (
        <p className="text-body text-content-secondary">
          点击「生成话术」获取 AI 跟进入口
        </p>
      )}

      {data && (
        <div className="space-y-3">
          <div className="flex flex-wrap gap-1.5 text-caption">
            {data.daysSinceLastVisit !== null && (
              <span className="text-content-secondary bg-surface-subtle px-1.5 py-0.5 rounded">
                距上次 {data.daysSinceLastVisit} 天
              </span>
            )}
            {data.avgInterval !== null && (
              <span className="text-content-secondary border border-divider px-1.5 py-0.5 rounded">
                平均 {data.avgInterval} 天复购
              </span>
            )}
            {data.aiMock && (
              <span className="text-warning bg-warning-surface px-1.5 py-0.5 rounded">
                Mock (未配置 MINIMAX_API_KEY)
              </span>
            )}
          </div>
          <div className="bg-surface-subtle rounded-md p-4 text-body-lg text-content-primary whitespace-pre-wrap">
            {data.suggestion}
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => navigator.clipboard.writeText(data.suggestion)}
          >
            <Copy className="h-3.5 w-3.5 mr-2" />
            复制话术
          </Button>
        </div>
      )}
    </Section>
  );
}