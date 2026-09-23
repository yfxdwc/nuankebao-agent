"use client";

// ============================================
// 使用数据看板 (web admin, 主人 2026-09-22 拍「完整全面使用数据收集」)
//
// 数据源: GET /api/admin/usage/{overview,users,events} (admin only, 只出聚合)
// 回答: 谁在用 / 每天用多少 / 哪个功能用得多 / AI 卡片有没有人点 / 漏斗断在哪 / 什么在报错
//
// B3 重构 (2026-09-23): Card → Section + PageHeader, 去掉 bg-muted 卡片描边
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

import { PageHeader } from "@/components/ui/page-header";
import { Section } from "@/components/ui/section";
import { StatRow, StatGroup } from "@/components/ui/stat-row";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
  TableEmpty,
} from "@/components/ui/data-table";
import { useChartColors } from "@/lib/use-theme-colors";
import { cn } from "@/lib/utils";

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
        setError("只有管理员能看使用数据 (当前账号不可用或不是 admin)");
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
      <div className="rounded-md border border-danger/30 bg-danger-surface p-4 text-body text-danger">
        {error}
      </div>
    );
  }

  if (!overview) {
    return (
      <p className="py-12 text-center text-body text-content-secondary">
        {loading ? "加载中..." : "暂无数据"}
      </p>
    );
  }

  const t = overview.totals;
  const hasData = t.events > 0;

  return (
    <div className="space-y-section-y">
      {/* PageHeader + 时间范围 (右对齐 action) */}
      <PageHeader
        title="使用数据"
        description="真实用户行为 (release APK 上报; 只记 ID/枚举/计数, 无客户隐私内容)"
        actions={
          <div className="flex gap-2">
            {[7, 30, 90].map((d) => (
              <button
                key={d}
                onClick={() => setDays(d)}
                className={cn(
                  "h-11 rounded-md px-4 text-body-lg font-medium transition-colors min-h-control",
                  days === d
                    ? "bg-brand text-brand-foreground"
                    : "bg-surface-subtle text-content-secondary hover:bg-surface-sunken"
                )}
              >
                近 {d} 天
              </button>
            ))}
          </div>
        }
      />

      {!hasData && (
        <div className="rounded-md border border-dashed border-divider p-6 text-body text-content-secondary">
          还没有采集到数据。打开一次新版 APK (release) 并正常使用后, 事件会在 1 分钟内
          上报; 若仍为空, 检查 APK 是否用 <code>--dart-define=NUANKEBAO_TELEMETRY=1</code>
          调试构建 (默认仅 release 采集)。
        </div>
      )}

      {/* 总览: StatGroup (横排, 不画卡片) */}
      <StatGroup title="总览">
        <StatRow
          label={<><Users className="h-3.5 w-3.5 inline mr-1" />活跃用户</>}
          value={t.users}
          hint={`${t.devices} 台设备 · ${t.activeDays} 个活跃日`}
        />
        <StatRow
          label={<><Activity className="h-3.5 w-3.5 inline mr-1" />事件数</>}
          value={t.events}
          hint={`近 ${days} 天累计`}
        />
        <StatRow
          label={<><MousePointerClick className="h-3.5 w-3.5 inline mr-1" />会话数</>}
          value={t.sessions}
          hint={`平均每次 ${t.sessions > 0 ? Math.round(t.events / t.sessions) : 0} 个事件`}
        />
        <StatRow
          label={<><Timer className="h-3.5 w-3.5 inline mr-1" />平均会话时长</>}
          value={formatDuration(t.avgSessionSec)}
          hint="同一会话首末事件间隔"
        />
      </StatGroup>

      {/* 每日趋势 */}
      <Section title="每日活跃 (用户数 / 事件数)">
        {overview.daily.length === 0 ? (
          <p className="py-8 text-center text-body text-content-secondary">暂无数据</p>
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
      </Section>

      <div className="grid gap-section-y lg:grid-cols-2">
        {/* AI 卡片 */}
        <Section title="AI 卡片使用" description="点击 → 成功/失败">
          {overview.aiCards.length === 0 ? (
            <p className="py-6 text-center text-body text-content-secondary">
              还没有人点过 AI 卡片
            </p>
          ) : (
            <ul className="divide-y divide-divider">
              {overview.aiCards.map((c) => (
                <li key={c.card} className="py-2.5 flex items-center justify-between gap-2">
                  <span className="text-body-lg text-content-primary font-medium">
                    {AI_CARD_LABELS[c.card] ?? c.card}
                  </span>
                  <span className="flex items-center gap-2 text-caption text-content-tertiary tabular-nums shrink-0">
                    <span className="bg-surface-subtle px-1.5 py-0.5 rounded">点击 {c.clicks}</span>
                    <span className="bg-brand-surface text-brand px-1.5 py-0.5 rounded">成功 {c.ok}</span>
                    {c.failed > 0 && (
                      <span className="bg-danger-surface text-danger px-1.5 py-0.5 rounded">失败 {c.failed}</span>
                    )}
                    {c.regenerates > 0 && <span>重生成 {c.regenerates}</span>}
                    {c.avgDurationMs > 0 && (
                      <span className="text-content-tertiary">
                        {(c.avgDurationMs / 1000).toFixed(1)}s
                      </span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Section>

        {/* 漏斗 */}
        <Section title="核心漏斗" description="去重用户数">
          <ul className="space-y-3">
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
                <li key={label} className="space-y-1">
                  <div className="flex items-center justify-between text-body-lg">
                    <span className="text-content-secondary">{label}</span>
                    <span className="font-medium tabular-nums">{value} 人</span>
                  </div>
                  <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface-sunken">
                    <div
                      className="h-full rounded-full bg-brand"
                      style={{ width: `${Math.min(100, (value / base) * 100)}%` }}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
        </Section>
      </div>

      {/* 用户维度 (Table, B 档标准) */}
      <Section title="按用户" description="谁在用 / 谁几天没用了">
        {users.length === 0 ? (
          <p className="py-6 text-center text-body text-content-secondary">
            近 {days} 天没有用户活动
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>用户</TableHead>
                <TableHead>最后活跃</TableHead>
                <TableHead align="right">活跃天</TableHead>
                <TableHead align="right">事件</TableHead>
                <TableHead align="right">会话</TableHead>
                <TableHead align="right">AI 点击</TableHead>
                <TableHead align="right">建客户</TableHead>
                <TableHead align="right">养生记录</TableHead>
                <TableHead align="right">完成跟进</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {users.map((u) => (
                <TableRow key={u.userId}>
                  <TableCell>
                    <span className="font-medium">{u.name ?? `#${u.userId}`}</span>
                    {u.role === "admin" && (
                      <span className="ml-2 text-caption text-content-tertiary border border-divider px-1.5 py-0.5 rounded">
                        管理员
                      </span>
                    )}
                  </TableCell>
                  <TableCell className="text-content-secondary">
                    {formatDateTime(u.lastActive)}
                  </TableCell>
                  <TableCell align="right">{u.daysActive}</TableCell>
                  <TableCell align="right">{u.events}</TableCell>
                  <TableCell align="right">{u.sessions}</TableCell>
                  <TableCell align="right">{u.aiClicks}</TableCell>
                  <TableCell align="right">{u.customersCreated}</TableCell>
                  <TableCell align="right">{u.recordsCreated}</TableCell>
                  <TableCell align="right">{u.followUpsDone}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Section>

      <div className="grid gap-section-y lg:grid-cols-2">
        {/* 事件排行 */}
        <Section title={`事件排行 (近 ${days} 天)`}>
          {overview.topEvents.length === 0 ? (
            <p className="py-6 text-center text-body text-content-secondary">
              近 {days} 天没有事件
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>事件</TableHead>
                  <TableHead>类别</TableHead>
                  <TableHead align="right">次数</TableHead>
                  <TableHead align="right">用户</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {overview.topEvents.slice(0, 15).map((e) => (
                  <TableRow key={e.eventName}>
                    <TableCell className="font-mono text-caption">{e.eventName}</TableCell>
                    <TableCell className="text-content-secondary">
                      {CATEGORY_LABELS[e.category ?? ""] ?? e.category ?? "—"}
                    </TableCell>
                    <TableCell align="right">{e.count}</TableCell>
                    <TableCell align="right">{e.users}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Section>

        {/* 报错 + 页面排行 */}
        <Section
          title="报错 Top"
          action={
            <AlertTriangle className="h-4 w-4 text-danger" />
          }
        >
          {overview.errors.length === 0 ? (
            <p className="py-6 text-center text-body text-content-secondary">
              近 {days} 天没有报错 🎉
            </p>
          ) : (
            <ul className="divide-y divide-divider">
              {overview.errors.map((e) => (
                <li key={`${e.eventName}-${e.label}`} className="py-2.5 flex items-center justify-between gap-2">
                  <span className="truncate font-mono text-caption text-content-primary">
                    {e.eventName}: {e.label}
                  </span>
                  <span className="ml-2 shrink-0 text-caption text-content-tertiary tabular-nums">
                    {e.count} 次 · {e.users} 人
                  </span>
                </li>
              ))}
            </ul>
          )}
          <div className="mt-section-y pt-section-y border-t border-divider">
            <p className="mb-2 text-caption font-medium text-content-tertiary">
              最常访问页面
            </p>
            <ul className="divide-y divide-divider">
              {overview.topScreens.slice(0, 8).map((s) => (
                <li key={s.screen} className="py-2 flex items-center justify-between">
                  <span className="font-mono text-caption text-content-primary">
                    {s.screen}
                  </span>
                  <span className="text-caption text-content-tertiary tabular-nums">
                    {s.count}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </Section>
      </div>

      {/* 原始事件 (折叠, 默认隐藏) */}
      <Section
        title="最近原始事件 (排查用)"
        action={
          <button
            onClick={toggleRaw}
            className="text-content-secondary hover:text-content-primary"
          >
            {showRaw ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>
        }
      >
        {showRaw && (
          rawLoading ? (
            <p className="py-4 text-center text-body text-content-secondary">加载中...</p>
          ) : rawEvents.length === 0 ? (
            <TableEmpty
              colSpan={6}
              title="还没有原始事件"
              description="近 7 天 release APK 没上报过事件 (可能没真机)"
            />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>时间</TableHead>
                  <TableHead>用户</TableHead>
                  <TableHead>事件</TableHead>
                  <TableHead>页面/实体</TableHead>
                  <TableHead>结果</TableHead>
                  <TableHead>props</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rawEvents.map((e) => (
                  <TableRow key={e.id}>
                    <TableCell className="text-content-secondary">
                      {formatDateTime(e.serverTs)}
                    </TableCell>
                    <TableCell>{e.userName ?? "—"}</TableCell>
                    <TableCell className="font-mono">{e.eventName}</TableCell>
                    <TableCell className="font-mono">
                      {e.screen ?? e.errorCode ?? "—"}
                    </TableCell>
                    <TableCell>
                      {e.success === null ? "—" : e.success ? "✅" : "❌"}
                      {e.durationMs != null ? ` ${e.durationMs}ms` : ""}
                    </TableCell>
                    <TableCell className="font-mono">
                      {e.props ? JSON.stringify(e.props) : "—"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )
        )}
      </Section>
    </div>
  );
}