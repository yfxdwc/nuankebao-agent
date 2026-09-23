"use client";

// ============================================
// 使用数据看板 (web admin, 主人 2026-09-22 拍「完整全面使用数据收集」)
//
// 数据源: GET /api/admin/usage/{overview,users,events} (admin only, 只出聚合)
// 回答: 谁在用 / 每天用多少 / 哪个功能用得多 / AI 卡片有没有人点 / 漏斗断在哪 / 什么在报错
// ============================================

import { useCallback, useEffect, useState } from "react";
import {
  Activity,
  AlertTriangle,
  ChevronDown,
  ChevronUp,
  MousePointerClick,
  Timer,
  Users,
} from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { useChartColors } from "@/lib/use-theme-colors";

interface UsageOverview {
  days: number;
  totals: {
    events: number;
    users: number;
    sessions: number;
    devices: number;
    activeDays: number;
    avgSessionSec: number;
  };
  daily: Array<{ date: string; events: number; users: number; sessions: number }>;
  topEvents: Array<{
    eventName: string;
    category: string | null;
    count: number;
    users: number;
  }>;
  topScreens: Array<{ screen: string; count: number; users: number }>;
  aiCards: Array<{
    card: string;
    clicks: number;
    ok: number;
    failed: number;
    regenerates: number;
    avgDurationMs: number;
  }>;
  errors: Array<{
    eventName: string;
    label: string;
    count: number;
    users: number;
  }>;
  funnel: {
    customerView: number;
    aiClick: number;
    aiOk: number;
    followUpCreate: number;
    followUpDone: number;
    recordCreate: number;
  };
}

interface UsageUser {
  userId: string;
  name: string | null;
  role: string | null;
  events: number;
  sessions: number;
  daysActive: number;
  lastActive: string | null;
  aiClicks: number;
  customersCreated: number;
  recordsCreated: number;
  followUpsDone: number;
  screenViews: number;
}

interface RawEvent {
  id: string;
  userName: string | null;
  eventName: string;
  category: string | null;
  screen: string | null;
  success: boolean | null;
  errorCode: string | null;
  durationMs: number | null;
  props: unknown;
  appVersion: string | null;
  platform: string | null;
  serverTs: string;
}

const AI_CARD_LABELS: Record<string, string> = {
  profile: "客户画像",
  follow_up: "跟进话术",
  repurchase: "复购预测",
  effect: "效果分析",
};

const CATEGORY_LABELS: Record<string, string> = {
  lifecycle: "启动",
  nav: "页面",
  auth: "登录",
  customer: "客户",
  wellness: "养生",
  followup: "跟进",
  ai: "AI",
  salon: "沙龙",
  relation: "加盟",
  error: "错误",
  perf: "性能",
};

function formatDuration(sec: number): string {
  if (sec <= 0) return "—";
  if (sec < 60) return `${sec} 秒`;
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return s === 0 ? `${m} 分钟` : `${m} 分 ${s} 秒`;
}

