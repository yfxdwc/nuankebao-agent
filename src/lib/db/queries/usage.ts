// ============================================
// 用量事件读写 + 聚合查询
//
// 读侧两条路:
//   1. API (admin only) → 只出聚合 (getUsageOverview / getUsageUsers / listRecentUsageEvents)
//   2. 服务器脚本 (scripts/usage-report.ts) → 可直读原始事件
//
// 时区: 日报/活跃天一律按 Asia/Shanghai 切 (部署在中国, 服务器可能 UTC)
// ============================================

import { and, desc, eq, sql, type SQL } from "drizzle-orm";

import { db } from "@/lib/db";
import { usageEvent, user as userTable } from "@/lib/db/schema";
import type {
  SanitizedDevice,
  SanitizedUsageEvent,
} from "@/lib/usage/sanitize";

const TZ = sql`AT TIME ZONE 'Asia/Shanghai'`;

function scopeDays(days: number): SQL {
  return sql`server_ts >= NOW() - (${days}::int * INTERVAL '1 day')`;
}

// ============================================
// 写
// ============================================

/**
 * 批量写入 (幂等: event_id 冲突跳过; 批内重复先去重)
 * @returns 实际写入行数
 */
export async function insertUsageEvents(
  userId: bigint,
  device: SanitizedDevice,
  events: SanitizedUsageEvent[]
): Promise<number> {
  if (events.length === 0) return 0;

  // 批内去重 (同一次 flush 里若重发同一 event_id, 同语句内冲突会报错)
  const seen = new Set<string>();
  const unique = events.filter((e) => {
    if (seen.has(e.eventId)) return false;
    seen.add(e.eventId);
    return true;
  });

  const rows = unique.map((e) => ({
    eventId: e.eventId,
    userId,
    deviceId: device.deviceId,
    sessionId: e.sessionId,
    eventName: e.eventName,
    category: e.category,
    screen: e.screen,
    entityType: e.entityType,
    entityId: e.entityId,
    success: e.success,
    errorCode: e.errorCode,
    durationMs: e.durationMs,
    props: e.props,
    appVersion: device.appVersion,
    platform: device.platform,
    osVersion: device.osVersion,
    deviceModel: device.deviceModel,
    clientTs: e.clientTs,
  }));

  const inserted = await db
    .insert(usageEvent)
    .values(rows)
    .onConflictDoNothing({ target: usageEvent.eventId })
    .returning({ id: usageEvent.id });

  return inserted.length;
}

/**
 * 保留期清理: 删除 N 天前的原始事件
 * @returns 删除行数
 */
export async function purgeUsageEvents(days: number): Promise<number> {
  const rows = await db.execute(sql`
    DELETE FROM usage_event
    WHERE server_ts < NOW() - (${days}::int * INTERVAL '1 day')
    RETURNING id
  `);
  return (rows as unknown as unknown[]).length;
}

// ============================================
// 读 (聚合)
// ============================================

