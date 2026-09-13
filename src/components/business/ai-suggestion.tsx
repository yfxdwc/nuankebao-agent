"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Sparkles, Loader2, RefreshCw } from "lucide-react";

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
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Sparkles className="h-4 w-4 text-primary" />
          AI 跟进建议
        </CardTitle>
        <Button
          size="sm"
          onClick={generate}
          disabled={loading}
        >
          {loading ? (
            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
          ) : data ? (
            <RefreshCw className="h-4 w-4 mr-2" />
          ) : (
            <Sparkles className="h-4 w-4 mr-2" />
          )}
          {loading ? "生成中..." : data ? "重新生成" : "生成话术"}
        </Button>
      </CardHeader>
      <CardContent>
        {error && <p className="text-sm text-destructive">{error}</p>}

        {!data && !error && !loading && (
          <p className="text-sm text-muted-foreground">
            点击"生成话术"获取 AI 跟进入口
          </p>
        )}

        {data && (
          <div className="space-y-3">
            <div className="flex flex-wrap gap-2 text-xs">
              {data.daysSinceLastVisit !== null && (
                <Badge variant="secondary">
                  距上次 {data.daysSinceLastVisit} 天
                </Badge>
              )}
              {data.avgInterval !== null && (
                <Badge variant="outline">
                  平均 {data.avgInterval} 天复购
                </Badge>
              )}
              {data.aiMock && (
                <Badge className="bg-yellow-100 text-yellow-800">
                  Mock (未配置 MINIMAX_API_KEY)
                </Badge>
              )}
            </div>
            <div className="bg-muted rounded-md p-4 text-sm whitespace-pre-wrap">
              {data.suggestion}
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => navigator.clipboard.writeText(data.suggestion)}
            >
              复制话术
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}