function formatDateTime(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return `${d.getMonth() + 1}-${String(d.getDate()).padStart(2, "0")} ${String(
    d.getHours()
  ).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export function UsageDashboard() {
  const c = useChartColors();
  const [days, setDays] = useState(30);
  const [overview, setOverview] = useState<UsageOverview | null>(null);
  const [users, setUsers] = useState<UsageUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showRaw, setShowRaw] = useState(false);
  const [rawEvents, setRawEvents] = useState<RawEvent[]>([]);
  const [rawLoading, setRawLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [ovRes, usRes] = await Promise.all([
        fetch(`/api/admin/usage/overview?days=${days}`, { cache: "no-store" }),
        fetch(`/api/admin/usage/users?days=${days}`, { cache: "no-store" }),
      ]);
      if (ovRes.status === 403) {
        setError("只有管理员能看使用数据 (当前账号不是 admin)");
        return;
      }
      if (!ovRes.ok) throw new Error(`加载失败: HTTP ${ovRes.status}`);
      setOverview((await ovRes.json()) as UsageOverview);
      if (usRes.ok) {
        const body = (await usRes.json()) as { users?: UsageUser[] };
        setUsers(body.users ?? []);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [days]);

  useEffect(() => {
    void load();
  }, [load]);

  const loadRaw = useCallback(async () => {
    setRawLoading(true);
    try {
      const res = await fetch("/api/admin/usage/events?limit=50", {
        cache: "no-store",
      });
      if (res.ok) {
        const body = (await res.json()) as { events?: RawEvent[] };
        setRawEvents(body.events ?? []);
      }
    } finally {
      setRawLoading(false);
    }
  }, []);

  const toggleRaw = () => {
    const next = !showRaw;
    setShowRaw(next);
    if (next && rawEvents.length === 0) void loadRaw();
  };

  if (error) {
    return (
      <div className="rounded-md border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">
        {error}
      </div>
    );
  }

  if (!overview) {
    return (
      <p className="py-12 text-center text-sm text-muted-foreground">
        {loading ? "加载中..." : "暂无数据"}
      </p>
    );
  }

  const t = overview.totals;
  const hasData = t.events > 0;

  return (
    <div className="space-y-6">
      {/* 头部 + 时间范围 */}
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">使用数据</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            真实用户行为 (release APK 上报; 只记 ID/枚举/计数, 无客户隐私内容)
          </p>
        </div>
        <div className="flex gap-2">
          {[7, 30, 90].map((d) => (
            <button
              key={d}
              onClick={() => setDays(d)}
              className={`h-11 rounded-md border px-4 text-sm transition-colors ${
                days === d
                  ? "bg-primary text-primary-foreground border-primary"
                  : "bg-background text-muted-foreground hover:bg-accent"
              }`}
            >
              近 {d} 天
            </button>
          ))}
        </div>
      </div>

      {!hasData && (
        <div className="rounded-md border border-dashed p-6 text-sm text-muted-foreground">
          还没有采集到数据。打开一次新版 APK (release) 并正常使用后, 事件会在 1 分钟内
          上报; 若仍为空, 检查 APK 是否用 <code>--dart-define=NUANKEBAO_TELEMETRY=1</code>
          调试构建 (默认仅 release 采集)。
        </div>
      )}

      {/* 总览卡片 */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium">
              <Users className="h-4 w-4 text-primary" /> 活跃用户
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{t.users}</div>
            <p className="mt-1 text-xs text-muted-foreground">
              {t.devices} 台设备 · {t.activeDays} 个活跃日
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium">
              <Activity className="h-4 w-4 text-primary" /> 事件数
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{t.events}</div>
            <p className="mt-1 text-xs text-muted-foreground">
              近 {days} 天累计
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium">
              <MousePointerClick className="h-4 w-4 text-primary" /> 会话数
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{t.sessions}</div>
            <p className="mt-1 text-xs text-muted-foreground">
              平均每次 {t.sessions > 0 ? Math.round(t.events / t.sessions) : 0} 个事件
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium">
              <Timer className="h-4 w-4 text-primary" /> 平均会话时长
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{formatDuration(t.avgSessionSec)}</div>
            <p className="mt-1 text-xs text-muted-foreground">同一会话首末事件间隔</p>
          </CardContent>
        </Card>
      </div>

      {/* 每日趋势 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">每日活跃 (用户数 / 事件数)</CardTitle>
        </CardHeader>
        <CardContent>
          {overview.daily.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">暂无数据</p>
          ) : (
            <ResponsiveContainer width="100%" height={260}>
              <BarChart
                data={overview.daily.map((d) => ({
                  date: d.date.slice(5),
                  users: d.users,
                  events: d.events,
                }))}
                margin={{ top: 10, right: 20, left: 0, bottom: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke={c.grid} />
                <XAxis dataKey="date" stroke={c.axis} />
                <YAxis allowDecimals={false} stroke={c.axis} />
                <Tooltip
                  contentStyle={{ borderRadius: 6, border: `1px solid ${c.border}`, background: c.surface }}
                />
                <Bar dataKey="users" name="用户" fill={c.series1} radius={[4, 4, 0, 0]} />
                <Bar dataKey="events" name="事件" fill={c.series2} radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        {/* AI 卡片 (核心问题: 有没有人点) */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">AI 卡片使用 (点击 → 成功/失败)</CardTitle>
          </CardHeader>
          <CardContent>
            {overview.aiCards.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted-foreground">
                还没有人点过 AI 卡片
              </p>
            ) : (
              <div className="space-y-3">
                {overview.aiCards.map((c) => (
                  <div key={c.card} className="flex items-center justify-between text-sm">
                    <span className="font-medium">
                      {AI_CARD_LABELS[c.card] ?? c.card}
                    </span>
                    <span className="flex items-center gap-2 text-muted-foreground">
                      <Badge variant="secondary">点击 {c.clicks}</Badge>
                      <Badge className="bg-primary/10 text-primary">成功 {c.ok}</Badge>
                      {c.failed > 0 && (
                        <Badge variant="destructive">失败 {c.failed}</Badge>
                      )}
                      {c.regenerates > 0 && <span>重生成 {c.regenerates}</span>}
                      <span>{c.avgDurationMs > 0 ? `${(c.avgDurationMs / 1000).toFixed(1)}s` : ""}</span>
                    </span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* 漏斗 */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">核心漏斗 (去重用户数)</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {(
                [
                  ["看客户详情", overview.funnel.customerView],
                  ["点 AI 生成", overview.funnel.aiClick],
                  ["AI 出结果", overview.funnel.aiOk],
                  ["建跟进任务", overview.funnel.followUpCreate],
                  ["完成跟进", overview.funnel.followUpDone],
                  ["记养生记录", overview.funnel.recordCreate],
                ] as Array<[string, number]>
              ).map(([label, value]) => {
                const base = Math.max(overview.funnel.customerView, 1);
                return (
                  <div key={label} className="space-y-1">
                    <div className="flex items-center justify-between text-sm">
                      <span>{label}</span>
                      <span className="font-medium">{value} 人</span>
                    </div>
                    <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
                      <div
                        className="h-full rounded-full bg-primary"
                        style={{ width: `${Math.min(100, (value / base) * 100)}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* 用户维度 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">按用户 (谁在用 / 谁几天没用了)</CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {users.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">
              近 {days} 天没有用户活动
            </p>
          ) : (
            <table className="w-full min-w-table text-sm">
              <thead>
                <tr className="border-b text-left text-xs text-muted-foreground">
                  <th className="py-2 pr-3 font-medium">用户</th>
                  <th className="py-2 pr-3 font-medium">最后活跃</th>
                  <th className="py-2 pr-3 font-medium">活跃天</th>
                  <th className="py-2 pr-3 font-medium">事件</th>
                  <th className="py-2 pr-3 font-medium">会话</th>
                  <th className="py-2 pr-3 font-medium">AI 点击</th>
                  <th className="py-2 pr-3 font-medium">建客户</th>
                  <th className="py-2 pr-3 font-medium">养生记录</th>
                  <th className="py-2 font-medium">完成跟进</th>
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <tr key={u.userId} className="border-b last:border-0">
                    <td className="py-3 pr-3">
                      <span className="font-medium">{u.name ?? `#${u.userId}`}</span>
                      {u.role === "admin" && (
                        <Badge variant="outline" className="ml-2">
                          管理员
                        </Badge>
                      )}
                    </td>
                    <td className="py-3 pr-3 text-muted-foreground">
                      {formatDateTime(u.lastActive)}
                    </td>
                    <td className="py-3 pr-3">{u.daysActive}</td>
                    <td className="py-3 pr-3">{u.events}</td>
                    <td className="py-3 pr-3">{u.sessions}</td>
                    <td className="py-3 pr-3">{u.aiClicks}</td>
                    <td className="py-3 pr-3">{u.customersCreated}</td>
                    <td className="py-3 pr-3">{u.recordsCreated}</td>
                    <td className="py-3">{u.followUpsDone}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        {/* 功能使用排行 */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">事件排行 (近 {days} 天)</CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left text-xs text-muted-foreground">
                  <th className="py-2 pr-3 font-medium">事件</th>
                  <th className="py-2 pr-3 font-medium">类别</th>
                  <th className="py-2 pr-3 font-medium">次数</th>
                  <th className="py-2 font-medium">用户</th>
                </tr>
              </thead>
              <tbody>
                {overview.topEvents.slice(0, 15).map((e) => (
                  <tr key={e.eventName} className="border-b last:border-0">
                    <td className="py-2 pr-3 font-mono text-xs">{e.eventName}</td>
                    <td className="py-2 pr-3 text-muted-foreground">
                      {CATEGORY_LABELS[e.category ?? ""] ?? e.category ?? "—"}
                    </td>
                    <td className="py-2 pr-3">{e.count}</td>
                    <td className="py-2">{e.users}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent>
        </Card>

        {/* 错误 + 页面排行 */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <AlertTriangle className="h-4 w-4 text-destructive" /> 报错 Top
            </CardTitle>
          </CardHeader>
          <CardContent>
            {overview.errors.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted-foreground">
                近 {days} 天没有报错 🎉
              </p>
            ) : (
              <div className="space-y-2">
                {overview.errors.map((e) => (
                  <div
                    key={`${e.eventName}-${e.label}`}
                    className="flex items-center justify-between text-sm"
                  >
                    <span className="truncate font-mono text-xs">
                      {e.eventName}: {e.label}
                    </span>
                    <span className="ml-2 shrink-0 text-muted-foreground">
                      {e.count} 次 · {e.users} 人
                    </span>
                  </div>
                ))}
              </div>
            )}
            <div className="mt-4 border-t pt-4">
              <p className="mb-2 text-xs font-medium text-muted-foreground">
                最常访问页面
              </p>
              <div className="space-y-1">
                {overview.topScreens.slice(0, 8).map((s) => (
                  <div key={s.screen} className="flex items-center justify-between text-sm">
                    <span className="font-mono text-xs">{s.screen}</span>
                    <span className="text-muted-foreground">{s.count}</span>
                  </div>
                ))}
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* 原始事件 (排查用) */}
      <Card>
        <CardHeader>
          <button
            onClick={toggleRaw}
            className="flex w-full items-center justify-between text-left"
          >
            <CardTitle className="text-base">最近原始事件 (排查用)</CardTitle>
            {showRaw ? (
              <ChevronUp className="h-4 w-4 text-muted-foreground" />
            ) : (
              <ChevronDown className="h-4 w-4 text-muted-foreground" />
            )}
          </button>
        </CardHeader>
        {showRaw && (
          <CardContent className="overflow-x-auto">
            {rawLoading ? (
              <p className="py-4 text-center text-sm text-muted-foreground">加载中...</p>
            ) : (
              <table className="w-full min-w-table text-xs">
                <thead>
                  <tr className="border-b text-left text-muted-foreground">
                    <th className="py-2 pr-3 font-medium">时间</th>
                    <th className="py-2 pr-3 font-medium">用户</th>
                    <th className="py-2 pr-3 font-medium">事件</th>
                    <th className="py-2 pr-3 font-medium">页面/实体</th>
                    <th className="py-2 pr-3 font-medium">结果</th>
                    <th className="py-2 font-medium">props</th>
                  </tr>
                </thead>
                <tbody>
                  {rawEvents.map((e) => (
                    <tr key={e.id} className="border-b last:border-0">
                      <td className="py-2 pr-3 text-muted-foreground">
                        {formatDateTime(e.serverTs)}
                      </td>
                      <td className="py-2 pr-3">{e.userName ?? "—"}</td>
                      <td className="py-2 pr-3 font-mono">{e.eventName}</td>
                      <td className="py-2 pr-3 font-mono">
                        {e.screen ?? e.errorCode ?? "—"}
                      </td>
                      <td className="py-2 pr-3">
                        {e.success === null ? "—" : e.success ? "✅" : "❌"}
                        {e.durationMs != null ? ` ${e.durationMs}ms` : ""}
                      </td>
                      <td className="py-2 font-mono">
                        {e.props ? JSON.stringify(e.props) : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </CardContent>
        )}
      </Card>
    </div>
  );
}
