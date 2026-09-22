// ============================================
// 使用数据 CLI 报表 (服务器直读, 可看原始口径)
//
// 跑:
//   npx tsx scripts/usage-report.ts                 # 默认近 30 天
//   npx tsx scripts/usage-report.ts 7               # 近 7 天
//   npx tsx scripts/usage-report.ts 30 --events=20  # 附最近 20 条原始事件
//
// 与 /admin/usage 的区别:
//   - 本脚本可直读原始事件 (服务器 shell), web 页只出聚合 (最小权限)
//   - 输出纯文本, 适合 SSH / 留档 / 主人直接看
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import {
  getUsageOverview,
  getUsageUsers,
  listRecentUsageEvents,
} from "@/lib/db/queries/usage";

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

const AI_CARD_LABELS: Record<string, string> = {
  profile: "客户画像",
  follow_up: "跟进话术",
  repurchase: "复购预测",
  effect: "效果分析",
};

function fmtDuration(sec: number): string {
  if (sec <= 0) return "—";
  if (sec < 60) return `${sec}s`;
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return s === 0 ? `${m}m` : `${m}m${s}s`;
}

function fmtTime(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate()
  ).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(
    d.getMinutes()
  ).padStart(2, "0")}`;
}

async function main() {
  const days = Number(process.argv[2]) || 30;
  const eventsArg = process.argv.find((a) => a.startsWith("--events="));
  const eventsLimit = eventsArg ? Number(eventsArg.split("=")[1]) : 0;

  const [overview, users] = await Promise.all([
    getUsageOverview(days),
    getUsageUsers(days),
  ]);

  console.log(`\n===== 暖客宝 使用数据 (近 ${days} 天) =====\n`);
  const t = overview.totals;
  console.log(
    `活跃用户 ${t.users} 人 / 事件 ${t.events} 条 / 会话 ${t.sessions} 次 / 设备 ${t.devices} 台`
  );
  console.log(`平均会话时长 ${fmtDuration(t.avgSessionSec)} · 有数据天数 ${t.activeDays}\n`);

  if (overview.daily.length > 0) {
    console.log("— 每日活跃 —");
    for (const d of overview.daily) {
      console.log(`  ${d.date}  用户 ${d.users}  事件 ${d.events}  会话 ${d.sessions}`);
    }
    console.log("");
  }

  if (overview.aiCards.length > 0) {
    console.log("— AI 卡片 (核心问题: 有没有人点) —");
    for (const c of overview.aiCards) {
      console.log(
        `  ${AI_CARD_LABELS[c.card] ?? c.card}: 点击 ${c.clicks} / 成功 ${c.ok} / 失败 ${c.failed}` +
          `${c.regenerates ? ` / 重生成 ${c.regenerates}` : ""}` +
          `${c.avgDurationMs ? ` / 平均 ${(c.avgDurationMs / 1000).toFixed(1)}s` : ""}`
      );
    }
    console.log("");
  }

  console.log("— 核心漏斗 (去重用户) —");
  const f = overview.funnel;
  console.log(
    `  看客户详情 ${f.customerView} → 点 AI ${f.aiClick} → AI 出结果 ${f.aiOk} → ` +
      `建跟进 ${f.followUpCreate} → 完成跟进 ${f.followUpDone} · 记养生 ${f.recordCreate}\n`
  );

  console.log("— 事件排行 Top 15 —");
  for (const e of overview.topEvents.slice(0, 15)) {
    console.log(
      `  ${e.eventName.padEnd(26)} ${String(e.count).padStart(6)} 次 / ${e.users} 人` +
        `  (${CATEGORY_LABELS[e.category ?? ""] ?? e.category ?? "—"})`
    );
  }
  console.log("");

  if (overview.errors.length > 0) {
    console.log("— 报错 Top —");
    for (const e of overview.errors) {
      console.log(`  ${e.eventName}:${e.label}  ${e.count} 次 / ${e.users} 人`);
    }
    console.log("");
  }

  console.log("— 按用户 —");
  for (const u of users) {
    console.log(
      `  ${(u.name ?? `#${u.userId}`).padEnd(12)} 最后活跃 ${fmtTime(u.lastActive)}` +
        ` · 活跃 ${u.daysActive} 天 · 事件 ${u.events} · 会话 ${u.sessions}` +
        ` · AI ${u.aiClicks} · 建客户 ${u.customersCreated} · 养生 ${u.recordsCreated} · 完成跟进 ${u.followUpsDone}`
    );
  }
  if (users.length === 0) console.log("  (无)");
  console.log("");

  if (eventsLimit > 0) {
    const events = await listRecentUsageEvents({ limit: eventsLimit });
    console.log(`— 最近 ${events.length} 条原始事件 —`);
    for (const e of events) {
      console.log(
        `  ${fmtTime(e.serverTs)}  ${(e.userName ?? "—").padEnd(10)} ${e.eventName.padEnd(24)}` +
          ` ${e.screen ?? e.errorCode ?? ""}` +
          `${e.durationMs != null ? ` ${e.durationMs}ms` : ""}` +
          `${e.props ? ` ${JSON.stringify(e.props)}` : ""}`
      );
    }
    console.log("");
  }
}

main().catch((e) => {
  console.error("usage-report 脚本自身炸了:", e);
  process.exit(1);
});
