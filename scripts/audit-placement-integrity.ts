// ============================================
// 加盟树结构一致性巡检 (dev / 运维) — 主人 2026-09-21 拍「拆」后新增
// ============================================
// 背景: 「点位父」现在存两处 ——
//   ① `franchisee.placement_parent_id` (规范列; 点位算法读它, 见 franchisee-tree.ts)
//   ② `placement_path` 去尾段 + 同 root_id (布局用; 图谱/「上层点位」读它)
//   拆栏前提 = 两者永远一致。本脚本就是那条巡检线 (只读, 不改数据)。
//
// 查 6 类不一致 (每类给清单, 便于人工修):
//   ① 点位父列 ≠ path 推出来的父
//   ② 非根节点缺点位父 (算法会"看不见"这棵子树)
//   ③ 根节点却有点位父
//   ④ placement_side ≠ path 最后一段
//   ⑤ placement_depth ≠ path 段数
//   ⑥ 同一棵树里出现两条相同 path (二叉树一个位子只能一个人)
//   另外报告:
//   ℹ️ 推荐人栏 (referrer_id) 与点位父不一致的条数 —— **不是错**,
//     拆栏后这正是允许的 (推荐人 ≠ 点位父), 只作信息提示。
//   ℹ️ 推荐人不在节点「祖先链」上 (Phase B §6 E2, migration 0027, 主人 2026-09-25 拍):
//     允许的例外 (不报错, 仅信息提示):
//       (a) admin 强改上层 (adminReparentNode, AGENTS §6.8) — 显式不动 referrer_id
//       (b) 历史节点 (Phase B 之前 referrer_id 与 placement_parent_id 混合存, 不一致是常态)
//
// 用法:
//   npx tsx scripts/audit-placement-integrity.ts            # 只报
//   npx tsx scripts/audit-placement-integrity.ts --strict   # 有任何不一致 → exit 1 (CI / 冒烟用)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { sql } from "drizzle-orm";
import { db } from "@/lib/db";

const STRICT = process.argv.includes("--strict");

interface Row extends Record<string, unknown> {
  id: string;
  name: string;
  placement_parent_id: string | null;
  path_parent_id: string | null;
  placement_side: string | null;
  placement_path: string;
  placement_depth: number;
  root_id: string | null;
}

const PATH_PARENT = sql`CASE
  WHEN length(f.placement_path) <= 2 THEN ''::text
  ELSE left(f.placement_path, length(f.placement_path) - 2)
END`;

