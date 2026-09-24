// ============================================
// 主体模型不变量 巡检 / 修复 (ADR-0015 Q16, 主人 2026-09-22 拍「全按建议」)
// ============================================
// 为什么需要这个脚本:
//   ADR-0015 定义的六条不变量 (一人一 hash / 账号⇒档案 / 节点⇒账号 / 建档≠归属 /
//   归属∪直推 / 列连接), 迁移前全靠**应用层自觉** → 存量数据已漂
//   (2026-09-22 实测: dev 254 条孤儿推荐码 / 3 个无账号节点 / 36 个账号没档案)。
//   本脚本把「巡检 → 修复」变成一条可重复跑的命令。
//
// 用法:
//   npx tsx scripts/audit-subject-integrity.ts           # = --check (只报; 有问题 → 退出码 1)
//   npx tsx scripts/audit-subject-integrity.ts --fix     # 修**可安全自动修**的 (①③④)
//
// 六项巡检:
//   ① 孤儿推荐码      referral_code 指向不存在的账号 (删号没清码)         → --fix 删码
//   ② 无账号节点      franchisee 找不到**绑定**账号 (§6.7 禁止; 口径 = user.franchisee_id)
//                     → 人工 (见 audit-orphan-nodes.ts)
//   ③ 账号缺客户档案   user 没有同手机号 customer (admin 豁免 Q5)        → --fix 建档案
//   ④ 列连接缺失      user.customer_id 为空但有档案 (Q7 回填漏)          → --fix 回填
//   ⑤ 列连接漂移      user.customer_id 指向的档案 phone_hash ≠ 账号的    → 只报 (需人工判断)
//   ⑥ 归属悬空        customer.owner_id 指向不存在的账号                 → 只报 (需人工判断)
//   ⑦ 节点手机号漂移   节点绑定的账号 phone_hash ≠ 节点记录的 phone_hash  → 只报 (改号漏同步?)
//
// ⚠ 与 audit-orphan-nodes.ts 的分工: 那边专管②(绑定/剪枝, 有下线的必须人工);
//   这边管①③④⑤⑥ + 给②一个总览数字。
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { ensureAccountProfile } from "@/lib/auth/registration";

// 测试数据前缀过滤 (合并测试-* / 冒烟-* / SeedTest-* 都是 dev 噪声; ADR-0015 之后用真数据)
const TEST_NAME_REGEX = '^(合并测试|冒烟|SeedTest)-';

const fix = process.argv.includes("--fix");

interface Row {
  [k: string]: unknown;
}

async function q(query: string): Promise<Row[]> {
  return (await db.execute(sql.raw(query))) as unknown as Row[];
}

