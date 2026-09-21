// ============================================
// 历史加盟节点补录「已确认」记录 (主人 2026-09-18 拍 Q6)
//
// 背景: 三方确认工作流是 2026-09-18 新加的; 之前已存在的节点 (种子 31 + 主人后加的)
//       没有申请单/确认记录 → 按主人拍板: **补录** 一条 executed 单 + 一条
//       initiator 确认 (verified_by='backfill'), 让历史数据在审计上可追溯。
//
// 跑: npx tsx scripts/backfill-placement-confirms.ts [--dry-run]
// 幂等: 同一 result_fid 已补录过就跳过 (可重复跑)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { and, eq, isNull, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  franchisee,
  franchisePlacementConfirm,
  franchisePlacementRequest,
} from "@/lib/db/schema";

const DRY = process.argv.includes("--dry-run");

/** 'L.L.R.' → 'L.' ; 'L.' → '' ; '' → null */
function parentPathOf(path: string): string | null {
  const segs = path.split(".").filter(Boolean);
  if (segs.length === 0) return null;
  segs.pop();
  return segs.length === 0 ? "" : segs.join(".") + ".";
}

async function main() {
  const nodes = await db
    .select({
      id: franchisee.id,
      name: franchisee.name,
      path: franchisee.placementPath,
      depth: franchisee.placementDepth,
      referrerId: franchisee.referrerId,
      createdBy: franchisee.createdBy,
    })
    .from(franchisee)
    .where(and(isNull(franchisee.deletedAt), sql`${franchisee.placementPath} <> ''`))
    .orderBy(franchisee.placementPath);

  console.log(`待检查节点: ${nodes.length} 个 (DRY=${DRY})`);

  let created = 0;
  let skipped = 0;

  for (const n of nodes) {
    // 幂等: 这个节点是否已有补录单
    const [existing] = await db
      .select({ id: franchisePlacementRequest.id })
      .from(franchisePlacementRequest)
      .where(
        and(
          eq(franchisePlacementRequest.resultFid, n.id),
          eq(franchisePlacementRequest.backfilled, true)
        )
      )
      .limit(1);
    if (existing) {
      skipped++;
      continue;
    }

    const parentPath = parentPathOf(n.path);
    let parentId: bigint | null = null;
    if (parentPath != null) {
      const [p] = await db
        .select({ id: franchisee.id })
        .from(franchisee)
        .where(
          and(
            eq(franchisee.placementPath, parentPath),
            isNull(franchisee.deletedAt)
          )
        )
        .limit(1);
      parentId = p?.id ?? null;
    }
    // 设置者: 优先用 referrer_id (推荐人), 退化到点位父节点
    const initiatorFid = n.referrerId ?? parentId ?? n.id;
    const side = n.path.endsWith("R.") ? "right" : "left";

    if (DRY) {
      console.log(
        `  [dry] #${n.id} ${n.name} path=${n.path} → 补录 (initiator=${initiatorFid}, parent=${parentId ?? "-"})`
      );
      created++;
      continue;
    }

    const now = new Date();
    const [req] = await db
      .insert(franchisePlacementRequest)
      .values({
        kind: "create",
        status: "executed",
        initiatorFid,
        initiatorUserId: n.createdBy,
        newName: n.name,
        targetParentFid: parentId ?? n.id,
        targetSide: side,
        resultFid: n.id,
        backfilled: true,
        expiresAt: now,
        executedAt: now,
      })
      .returning({ id: franchisePlacementRequest.id });

    await db.insert(franchisePlacementConfirm).values({
      requestId: req.id,
      confirmerRole: "initiator",
      confirmerFid: initiatorFid,
      confirmerUserId: n.createdBy,
      decision: "approve",
      verifiedBy: "backfill",
    });
    created++;
  }

  console.log(`✓ 补录 ${created} 条, 跳过 ${skipped} 条 (已补录过)`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
