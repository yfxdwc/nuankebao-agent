"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
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
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Sparkles className="h-4 w-4 text-primary" />
          AI 客户画像
        </CardTitle>
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
      </CardHeader>
      <CardContent>
        {error && <p className="text-sm text-destructive">{error}</p>}

        {!data && !error && !loading && (
          <p className="text-sm text-muted-foreground">
            点击"生成画像"获取 AI 客户洞察
          </p>
        )}

        {data && (
          <div className="space-y-3">
            <div className="flex flex-wrap gap-2 text-xs">
              {data.aiMock && (
                <Badge className="bg-yellow-100 text-yellow-800">
                  Mock (未配置 MINIMAX_API_KEY)
                </Badge>
              )}
              {data.recentRecords.length > 0 && (
                <Badge variant="outline">
                  基于 {data.recentRecords.length} 条历史记录
                </Badge>
              )}
            </div>
            <div className="bg-muted rounded-md p-4 text-sm whitespace-pre-wrap">
              {data.aiSummary}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}