async function main() {
  const rows = await db.execute<Row>(sql`
    SELECT f.id::text                                   AS id,
           f.name                                       AS name,
           f.placement_parent_id::text                  AS placement_parent_id,
           p.id::text                                   AS path_parent_id,
           f.placement_side                             AS placement_side,
           f.placement_path                             AS placement_path,
           f.placement_depth                            AS placement_depth,
           f.root_id::text                              AS root_id
    FROM franchisee f
    LEFT JOIN franchisee p
           ON p.root_id = f.root_id
          AND p.placement_path = ${PATH_PARENT}
          AND p.id <> f.id
          AND p.deleted_at IS NULL
    WHERE f.deleted_at IS NULL
    ORDER BY f.id
  `);

  const bad = {
    parentMismatch: rows.filter(
      (r) => r.placement_path !== "" && (r.path_parent_id ?? null) !== (r.placement_parent_id ?? null)
    ),
    missingParent: rows.filter(
      (r) => r.placement_path !== "" && r.placement_parent_id == null
    ),
    rootHasParent: rows.filter(
      (r) => r.placement_path === "" && r.placement_parent_id != null
    ),
    sideMismatch: rows.filter((r) => {
      const want = r.placement_path.endsWith("L.")
        ? "left"
        : r.placement_path.endsWith("R.")
          ? "right"
          : null;
      return (r.placement_side ?? null) !== want;
    }),
    depthMismatch: rows.filter(
      (r) => r.placement_depth !== r.placement_path.split(".").filter(Boolean).length
    ),
  };

  const dupPaths = await db.execute<
    { root_id: string; placement_path: string; n: number } & Record<string, unknown>
  >(sql`
    SELECT COALESCE(root_id, id)::text AS root_id, placement_path, count(*)::int AS n
    FROM franchisee
    WHERE deleted_at IS NULL
    GROUP BY 1, 2
    HAVING count(*) > 1
  `);

  const info = await db.execute<{ n: number } & Record<string, unknown>>(sql`
    SELECT count(*)::int AS n FROM franchisee
    WHERE deleted_at IS NULL AND referrer_id IS DISTINCT FROM placement_parent_id
  `);

  // ℹ️ Phase B §6 E2 (migration 0027): 推荐人不在节点「祖先链」上 (允许的例外)
  //   触发场景:
  //     (a) adminReparentNode 后 (AGENTS §6.8) — 显式不动 referrer_id
  //     (b) 历史节点 (Phase B 之前 referrer_id 与 placement_parent_id 混合存, 不一致是常态)
  //   处理策略: 只报清单 + 不报错 (不级联改, E2), --strict 不计入失败判定
  const referrerNotInChain = await db.execute<
    {
      id: string;
      name: string;
      referrer_id: string;
      referrer_name: string;
      placement_parent_id: string;
      placement_path: string;
      root_id: string | null;
    } & Record<string, unknown>
  >(sql`
    SELECT child.id::text AS id,
           child.name      AS name,
           child.referrer_id::text AS referrer_id,
           ref.name        AS referrer_name,
           child.placement_parent_id::text AS placement_parent_id,
           child.placement_path AS placement_path,
           child.root_id::text AS root_id
    FROM franchisee child
    JOIN franchisee ref ON ref.id = child.referrer_id
    WHERE child.deleted_at IS NULL
      AND child.referrer_id IS NOT NULL
      AND child.placement_parent_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM franchisee anc
        WHERE anc.deleted_at IS NULL
          AND anc.root_id IS NOT DISTINCT FROM child.root_id
          AND child.placement_path LIKE (anc.placement_path || '%')
          AND anc.id = child.referrer_id
      )
    ORDER BY child.id
  `);

  console.log(`巡检 ${rows.length} 个活节点 (dev 库)\n`);

  const report = (label: string, list: Row[], why: string) => {
    if (list.length === 0) {
      console.log(`✅ ${label}: 0 条`);
      return;
    }
    console.log(`❌ ${label}: ${list.length} 条 — ${why}`);
    for (const r of list.slice(0, 10)) {
      console.log(
        `   #${r.id} ${r.name} path="${r.placement_path}" depth=${r.placement_depth} ` +
          `点位父列=${r.placement_parent_id ?? "null"} / path 推父=${r.path_parent_id ?? "null"} ` +
          `side=${r.placement_side ?? "null"} root=${r.root_id ?? "null"}`
      );
    }
    if (list.length > 10) console.log(`   … 其余 ${list.length - 10} 条略`);
  };

  report("① 点位父列 = path 推出来的父", bad.parentMismatch, "拆栏前提被破坏: 点位算法与图谱会看到两棵不同的树");
  report("② 非根节点有点位父", bad.missingParent, "点位算法按列导航 → 缺列 = 这棵子树看不见");
  report("③ 根节点没有点位父", bad.rootHasParent, "根不该有上层");
  report("④ placement_side = path 最后一段", bad.sideMismatch, "「我在上层哪条线」会显示错");
  report("⑤ placement_depth = path 段数", bad.depthMismatch, "层号会显示错");

  if (dupPaths.length === 0) {
    console.log("✅ ⑥ 同树内 path 唯一: 0 条冲突");
  } else {
    console.log(`❌ ⑥ 同树内 path 唯一: ${dupPaths.length} 处冲突 — 一个位子坐了两个人`);
    for (const d of dupPaths.slice(0, 10)) {
      console.log(`   root=${d.root_id} path="${d.placement_path}" × ${d.n}`);
    }
  }

  const n = info[0]?.n ?? 0;
  console.log(
    `\nℹ️  推荐人 ≠ 点位父: ${n} 条 —— **这不是错** (拆栏后允许; ` +
      `"谁推荐了她"和"她挂在谁下面"本来就可以是两个人)`
  );

  // ℹ️ Phase B §6 E2: referrer 不在祖先链上 (允许例外: admin 强改上层 / 历史节点)
  if (referrerNotInChain.length === 0) {
    console.log(
      "ℹ️  推荐人不在祖先链: 0 条 (E2 允许的例外, 不影响 --strict 判定)"
    );
  } else {
    console.log(
      `ℹ️  推荐人不在祖先链: ${referrerNotInChain.length} 条 —— **允许的例外** (Phase B §6 E2):\n` +
        "   (a) admin 强改上层 (adminReparentNode, AGENTS §6.8) — 显式不动 referrer_id\n" +
        "   (b) 历史节点 (Phase B 之前) — referrer 与 placement_parent 混合存的常态\n" +
        "   不级联改, 不报错, 仅供人工排查时参考"
    );
    for (const r of referrerNotInChain.slice(0, 10)) {
      console.log(
        `   #${r.id} ${r.name} (root=${r.root_id ?? "null"}, path=${r.placement_path}): ` +
          `referrer=#${r.referrer_id} ${r.referrer_name}, 点位父=#${r.placement_parent_id}`,
      );
    }
    if (referrerNotInChain.length > 10) {
      console.log(`   … 其余 ${referrerNotInChain.length - 10} 条略`);
    }
  }

  const errors =
    bad.parentMismatch.length +
    bad.missingParent.length +
    bad.rootHasParent.length +
    bad.sideMismatch.length +
    bad.depthMismatch.length +
    dupPaths.length;

  if (errors === 0) {
    console.log("\n✅ 点位父 (列) 与布局 (path/depth/side) 完全一致, 无冲突");
  } else {
    console.log(`\n⚠️ 共 ${errors} 处不一致, 需人工处理`);
  }

  if (STRICT && errors > 0) process.exit(1);
  process.exit(0);
}

main().catch((e) => {
  console.error("💥", e);
  process.exit(1);
});
