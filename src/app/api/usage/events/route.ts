// ============================================
// POST /api/usage/events — 真实用户使用事件采集入口
//
// 主人 2026-09-22 拍: 内部工具强制开启; 原始事件 180 天后删
//
// Body:
//   {
//     device: { deviceId, appVersion?, platform?, osVersion?, deviceModel? },
//     events: [{ id, name, ts?, sessionId?, screen?, entityType?, entityId?,
//                success?, errorCode?, durationMs?, props? }, ...]   // ≤ 50 条
//   }
// Response 200: { accepted, rejected, dropped? }
//
// 安全 (CHARTER §4.4.5):
//   - auth 必须 (user_id 服务端取自 session, 不信任客户端)
//   - 限流 (rateLimit "usage": 30 req/min/用户)
//   - 词表 + props 白名单 + slug 正则 + 手机号 regex 兜底 (src/lib/usage/sanitize.ts)
//   - 服务端时间戳 server_ts 为准; 客户端 ts 只作参考 (漂移 > 7 天丢弃)
//   - 幂等: event_id 唯一索引 + ON CONFLICT DO NOTHING (批量重传安全)
//
// 不挂 audit 触发器: usage_event 自身就是行为留痕 (挂上 = 双倍写入)
// ============================================

import { NextRequest, NextResponse } from "next/server";

import { apiGuard } from "@/lib/api-guard";
import { insertUsageEvents } from "@/lib/db/queries/usage";
import { sanitizeUsageBatch } from "@/lib/usage/sanitize";
import { logger } from "@/lib/errors";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** 请求体上限 (50 条 × ~300B ≈ 15KB; 64KB 是宽松上限, 防畸形大包) */
const MAX_BODY_BYTES = 64 * 1024;

export async function POST(request: NextRequest) {
  const guard = await apiGuard(request, { auth: true, rateLimit: "usage" });
  if (guard.response) return guard.response;
  if (!guard.userId) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) {
    return NextResponse.json(
      { error: "请求体过大", code: "PAYLOAD_TOO_LARGE" },
      { status: 413 }
    );
  }

  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return NextResponse.json({ error: "JSON 解析失败" }, { status: 400 });
  }

  const { device, events, rejected } = sanitizeUsageBatch(body);
  if (!device) {
    return NextResponse.json(
      { error: "device.deviceId 缺失或非法", code: "BAD_DEVICE" },
      { status: 400 }
    );
  }

  try {
    const accepted = await insertUsageEvents(BigInt(guard.userId), device, events);
    return NextResponse.json({
      accepted,
      rejected,
      // 幂等去重 (重传) 数量 = 通过清洗但没写进库的
      deduped: Math.max(0, events.length - accepted),
    });
  } catch (error) {
    // 采集端点永不把客户端搞崩: 记日志, 返回 500 让客户端退避重试
    logger.error("usage events insert failed", {
      error: error instanceof Error ? error.message : String(error),
      userId: guard.userId,
      count: events.length,
    });
    return NextResponse.json(
      { error: "写入失败, 请稍后重试", code: "INSERT_FAILED" },
      { status: 500 }
    );
  }
}