async function main() {
  console.log(
    `\n=== 主体模型不变量巡检 (ADR-0015 Q16) — 模式: ${fix ? "🔧 --fix (会改数据)" : "🔍 --check (只读)"} ===\n`
  );

  const problems: string[] = [];
  const warnings: string[] = [];  // 数据质量提醒 (不进阻断; 例如 dev 冒烟残留)

  // ── ① 孤儿推荐码 ───────────────────────────────────────────────
  const [orphanCodes] = await q(`
    SELECT count(*)::int AS n FROM referral_code rc
    WHERE NOT EXISTS (SELECT 1 FROM "user" u WHERE u.id = rc.user_id)
  `);
  const n1 = Number(orphanCodes?.n ?? 0);
  console.log(`① 孤儿推荐码 (指向已删账号): ${n1}`);
  if (n1 > 0) {
    if (fix) {
      const deleted = await q(`
        DELETE FROM referral_code rc
        WHERE NOT EXISTS (SELECT 1 FROM "user" u WHERE u.id = rc.user_id)
        RETURNING rc.id
      `);
      console.log(`   🔧 已删除 ${deleted.length} 条孤儿码`);
    } else {
      problems.push(`① 孤儿推荐码 ${n1} 条 (--fix 可删)`);
    }
  }

  // ── ② 无账号加盟节点 (§6.7) ────────────────────────────────────
  //   口径 = **绑定** (user.franchisee_id = f.id + is_active) —— 与
  //   franchisee-account.ts::assertNodeHasAccount / audit-orphan-nodes.ts 完全一致
  //   (手机号一致只是"同人"的约定, 不是 §6.7 的判定; 漂移见 ⑦)
  const [orphanNodes] = await q(`
    SELECT count(*)::int AS n FROM franchisee f
    WHERE f.deleted_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM "user" u
        WHERE u.franchisee_id = f.id AND u.is_active = true
      )
  `);
  const n2 = Number(orphanNodes?.n ?? 0);
  console.log(`② 无账号加盟节点 (§6.7 禁止; binding 口径): ${n2}`);
  if (n2 > 0) {
    problems.push(
      `② 无账号节点 ${n2} 个 → npx tsx scripts/audit-orphan-nodes.ts [--bind|--prune]`
    );
    if (fix) {
      const rows = await q(`
        SELECT f.id, f.name FROM franchisee f
        WHERE f.deleted_at IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM "user" u
            WHERE u.franchisee_id = f.id AND u.is_active = true
          )
        ORDER BY f.id LIMIT 10
      `);
      console.log(
        `   (前 ${rows.length} 个: ${rows.map((r) => `#${r.id} ${r.name}`).join(", ")} — 本脚本不自动处理)`
      );
    }
  }

  // ── ③ 账号缺客户档案 (排除 admin 豁免 Q5) ───────────────────────
  const missingProfiles = await q(`
    SELECT u.id, u.name, u.role
    FROM "user" u
    WHERE u.role <> 'admin'
      AND u.is_active = true
      AND u.name !~ '^(合并测试|冒烟|SeedTest)-'
      AND NOT EXISTS (
        SELECT 1 FROM customer c
        WHERE c.phone_hash = u.phone_hash AND c.deleted_at IS NULL
      )
    ORDER BY u.id
  `);
  console.log(`③ 账号缺客户档案 (非 admin): ${missingProfiles.length}`);
  if (missingProfiles.length > 0) {
    if (fix) {
      let created = 0;
      for (const u of missingProfiles) {
        const res = await ensureAccountProfile(BigInt(String(u.id)), BigInt(0));
        if (res.customerCreated) created++;
      }
      console.log(`   🔧 已补档 ${created} 个 (复用既有档案的不计)`);
    } else {
      problems.push(`③ 缺档案账号 ${missingProfiles.length} 个 (--fix 可补)`);
    }
  }

  // ── ④ user.customer_id 未回填 (Q7) ─────────────────────────────
  const [missingLink] = await q(`
    SELECT count(*)::int AS n FROM "user" u
    JOIN customer c ON c.phone_hash = u.phone_hash AND c.deleted_at IS NULL
    WHERE u.customer_id IS NULL
  `);
  const n4 = Number(missingLink?.n ?? 0);
  console.log(`④ 列连接缺失 (有档案但 user.customer_id 为空): ${n4}`);
  if (n4 > 0) {
    if (fix) {
      const linked = await q(`
        UPDATE "user" u SET customer_id = c.id
        FROM customer c
        WHERE u.customer_id IS NULL
          AND c.deleted_at IS NULL
          AND c.phone_hash = u.phone_hash
        RETURNING u.id
      `);
      console.log(`   🔧 已回填 ${linked.length} 个账号的 customer_id`);
    } else {
      problems.push(`④ 列连接缺失 ${n4} 个 (--fix 可回填)`);
    }
  }

  // ── ⑤ 列连接漂移 (customer_id 指向别人的档案) ─────────────────
  const drift = await q(`
    SELECT u.id AS user_id, u.name, c.id AS customer_id, c.name AS customer_name
    FROM "user" u
    JOIN customer c ON c.id = u.customer_id
    WHERE c.phone_hash <> u.phone_hash
      AND u.name !~ '^(合并测试|冒烟|SeedTest)-'
      AND c.name !~ '^(合并测试|冒烟|SeedTest)-'
    ORDER BY u.id LIMIT 20
  `);
  console.log(`⑤ 列连接漂移 (customer_id 指向的档案不是同一手机号): ${drift.length}`);
  if (drift.length > 0) {
    problems.push(`⑤ 列连接漂移 ${drift.length} 个 → 人工核对 (改号漏同步?)`);
    for (const d of drift) {
      console.log(`   - user ${d.user_id} ${d.name} → customer ${d.customer_id} ${d.customer_name}`);
    }
  }

  // ── ⑥ 归属悬空 (owner_id 指向已删账号) ────────────────────────
  const [danglingOwner] = await q(`
    SELECT count(*)::int AS n FROM customer c
    WHERE c.owner_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM "user" u WHERE u.id = c.owner_id)
  `);
  const n6 = Number(danglingOwner?.n ?? 0);
  console.log(`⑥ 归属悬空 (owner_id 指向已删账号): ${n6}`);
  if (n6 > 0) {
    problems.push(`⑥ 归属悬空 ${n6} 条 → 人工判断 (转给谁 / 置空) `);
  }

  // ── ⑦ 节点手机号漂移 (绑定账号与节点记录的手机号不一致) ──────
  const nodeDrift = await q(`
    SELECT f.id AS fid, f.name AS fname, u.id AS uid, u.name AS uname
    FROM franchisee f
    JOIN "user" u ON u.franchisee_id = f.id AND u.is_active = true
    WHERE f.deleted_at IS NULL AND u.phone_hash <> f.phone_hash
      AND u.name !~ '^(合并测试|冒烟|SeedTest)-'
      AND f.name !~ '^(合并测试|冒烟|SeedTest)-'
    ORDER BY f.id LIMIT 20
  `);
  console.log(`⑦ 节点手机号漂移 (绑定账号的号 ≠ 节点记录的号): ${nodeDrift.length}`);
  if (nodeDrift.length > 0) {
    warnings.push(`⑦ 节点手机号漂移 ${nodeDrift.length} 个 → 人工核对 (是否改号漏同步)`);
    for (const d of nodeDrift) {
      console.log(`   - 节点 ${d.fid} ${d.fname} ← 账号 ${d.uid} ${d.uname}`);
    }
  }

  // ── 汇总 ──────────────────────────────────────────────────────
  console.log("\n=== 汇总 ===");
  if (problems.length === 0) {
    if (warnings.length === 0) {
      console.log("✅ 七项不变量全部通过 (无问题)\n");
    } else {
      console.log("✅ 硬性不变量全部通过; 另有数据质量告警:\n");
      for (const w of warnings) console.log(`  ⚠️  ${w}`);
      console.log("");
    }
    process.exit(0);
  }
  for (const p of problems) console.log(`  ❌ ${p}`);
  for (const w of warnings) console.log(`  ⚠️  ${w} (告警, 不阻断)`);
  console.log(
    fix
      ? "\n⚠️ 仍有需要人工处理的项 (见上); 自动可修项已尝试修复。\n"
      : "\n→ 加 --fix 修复可自动修的三项 (①③④); 其余需人工。\n"
  );
  process.exit(fix ? 0 : 1);
}

main().catch((e) => {
  console.error("❌ 巡检失败:", e instanceof Error ? e.message : String(e));
  process.exit(2);
});
