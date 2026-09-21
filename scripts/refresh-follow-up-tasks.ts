// ============================================
// 每日跟进任务生成 (主人 2026-09-20 拍 Q4: 自动建 + 7 天去重)
// ============================================
// 为什么要有这个脚本:
//   紧急度是**算出来**的 (列表/提醒条实时计算) —— 但用户勾「完成」需要一个**真实任务**挂住,
//   而且第二天打开 App 还得记得"这个人我昨天答应要联系" → 所以每天固定时间落一批任务。
//
// 规则 (只落**免费信号**, 生日/复购属会员能力, 由 App 侧展示, 不在 cron 里生成):
//   - 该客户紧急度 ≥ P1 (60 分) 且有「该联系了」类信号 (距上次联系 > 15 天 / 新客未首访) → 建任务
//   - 一人同时只留**一条** pending 任务 (已有 pending → 跳过)
//   - **7 天去重**: 同一客户 7 天内建过任务 (含已完成) → 跳过 (不骚扰)
//
// 用法:
//   npx tsx scripts/refresh-follow-up-tasks.ts            # 真跑
//   npx tsx scripts/refresh-follow-up-tasks.ts --dry-run   # 只看会建几条
//   LIMIT=500 npx tsx scripts/refresh-follow-up-tasks.ts   # 限制扫描量 (默认 2000)
//
// 定时: deploy/ 里可挂 systemd timer (每日 07:00), 与备份 timer 同一套机制
// ============================================

// ⚠ 必须是第一个 import: dotenv 的副作用要先于读 DATABASE_URL 的模块求值 (见 scripts/_env.ts)
import "./_env";

import { and, eq, gte, inArray, isNull, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer, followUpTask } from "@/lib/db/schema";
import { withAuditContext } from "@/lib/audit/context";
import { computeUrgency } from "@/lib/follow-up/urgency";

const dryRun = process.argv.includes("--dry-run");
const LIMIT = parseInt(process.env.LIMIT ?? "2000");
const DEDUP_DAYS = 7;
const MIN_SCORE = 60; // P1 及以上才建任务

async function main() {
  const now = new Date();
  const since = new Date(now.getTime() - DEDUP_DAYS * 86_400_000);

  // 待扫描客户 (未删除 + 限额)
  const rows = await db
    .select({
      id: customer.id,
      name: customer.name,
      createdAt: customer.createdAt,
      lastInteractionAt: customer.lastInteractionAt,
      lastVisitAt: customer.lastVisitAt,
      isSeed: customer.isSeed,
    })
    .from(customer)
    .where(isNull(customer.deletedAt))
    .limit(LIMIT);

  const ids = rows.map((r) => r.id);
  if (ids.length === 0) {
    console.log("没有客户, 跳过");
    return;
  }

  // 已有 pending 任务 (一人只留一条) + 7 天内建过的任务
  const existing = await db
    .select({
      customerId: followUpTask.customerId,
      status: followUpTask.status,
      createdAt: followUpTask.createdAt,
    })
    .from(followUpTask)
    .where(
      and(
        inArray(followUpTask.customerId, ids),
        sql`(${followUpTask.status} = 'pending' OR ${followUpTask.createdAt} >= ${since.toISOString()}::timestamptz)`
      )
    );
  const hasPending = new Set<string>();
  const recentlyTouched = new Set<string>();
  for (const t of existing) {
    const key = t.customerId.toString();
    if (t.status === "pending") hasPending.add(key);
    if (t.createdAt >= since) recentlyTouched.add(key);
  }

  // 算紧急度 (免费信号) → 挑出该建的
  const toCreate: Array<{ id: bigint; name: string; reason: string; score: number }> = [];
  let skippedPending = 0;
  let skippedDedup = 0;
  let belowThreshold = 0;

  for (const r of rows) {
    const key = r.id.toString();
    const result = computeUrgency({
      customerType: r.isSeed ? "seed" : "normal",
      createdAt: r.createdAt,
      lastInteractionAt: r.lastInteractionAt,
      lastVisitAt: r.lastVisitAt,
      openTaskDueAts: hasPending.has(key) ? [new Date(now.getTime() + 86_400_000)] : [],
      now,
    });
    if (result.score < MIN_SCORE) {
      belowThreshold++;
      continue;
    }
    // 只需要「该联系了」类信号 (任务逾期已经是一条真任务 → 不用再建)
    const contactSignal = result.signals.find(
      (s) => s.key === "no_contact_long" || s.key === "never_contacted"
    );
    if (!contactSignal) {
      belowThreshold++;
      continue;
    }
    if (hasPending.has(key)) {
      skippedPending++;
      continue;
    }
    if (recentlyTouched.has(key)) {
      skippedDedup++;
      continue;
    }
    toCreate.push({
      id: r.id,
      name: r.name,
      reason: contactSignal.text,
      score: result.score,
    });
  }

  console.log(
    `扫描 ${rows.length} 位客户 → 待建 ${toCreate.length} 条` +
      ` (已有待办跳过 ${skippedPending} / 7 天内建过跳过 ${skippedDedup} / 未达阈值 ${belowThreshold})`
  );
  for (const t of toCreate.slice(0, 5)) {
    console.log(`   e.g. ${t.name}: ${t.reason} (${t.score} 分)`);
  }
  if (toCreate.length > 5) console.log(`   … 其余 ${toCreate.length - 5} 条同类`);

  if (dryRun) {
    console.log("\n[dry-run] 未写库");
    return;
  }
  if (toCreate.length === 0) {
    console.log("\n✅ 无需新建 (幂等)");
    return;
  }

  // due = 今天 09:00 (本地时区当天, 便于待办页归到"今天")
  const due = new Date(now);
  due.setHours(9, 0, 0, 0);
  if (due < now) due.setTime(now.getTime());

  await withAuditContext({ userId: BigInt(0) }, async (tx) => {
    await tx.insert(followUpTask).values(
      toCreate.map((t) => ({
        customerId: t.id,
        dueAt: due,
        reason: t.reason,
        status: "pending" as const,
        createdBy: BigInt(0),
      }))
    );
  });

  const [cnt] = await db.execute<{ n: string }>(
    sql`SELECT count(*) AS n FROM follow_up_task WHERE status = 'pending'`
  );
  console.log(`\n✅ 已建 ${toCreate.length} 条跟进任务 (当前 pending 总数 ${cnt.n})`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("✗ 失败:", e instanceof Error ? e.message : e);
    process.exit(1);
  });
