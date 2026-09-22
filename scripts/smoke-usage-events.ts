// ============================================
// 使用数据采集冒烟 (dev) — 主人 2026-09-22 拍「完整全面使用数据收集模块」
//
// 验 10 条 (HTTP 段需 dev server; 不可达则跳过 HTTP, 只跑 DB 段):
//   ① 合法批量 → 200 + accepted=N
//   ② 同批重传 → accepted=0 (幂等, event_id 唯一)
//   ③ 未知事件名 → rejected≥1 (词表外丢弃)
//   ④ 中文 props 值 → 事件收下, 库里 props 无中文 (自由文本写不进)
//   ⑤ 缺 device → 400
//   ⑥ 非管理员 GET /api/admin/usage/overview → 403
//   ⑦ 管理员 overview → 200 且能看到刚才的事件 (totals.events 增加)
//   ⑧ 管理员 users → 能看到测试账号
//   ⑨ 管理员 events → 能按 eventName 过滤
//   ⑩ 保留期清理 purgeUsageEvents(180) 删掉 200 天前的事件、保留新事件
//
// 跑: npx tsx scripts/smoke-usage-events.ts   (幂等, 跑完自己清理)
// ============================================

// ⚠ 必须是第一个 import (dotenv 副作用先于读 env 的模块; 见 scripts/_env.ts)
import "./_env";

import { eq, inArray, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer, referralCode, usageEvent, user } from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile } from "@/lib/auth/registration";
import { purgeUsageEvents } from "@/lib/db/queries/usage";

const BASE = process.env.SMOKE_BASE_URL ?? "http://127.0.0.1:3003";
const MARK = "smoke-usage";
const PHONE_ADMIN = "13900008801";
const PHONE_SALES = "13900008802";
const DEVICE = "smoke-device-0001";
const SESSION = "smoke-session-001";

let pass = 0;
let fail = 0;
const ck = (name: string, ok: boolean, extra = "") => {
  console.log(`${ok ? "✅" : "❌"} ${name}${extra ? ` — ${extra}` : ""}`);
  ok ? pass++ : fail++;
};

async function cleanup() {
  // 按 device + 测试账号删 (幂等)
  await db.delete(usageEvent).where(eq(usageEvent.deviceId, DEVICE));
  for (const phone of [PHONE_ADMIN, PHONE_SALES]) {
    const h = hashForLookup(phone);
    const rows = await db.select({ id: user.id }).from(user).where(eq(user.phoneHash, h));
    const ids = rows.map((r) => r.id);
    if (ids.length > 0) {
      await db.delete(usageEvent).where(inArray(usageEvent.userId, ids));
      await db.delete(user).where(inArray(user.id, ids));
    }
    await db.delete(customer).where(eq(customer.phoneHash, h));
  }
}

