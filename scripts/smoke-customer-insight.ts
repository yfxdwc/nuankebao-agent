// ============================================
// 客户评分 / 行动指引 —— 真数据冒烟 (P1 验收)
// ============================================
//
// 主人 2026-09-23 拍板「先看真客户分数是否合理, 再上前端」。
// 本脚本拿**真实库**里的客户跑一遍, 打印可读报告:
//   ① 三维分数 + 分档
//   ② 每个维度的因子明细 (可解释性)
//   ③ 行动指引 (结构化 + 优先级)
//   ④ 合理性自检 (断言, 不合常理就报错)
//
// 跑: npx tsx scripts/smoke-customer-insight.ts
//     npx tsx scripts/smoke-customer-insight.ts --all      # 全部客户
//     npx tsx scripts/smoke-customer-insight.ts --id 42    # 指定客户
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";
import { sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { loadCustomerInsight } from "@/lib/customer/insight";

const args = process.argv.slice(2);
const wantAll = args.includes("--all");
const idArg = args.includes("--id") ? BigInt(args[args.indexOf("--id") + 1]) : null;
/**
 * `--as-of 2026-12-01` 或 `--days-later 90`
 *
 * 为什么需要: demo 库的数据全是一天内造的 → 关系时长全 < 30 天 → 价值分全 null,
 * **看不出算法在"有历史"的客户上表现如何**。把"今天"往后挪, 就能预览
 * "如果这个客户过了 90 天会得几分" —— 这是校验阈值是否合理的唯一办法 (不造脏数据)。
 */
const asOfArg = args.includes("--as-of") ? args[args.indexOf("--as-of") + 1] : null;
const daysLaterArg = args.includes("--days-later")
  ? Number(args[args.indexOf("--days-later") + 1])
  : null;
const NOW_OVERRIDE: Date | null = asOfArg
  ? new Date(`${asOfArg}T09:00:00Z`)
  : daysLaterArg !== null
    ? new Date(Date.now() + daysLaterArg * 86_400_000)
    : null;

let pass = 0;
let fail = 0;
const ok = (m: string) => { pass++; console.log(`  ✅ ${m}`); };
const bad = (m: string) => { fail++; console.log(`  ❌ ${m}`); };

const PAD = (s: string | number, n: number) => String(s).padEnd(n);

function bar(score: number | null, width = 12): string {
  if (score === null) return "─".repeat(width) + "  待评估";
  const filled = Math.round((score / 100) * width);
  return "█".repeat(filled) + "░".repeat(width - filled) + `  ${score.toFixed(1)}`;
}

async function main() {
  // ── 挑客户: **按数据丰富度采样** ──
  //   ⚠ 不能按 createdAt DESC: 那会全拿到刚造的零数据客户, 分数全是同一个值, 看不出算法好坏。
  //   改成 (养生记录数 + 互动数) 倒序 —— 拿"数据最多"的几个, 差异最明显。
  const rows = (await db.execute(sql`
    select * from (
      select c.id as id, c.name as name, c.created_at as created_at,
        (select count(*) from wellness_record w where w.customer_id = c.id) as recs,
        (select count(*) from interaction i where i.customer_id = c.id) as ints
      from customer c where c.deleted_at is null
    ) x
    order by (x.recs + x.ints) desc, x.id asc
    limit ${wantAll ? 200 : 40}
  `)) as Array<{ id: bigint; name: string; created_at: Date; recs: number; ints: number }>;

  const targets = idArg
    ? rows.filter((r) => r.id === idArg)
    : rows.slice(0, 15);

  if (targets.length === 0) {
    console.log("没有可跑的客户 (库是空的?)");
    process.exit(1);
  }

  console.log("\n" + "═".repeat(78));
  console.log(" 客户评分 / 行动指引 —— 真数据冒烟");
  console.log("═".repeat(78));
  console.log(` 客户数: ${targets.length} (库内共 ${rows.length} 条未删客户)`);
  if (NOW_OVERRIDE) {
    console.log(` ⏩ 时间基准: ${NOW_OVERRIDE.toISOString().slice(0, 10)} (--as-of / --days-later)`);
  }
  console.log("");

  const seen: Array<{ name: string; overall: number | null }> = [];

  for (const c of targets) {
    const insight = await loadCustomerInsight(c.id, NOW_OVERRIDE ?? new Date());
    if (!insight) {
      bad(`${c.name} (id=${c.id}) → loadCustomerInsight 返回 null`);
      continue;
    }
    const s = insight.score;

    console.log("─".repeat(78));
    console.log(`👤 ${c.name}  (id=${c.id})  建档 ${daysAgo(c.created_at)} 天前`);
    console.log("─".repeat(78));

    // ① 综合 + 三维
    console.log(`  综合   ${bar(s.overall)}   ${s.overallBandLabel}`);
    console.log(`  健康   ${bar(s.effect.score)}   ${s.effect.bandLabel}`);
    console.log(`  温度   ${bar(s.engagement.score)}   ${s.engagement.bandLabel}`);
    console.log(`  价值   ${bar(s.value.score)}   ${s.value.bandLabel}`);
    if (s.weakDimensions.length > 0) {
      console.log(`  ⚠ 短板: ${s.weakDimensions.join(" / ")}`);
    }
    if (s.effect.missingReason) {
      console.log(`  ℹ 健康分缺失: ${s.effect.missingReason}`);
    }

    // ② 因子明细 (可解释性 —— 销售能核对)
    const dims = [s.effect, s.engagement, s.value];
    for (const d of dims) {
      if (d.factors.length === 0) continue;
      console.log(`  ├─ ${d.label}`);
      for (const f of d.factors) {
        console.log(`  │   ${PAD(f.label, 12)} ${PAD(f.score.toFixed(0) + "/" + f.max, 8)} ${f.detail}`);
      }
    }

    // ③ 行动指引
    if (insight.actions.length === 0) {
      console.log("  └─ 行动: (无 —— 一切正常)");
    } else {
      console.log(`  └─ 行动 (${insight.actions.length} 条, L0 显示前 ${insight.topActions.length}):`);
      for (const a of insight.actions) {
        const flag = a.priority === "high" ? "🔴" : a.priority === "medium" ? "🟠" : "🟡";
        console.log(`      ${flag} [${a.id}] ${a.title}  · ${a.when} · ${a.channel}`);
        console.log(`         why: ${a.why}`);
        console.log(`         建任务: "${a.taskTitle}" (due ${a.taskDueAt.slice(0, 10)})`);
      }
    }

    // ④ 合理性自检
    if (s.overall !== null && (s.overall < 0 || s.overall > 100)) {
      bad(`${c.name}: overall=${s.overall} 越界`);
    }
    for (const d of dims) {
      if (d.score !== null && (d.score < 0 || d.score > 100)) {
        bad(`${c.name}: ${d.label} = ${d.score} 越界`);
      }
      for (const f of d.factors) {
        if (f.score < 0 || f.score > f.max) {
          bad(`${c.name}: ${d.label}.${f.label} = ${f.score}/${f.max} 越界`);
        }
      }
    }

    // 确定性: 同一 `now` 下再算一次, 分数必须完全一样 (纯函数承诺)
    //   ⚠ 不能直接比整个 score 对象 —— computedAt 是 ISO 毫秒, 两次 new Date() 必然不同。
    //     所以固定同一时刻, 只比"分数本身"。
    const fixedNow = new Date();
    const a1 = await loadCustomerInsight(c.id, fixedNow);
    const a2 = await loadCustomerInsight(c.id, fixedNow);
    const scoreOnly = (x: typeof a1) => {
      if (!x) return null;
      const { computedAt: _drop, ...rest } = x.score;
      void _drop;
      return JSON.stringify(rest);
    };
    if (scoreOnly(a1) !== scoreOnly(a2)) {
      bad(`${c.name}: 同一时刻两次调用分数不一致 (违反确定性!)`);
    }

    seen.push({ name: c.name, overall: s.overall });
    console.log("");
  }

  // ── 全局自检 ──
  console.log("═".repeat(78));
  console.log(" 合理性自检");
  console.log("═".repeat(78));

  const withScore = seen.filter((x) => x.overall !== null);
  if (withScore.length === 0) {
    bad("没有任何客户算出分数 —— loader 有问题?");
  } else {
    ok(`${withScore.length}/${seen.length} 个客户算出了综合分`);
  }

  const scores = withScore.map((x) => x.overall as number);
  if (scores.length > 1) {
    const min = Math.min(...scores);
    const max = Math.max(...scores);
    const avg = scores.reduce((a, b) => a + b, 0) / scores.length;
    console.log(`  分数分布: min=${min.toFixed(1)}  max=${max.toFixed(1)}  avg=${avg.toFixed(1)}`);

    // ⚠ 先看**输入**是否同质 —— 输入全一样的话, 输出没区分度是**数据问题不是算法问题**。
    //   (2026-09-23: 首次跑 demo 数据全是"3 记录 + 3 互动、同一天造" → 自检误报"算法有问题")
    const recSpread = new Set(targets.map((t) => Number(t.recs))).size;
    const intSpread = new Set(targets.map((t) => Number(t.ints))).size;
    console.log(`  输入分布: 养生记录数 ${recSpread} 种 / 互动数 ${intSpread} 种`);
    if (recSpread <= 1 && intSpread <= 1) {
      console.log(
        "  ℹ 输入同质 (所有客户数据量一样) → 跳过「区分度」断言; 要验区分度请用真实/多样数据"
      );
    } else if (max - min < 1) {
      bad(`输入有差异但分数几乎无区分度 (max-min=${(max - min).toFixed(2)}) —— 算法有问题?`);
    } else {
      ok(`分数有区分度 (跨度 ${(max - min).toFixed(1)} 分)`);
    }

    if (avg < 20 || avg > 90) {
      console.log(
        `  ⚠ 均值 ${avg.toFixed(1)} 偏${avg < 20 ? "低" : "高"} —— 可能是阈值需要调 (不是错误, 需人工判断)`
      );
    }
  }

  console.log("");
  console.log("═".repeat(78));
  console.log(` 通过 ${pass} / ${pass + fail}`);
  console.log("═".repeat(78) + "\n");
  process.exit(fail > 0 ? 1 : 0);
}

function daysAgo(d: Date): number {
  const ref = NOW_OVERRIDE ?? new Date();
  return Math.round((ref.getTime() - new Date(d).getTime()) / 86_400_000);
}

main().catch((e) => {
  console.error("冒烟失败:", e);
  process.exit(1);
});
