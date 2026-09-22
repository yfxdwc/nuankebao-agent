// ============================================
// 使用数据保留期清理 (主人 2026-09-22 拍: 原始事件 180 天后删)
//
// 跑:
//   npx tsx scripts/usage-retention.ts                # 默认 180 天, 真删
//   npx tsx scripts/usage-retention.ts --dry-run      # 只统计不删
//   npx tsx scripts/usage-retention.ts --days=90      # 自定义 (最小 7, 防手滑整库清空)
//   USAGE_RETENTION_DAYS=180 npx tsx scripts/usage-retention.ts
//
// 定时: deploy/systemd/nuankebao-usage-retention.timer (每日 04:30; 见 deploy/README.md)
// 注: 聚合分析 (getUsageOverview) 仍在保留期内可用; 超期后只保留代码里的聚合能力,
//     不保留原始行。需要长期趋势 → 后续加 usage_daily 汇总表 (可选项, 当前 1-2 用户量级不需要)。
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import {
  countUsageEventsOlderThan,
  purgeUsageEvents,
} from "@/lib/db/queries/usage";

const MIN_DAYS = 7;

function parseDays(): number {
  const arg = process.argv.find((a) => a.startsWith("--days="));
  const raw = arg ? arg.split("=")[1] : process.env.USAGE_RETENTION_DAYS;
  const days = raw ? Number(raw) : 180;
  if (!Number.isFinite(days) || !Number.isInteger(days) || days < MIN_DAYS) {
    console.error(
      `❌ 保留天数非法: ${raw} (要求 ≥ ${MIN_DAYS}, 默认 180; 防止手滑清空全库)`
    );
    process.exit(2);
  }
  return days;
}

async function main() {
  const days = parseDays();
  const dryRun = process.argv.includes("--dry-run");

  console.log(
    `[usage-retention] 保留期 = ${days} 天; 模式 = ${dryRun ? "dry-run (只看)" : "真删"}`
  );

  if (dryRun) {
    const count = await countUsageEventsOlderThan(days);
    console.log(`[usage-retention] 将删除 ${count} 条原始事件 (未执行)`);
    return;
  }

  const before = await countUsageEventsOlderThan(days);
  const deleted = await purgeUsageEvents(days);
  console.log(
    `[usage-retention] 候选 ${before} 条, 实际删除 ${deleted} 条 (幂等: 重复跑删 0 条)`
  );
}

main().catch((e) => {
  console.error("usage-retention 脚本自身炸了:", e);
  process.exit(1);
});