async function login(identifier: string, password: string) {
  const res = await fetch(`${BASE}/api/auth/flutter-login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ identifier, password }),
  });
  const body = (await res.json().catch(() => ({}))) as { sessionToken?: string };
  return body.sessionToken ?? null;
}

function batch(eventId: string, name = "screen_view") {
  return {
    device: {
      deviceId: DEVICE,
      appVersion: "0.2.7+8",
      platform: "android",
      osVersion: "14",
      deviceModel: "smoke-device",
    },
    events: [
      {
        id: eventId,
        name,
        ts: new Date().toISOString(),
        sessionId: SESSION,
        screen: "/customers/:id",
        entityType: "customer",
        entityId: "1",
      },
    ],
  };
}

async function main() {
  await cleanup();

  const [code] = await db.select({ code: referralCode.code }).from(referralCode).limit(1);
  if (!code) throw new Error("库里没有推荐码, 先跑 seed");

  // 建号必须带 actorUserId (审计) — 用库里既有 admin (pnpm db:ensure-admin)
  const [actor] = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.role, "admin"))
    .limit(1);
  if (!actor) throw new Error("库里没有 admin, 先跑 pnpm db:ensure-admin");

  const admin = await createAccountWithProfile({
    name: `${MARK}-admin`,
    phone: PHONE_ADMIN,
    password: "Test1234",
    referralCode: code.code,
    actorUserId: actor.id,
  });
  const sales = await createAccountWithProfile({
    name: `${MARK}-sales`,
    phone: PHONE_SALES,
    password: "Test1234",
    referralCode: code.code,
    actorUserId: actor.id,
  });
  await db.update(user).set({ role: "admin" }).where(eq(user.id, admin.userId));

  const alive = await fetch(`${BASE}/api/health`)
    .then((r) => r.ok)
    .catch(() => false);

  if (!alive) {
    console.log(`⏭  HTTP 段跳过 (${BASE} 不可达, 未起 dev server)`);
    console.log("\nDB 段: 直接插 1 条 + 清理");
    const now = new Date();
    const old = new Date(now.getTime() - 200 * 24 * 3600 * 1000);
    await db.insert(usageEvent).values([
      {
        eventId: `${MARK}-old-event`,
        userId: sales.userId,
        deviceId: DEVICE,
        eventName: "screen_view",
        category: "nav",
        serverTs: old,
      },
      {
        eventId: `${MARK}-new-event`,
        userId: sales.userId,
        deviceId: DEVICE,
        eventName: "screen_view",
        category: "nav",
        serverTs: now,
      },
    ]);
    const purged = await purgeUsageEvents(180);
    ck("⑩ purge 删除 200 天前事件", purged >= 1, `purged=${purged}`);
    const left = await db
      .select({ id: usageEvent.id })
      .from(usageEvent)
      .where(eq(usageEvent.deviceId, DEVICE));
    ck("⑩ 新事件保留", left.length === 1, `left=${left.length}`);
    await cleanup();
    console.log(`\n${fail === 0 ? "全部通过" : "有失败"}: ${pass} pass / ${fail} fail`);
    process.exit(fail === 0 ? 0 : 1);
  }

  const adminToken = await login(PHONE_ADMIN, "Test1234");
  const salesToken = await login(PHONE_SALES, "Test1234");
  if (!adminToken || !salesToken) {
    ck("前置: 登录拿 session", false, `admin=${!!adminToken} sales=${!!salesToken}`);
    await cleanup();
    process.exit(1);
  }
  const adminCookie = { Cookie: `authjs.session-token=${adminToken}` };
  const salesCookie = { Cookie: `authjs.session-token=${salesToken}` };
  const json = (extra: Record<string, string> = {}) => ({
    "content-type": "application/json",
    ...extra,
  });

  // ① 合法批量
  const evt1 = `${MARK}-evt-0001`;
  const r1 = await fetch(`${BASE}/api/usage/events`, {
    method: "POST",
    headers: json(salesCookie),
    body: JSON.stringify(batch(evt1)),
  });
  const b1 = (await r1.json()) as { accepted?: number };
  ck("① 合法批量 200 + accepted=1", r1.status === 200 && b1.accepted === 1, `status=${r1.status} accepted=${b1.accepted}`);

  // ② 幂等重传
  const r2 = await fetch(`${BASE}/api/usage/events`, {
    method: "POST",
    headers: json(salesCookie),
    body: JSON.stringify(batch(evt1)),
  });
  const b2 = (await r2.json()) as { accepted?: number; deduped?: number };
  ck("② 重传 accepted=0 (幂等)", r2.status === 200 && b2.accepted === 0, `accepted=${b2.accepted}`);

  // ③ 未知事件名
  const r3 = await fetch(`${BASE}/api/usage/events`, {
    method: "POST",
    headers: json(salesCookie),
    body: JSON.stringify(batch(`${MARK}-evt-0002`, "customer_姓名_张三")),
  });
  const b3 = (await r3.json()) as { rejected?: number };
  ck("③ 未知事件名 rejected≥1", r3.status === 200 && (b3.rejected ?? 0) >= 1, `rejected=${b3.rejected}`);

  // ④ 中文 props 写不进
  const evt4 = `${MARK}-evt-0004`;
  const payload4 = batch(evt4, "customer_search");
  payload4.events[0] = {
    ...payload4.events[0],
    // @ts-expect-error 冒烟故意塞非法键/值
    props: { keywordLen: 3, keyword: "张三", note: "腰椎间盘突出" },
  };
  await fetch(`${BASE}/api/usage/events`, {
    method: "POST",
    headers: json(salesCookie),
    body: JSON.stringify(payload4),
  });
  const [row4] = await db
    .select({ props: usageEvent.props })
    .from(usageEvent)
    .where(eq(usageEvent.eventId, evt4))
    .limit(1);
  const propsStr = JSON.stringify(row4?.props ?? {});
  ck(
    "④ 库里 props 无中文/无自由文本",
    !!row4 && !/[\u4e00-\u9fa5]/.test(propsStr) && propsStr.includes("keywordLen"),
    propsStr
  );

  // ⑤ 缺 device
  const r5 = await fetch(`${BASE}/api/usage/events`, {
    method: "POST",
    headers: json(salesCookie),
    body: JSON.stringify({ events: [{ id: `${MARK}-evt-0005`, name: "screen_view" }] }),
  });
  ck("⑤ 缺 device → 400", r5.status === 400, `status=${r5.status}`);

  // ⑥ 非管理员 → 403
  const r6 = await fetch(`${BASE}/api/admin/usage/overview?days=7`, { headers: salesCookie });
  ck("⑥ 非管理员 overview → 403", r6.status === 403, `status=${r6.status}`);

  // ⑦ 管理员 overview
  const r7 = await fetch(`${BASE}/api/admin/usage/overview?days=7`, { headers: adminCookie });
  const b7 = (await r7.json()) as {
    totals?: { events?: number };
    topScreens?: Array<{ screen: string }>;
    aiCards?: unknown[];
  };
  ck(
    "⑦ 管理员 overview 200 且含 screen_view",
    r7.status === 200 &&
      (b7.totals?.events ?? 0) >= 2 &&
      (b7.topScreens ?? []).some((s) => s.screen === "/customers/:id"),
    `status=${r7.status} events=${b7.totals?.events} screens=${(b7.topScreens ?? []).map((s) => s.screen).join("|")}`
  );

  // ⑧ 管理员 users
  const r8 = await fetch(`${BASE}/api/admin/usage/users?days=7`, { headers: adminCookie });
  const b8 = (await r8.json()) as { users?: Array<{ userId: string }> };
  ck(
    "⑧ 管理员 users 含测试账号",
    r8.status === 200 && (b8.users ?? []).some((u) => u.userId === String(sales.userId)),
    `status=${r8.status} users=${b8.users?.length}`
  );

  // ⑨ 管理员 events 过滤
  const r9 = await fetch(
    `${BASE}/api/admin/usage/events?limit=50&name=customer_search`,
    { headers: adminCookie }
  );
  const b9 = (await r9.json()) as { events?: Array<{ eventName: string }> };
  ck(
    "⑨ events 按 name 过滤",
    r9.status === 200 && (b9.events ?? []).every((e) => e.eventName === "customer_search"),
    `status=${r9.status} n=${b9.events?.length}`
  );

  // ⑩ 保留期清理
  const now = new Date();
  const old = new Date(now.getTime() - 200 * 24 * 3600 * 1000);
  await db.insert(usageEvent).values({
    eventId: `${MARK}-old-event`,
    userId: sales.userId,
    deviceId: DEVICE,
    eventName: "screen_view",
    category: "nav",
    serverTs: old,
  });
  await db.execute(sql`UPDATE usage_event SET server_ts = ${old.toISOString()} WHERE event_id = ${`${MARK}-old-event`}`);
  const purged = await purgeUsageEvents(180);
  const gone = await db
    .select({ id: usageEvent.id })
    .from(usageEvent)
    .where(eq(usageEvent.eventId, `${MARK}-old-event`));
  ck("⑩ purge 删 200 天前 + 保留新", purged >= 1 && gone.length === 0, `purged=${purged}`);

  await cleanup();
  console.log(`\n${fail === 0 ? "全部通过" : "有失败"}: ${pass} pass / ${fail} fail`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error("冒烟脚本自身炸了:", e);
  try {
    await cleanup();
  } catch {
    /* ignore */
  }
  process.exit(1);
});