export interface UsageOverview {
  days: number;
  totals: {
    events: number;
    users: number;
    sessions: number;
    devices: number;
    activeDays: number;
    avgSessionSec: number;
  };
  daily: Array<{
    date: string;
    events: number;
    users: number;
    sessions: number;
  }>;
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

export async function getUsageOverview(days: number): Promise<UsageOverview> {
  const scope = scopeDays(days);

  const [totalsRows, dailyRows, topEventRows, topScreenRows, aiRows, errorRows, funnelRows, sessionRows] =
    await Promise.all([
      db.execute<{
        events: number;
        users: number;
        sessions: number;
        devices: number;
        active_days: number;
      }>(sql`
        SELECT
          count(*)::int AS events,
          count(DISTINCT user_id)::int AS users,
          count(DISTINCT session_id)::int AS sessions,
          count(DISTINCT device_id)::int AS devices,
          count(DISTINCT to_char(server_ts ${TZ}, 'YYYY-MM-DD'))::int AS active_days
        FROM usage_event
        WHERE ${scope}
      `),
      db.execute<{
        date: string;
        events: number;
        users: number;
        sessions: number;
      }>(sql`
        SELECT
          to_char(server_ts ${TZ}, 'YYYY-MM-DD') AS date,
          count(*)::int AS events,
          count(DISTINCT user_id)::int AS users,
          count(DISTINCT session_id)::int AS sessions
        FROM usage_event
        WHERE ${scope}
        GROUP BY 1
        ORDER BY 1
      `),
      db.execute<{
        event_name: string;
        category: string | null;
        count: number;
        users: number;
      }>(sql`
        SELECT
          event_name,
          max(category) AS category,
          count(*)::int AS count,
          count(DISTINCT user_id)::int AS users
        FROM usage_event
        WHERE ${scope}
        GROUP BY event_name
        ORDER BY count DESC
        LIMIT 30
      `),
      db.execute<{ screen: string; count: number; users: number }>(sql`
        SELECT
          screen,
          count(*)::int AS count,
          count(DISTINCT user_id)::int AS users
        FROM usage_event
        WHERE ${scope} AND event_name = 'screen_view' AND screen IS NOT NULL
        GROUP BY screen
        ORDER BY count DESC
        LIMIT 20
      `),
      db.execute<{
        card: string;
        clicks: number;
        ok: number;
        failed: number;
        regenerates: number;
        avg_duration_ms: number;
      }>(sql`
        SELECT
          props->>'card' AS card,
          count(*) FILTER (WHERE event_name = 'ai_generate_click')::int AS clicks,
          count(*) FILTER (WHERE event_name = 'ai_generate_result' AND success)::int AS ok,
          count(*) FILTER (WHERE event_name = 'ai_generate_result' AND success IS FALSE)::int AS failed,
          count(*) FILTER (WHERE event_name = 'ai_regenerate')::int AS regenerates,
          coalesce(round(avg(duration_ms) FILTER (WHERE event_name = 'ai_generate_result'))::int, 0) AS avg_duration_ms
        FROM usage_event
        WHERE ${scope}
          AND event_name IN ('ai_generate_click', 'ai_generate_result', 'ai_regenerate')
          AND props->>'card' IS NOT NULL
        GROUP BY 1
        ORDER BY clicks DESC, ok DESC
      `),
      db.execute<{
        event_name: string;
        label: string;
        count: number;
        users: number;
      }>(sql`
        SELECT
          event_name,
          coalesce(error_code, props->>'path', 'unknown') AS label,
          count(*)::int AS count,
          count(DISTINCT user_id)::int AS users
        FROM usage_event
        WHERE ${scope} AND event_name IN ('api_error', 'ui_error')
        GROUP BY 1, 2
        ORDER BY count DESC
        LIMIT 15
      `),
      db.execute<{
        customer_view: number;
        ai_click: number;
        ai_ok: number;
        follow_up_create: number;
        follow_up_done: number;
        record_create: number;
      }>(sql`
        SELECT
          count(DISTINCT user_id) FILTER (WHERE event_name = 'screen_view' AND screen LIKE '/customers/%')::int AS customer_view,
          count(DISTINCT user_id) FILTER (WHERE event_name = 'ai_generate_click')::int AS ai_click,
          count(DISTINCT user_id) FILTER (WHERE event_name = 'ai_generate_result' AND success)::int AS ai_ok,
          count(DISTINCT user_id) FILTER (WHERE event_name = 'follow_up_create')::int AS follow_up_create,
          count(DISTINCT user_id) FILTER (WHERE event_name = 'follow_up_done')::int AS follow_up_done,
          count(DISTINCT user_id) FILTER (WHERE event_name = 'record_create')::int AS record_create
        FROM usage_event
        WHERE ${scope}
      `),
      db.execute<{ avg_session_sec: number }>(sql`
        SELECT coalesce(round(avg(span_sec))::int, 0) AS avg_session_sec
        FROM (
          SELECT extract(EPOCH FROM (max(server_ts) - min(server_ts))) AS span_sec
          FROM usage_event
          WHERE ${scope} AND session_id IS NOT NULL
          GROUP BY session_id
        ) t
      `),
    ]);

  const totals = (
    totalsRows as unknown as Array<{
      events: number;
      users: number;
      sessions: number;
      devices: number;
      active_days: number;
    }>
  )[0];
  const funnelRow = (
    funnelRows as unknown as Array<{
      customer_view: number;
      ai_click: number;
      ai_ok: number;
      follow_up_create: number;
      follow_up_done: number;
      record_create: number;
    }>
  )[0];
  const sessionRow = (
    sessionRows as unknown as Array<{ avg_session_sec: number }>
  )[0];

  return {
    days,
    totals: {
      events: Number(totals?.events ?? 0),
      users: Number(totals?.users ?? 0),
      sessions: Number(totals?.sessions ?? 0),
      devices: Number(totals?.devices ?? 0),
      activeDays: Number(totals?.active_days ?? 0),
      avgSessionSec: Number(sessionRow?.avg_session_sec ?? 0),
    },
    daily: (
      dailyRows as unknown as Array<{
        date: string;
        events: number;
        users: number;
        sessions: number;
      }>
    ).map((r) => ({
      date: r.date,
      events: Number(r.events),
      users: Number(r.users),
      sessions: Number(r.sessions),
    })),
    topEvents: (
      topEventRows as unknown as Array<{
        event_name: string;
        category: string | null;
        count: number;
        users: number;
      }>
    ).map((r) => ({
      eventName: r.event_name,
      category: r.category,
      count: Number(r.count),
      users: Number(r.users),
    })),
    topScreens: (
      topScreenRows as unknown as Array<{
        screen: string;
        count: number;
        users: number;
      }>
    ).map((r) => ({
      screen: r.screen,
      count: Number(r.count),
      users: Number(r.users),
    })),
    aiCards: (
      aiRows as unknown as Array<{
        card: string;
        clicks: number;
        ok: number;
        failed: number;
        regenerates: number;
        avg_duration_ms: number;
      }>
    ).map((r) => ({
      card: r.card,
      clicks: Number(r.clicks),
      ok: Number(r.ok),
      failed: Number(r.failed),
      regenerates: Number(r.regenerates),
      avgDurationMs: Number(r.avg_duration_ms),
    })),
    errors: (
      errorRows as unknown as Array<{
        event_name: string;
        label: string;
        count: number;
        users: number;
      }>
    ).map((r) => ({
      eventName: r.event_name,
      label: r.label,
      count: Number(r.count),
      users: Number(r.users),
    })),
    funnel: {
      customerView: Number(funnelRow?.customer_view ?? 0),
      aiClick: Number(funnelRow?.ai_click ?? 0),
      aiOk: Number(funnelRow?.ai_ok ?? 0),
      followUpCreate: Number(funnelRow?.follow_up_create ?? 0),
      followUpDone: Number(funnelRow?.follow_up_done ?? 0),
      recordCreate: Number(funnelRow?.record_create ?? 0),
    },
  };
}

export interface UsageUserRow {
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

/** 每个真实用户的使用画像 (谁在用 / 用多少 / 最后一次什么时候) */
export async function getUsageUsers(days: number): Promise<UsageUserRow[]> {
  const rows = await db.execute<{
    user_id: string;
    name: string | null;
    role: string | null;
    events: number;
    sessions: number;
    days_active: number;
    last_active: Date | string | null;
    ai_clicks: number;
    customers_created: number;
    records_created: number;
    follow_ups_done: number;
    screen_views: number;
  }>(sql`
    SELECT
      e.user_id::text AS user_id,
      u.name AS name,
      u.role::text AS role,
      count(*)::int AS events,
      count(DISTINCT e.session_id)::int AS sessions,
      count(DISTINCT to_char(e.server_ts ${TZ}, 'YYYY-MM-DD'))::int AS days_active,
      max(e.server_ts) AS last_active,
      count(*) FILTER (WHERE e.event_name = 'ai_generate_click')::int AS ai_clicks,
      count(*) FILTER (WHERE e.event_name = 'customer_create')::int AS customers_created,
      count(*) FILTER (WHERE e.event_name = 'record_create')::int AS records_created,
      count(*) FILTER (WHERE e.event_name = 'follow_up_done')::int AS follow_ups_done,
      count(*) FILTER (WHERE e.event_name = 'screen_view')::int AS screen_views
    FROM usage_event e
    LEFT JOIN "user" u ON u.id = e.user_id
    WHERE e.server_ts >= NOW() - (${days}::int * INTERVAL '1 day')
    GROUP BY e.user_id, u.name, u.role
    ORDER BY last_active DESC NULLS LAST
  `);

  return (
    rows as unknown as Array<{
      user_id: string;
      name: string | null;
      role: string | null;
      events: number;
      sessions: number;
      days_active: number;
      last_active: Date | string | null;
      ai_clicks: number;
      customers_created: number;
      records_created: number;
      follow_ups_done: number;
      screen_views: number;
    }>
  ).map((r) => ({
    userId: String(r.user_id),
    name: r.name,
    role: r.role,
    events: Number(r.events),
    sessions: Number(r.sessions),
    daysActive: Number(r.days_active),
    lastActive: r.last_active ? new Date(r.last_active).toISOString() : null,
    aiClicks: Number(r.ai_clicks),
    customersCreated: Number(r.customers_created),
    recordsCreated: Number(r.records_created),
    followUpsDone: Number(r.follow_ups_done),
    screenViews: Number(r.screen_views),
  }));
}

/** 最近原始事件 (admin 调试用; 默认只给人看, 不落任何其他表) */
export async function listRecentUsageEvents(opts: {
  limit?: number;
  userId?: bigint;
  eventName?: string;
}): Promise<
  Array<{
    id: string;
    userId: string | null;
    userName: string | null;
    eventName: string;
    category: string | null;
    screen: string | null;
    entityType: string | null;
    entityId: string | null;
    success: boolean | null;
    errorCode: string | null;
    durationMs: number | null;
    props: unknown;
    appVersion: string | null;
    platform: string | null;
    serverTs: string;
  }>
> {
  const conditions = [];
  if (opts.userId) conditions.push(eq(usageEvent.userId, opts.userId));
  if (opts.eventName) conditions.push(eq(usageEvent.eventName, opts.eventName));

  const rows = await db
    .select({
      id: usageEvent.id,
      userId: usageEvent.userId,
      userName: userTable.name,
      eventName: usageEvent.eventName,
      category: usageEvent.category,
      screen: usageEvent.screen,
      entityType: usageEvent.entityType,
      entityId: usageEvent.entityId,
      success: usageEvent.success,
      errorCode: usageEvent.errorCode,
      durationMs: usageEvent.durationMs,
      props: usageEvent.props,
      appVersion: usageEvent.appVersion,
      platform: usageEvent.platform,
      serverTs: usageEvent.serverTs,
    })
    .from(usageEvent)
    .leftJoin(userTable, eq(userTable.id, usageEvent.userId))
    .where(conditions.length > 0 ? and(...conditions) : undefined)
    .orderBy(desc(usageEvent.serverTs))
    .limit(Math.min(Math.max(opts.limit ?? 100, 1), 200));

  return rows.map((r) => ({
    id: r.id.toString(),
    userId: r.userId?.toString() ?? null,
    userName: r.userName ?? null,
    eventName: r.eventName,
    category: r.category,
    screen: r.screen,
    entityType: r.entityType,
    entityId: r.entityId,
    success: r.success,
    errorCode: r.errorCode,
    durationMs: r.durationMs,
    props: r.props,
    appVersion: r.appVersion,
    platform: r.platform,
    serverTs: r.serverTs.toISOString(),
  }));
}
