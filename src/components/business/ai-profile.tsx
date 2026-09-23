"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/section";
import { Sparkles, Loader2, RefreshCw } from "lucide-react";

interface AIProfileResult {
  aiSummary: string;
  aiMock: boolean;
  recentRecords: Array<{
    serviceDate: string;
    serviceItem: string;
    bodyParts: string[];
    feedback: string | null;
  }>;
}

export function AIProfile({ customerId }: { customerId: string }) {
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<AIProfileResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function generate() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/ai/profile/${customerId}`);
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
      title="AI 客户画像"
      action={
        <Button size="sm" onClick={generate} disabled={loading}>
          {loading ? (
            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
          ) : data ? (
            <RefreshCw className="h-4 w-4 mr-2" />
          ) : (
            <Sparkles className="h-4 w-4 mr-2" />
          )}
          {loading ? "生成中..." : data ? "重新生成" : "生成画像"}
        </Button>
      }
    >
      {error && <p className="text-body text-danger bg-danger-surface rounded-md p-2">{error}</p>}

      {!data && !error && !loading && (
        <p className="text-body text-content-secondary">
          点击「生成画像」获取 AI 客户洞察
        </p>
      )}

      {data && (
        <div className="space-y-3">
          <div className="flex flex-wrap gap-1.5 text-caption">
            {data.aiMock && (
              <span className="text-warning bg-warning-surface px-1.5 py-0.5 rounded">
                Mock (未配置 MINIMAX_API_KEY)
              </span>
            )}
            {data.recentRecords.length > 0 && (
              <span className="text-content-secondary border border-divider px-1.5 py-0.5 rounded">
                基于 {data.recentRecords.length} 条历史记录
              </span>
            )}
          </div>
          <div className="bg-surface-subtle rounded-md p-4 text-body-lg text-content-primary whitespace-pre-wrap">
            {data.aiSummary}
          </div>
        </div>
      )}
    </Section>
  );
}