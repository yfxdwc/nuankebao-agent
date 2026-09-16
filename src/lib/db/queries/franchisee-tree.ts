// ============================================
// 二叉树填位算法 (Plan F1 决策 3C)
// 策略: 推荐人手选 left/right, 空就填; 不空 fallback BFS 左优先
// 并发: SELECT FOR UPDATE 锁父节点
// ============================================

import { and, eq, isNull } from "drizzle-orm";
import { franchisee } from "@/lib/db/schema";
import type { PlacementSide } from "@/lib/db/schema";

// Postgres 事务类型 (避免 import 循环)
type TxType = {
  select: (...args: any[]) => any;
  update: (...args: any[]) => any;
};

export interface PlaceResult {
  parentId: bigint;
  side: PlacementSide;
  fallback: boolean; // true = 推荐人位置已满, 自动 fallback BFS
}

/**
 * 找最近的空位
 *
 * @param tx Drizzle 事务对象
 * @param referrerId 推荐人 franchisee.id
 * @param sideHint 推荐人选的位置 hint ('left' | 'right'), 可选
 *
 * 行为:
 *   1. 如果有 sideHint, 尝试该位置, 空就返回
 *   2. 该位置已满 → fallback 到 BFS 左优先
 *   3. BFS 找最近的空 left → 空 right → 递归下一层
 *
 * 边界:
 *   - referrerId 必须存在 (调用方保证)
 *   - 二叉树深度上限 4 层 (主人 2026-09-16 override, ADR-0010)
 *     历史: 3 层 → 4 层 (test data 单 tree 31 节点需求, dev/test only)
 *   - 返回 fallback=true 让 frontend 提示"已自动放到 XXX"
 */
export async function placeNewFranchisee(
  tx: TxType,
  referrerId: bigint,
  sideHint?: PlacementSide
): Promise<PlaceResult> {
  // ADR-0010: 主人 2026-09-16 override, ≤4 层硬约束 (dev/test seed data)
  //   - 目的: 1 个 tree 装 31 节点 (1+2+4+8+16), 满足主人「30+ 加盟商」需求
  //   - 边界: referrer depth >= 4 不能添加下线 (depth 4 节点不允许有子)
  //   - 风险: ADR-0006 合规边界放宽 1 层, 仍 < 5 (《禁止传销条例》实务解读 5+ 才入刑)
  //   - 回滚: 删 ADR-0010 + 把 4 改回 3 (1 行). depth=4 节点保留可查, 但不能再加子
  const MAX_DEPTH = 4; // ADR-0010 override; revert: 改回 3
  const [ref] = await tx
    .select({ id: franchisee.id, depth: franchisee.placementDepth })
    .from(franchisee)
    .where(
      and(
        eq(franchisee.id, referrerId),
        isNull(franchisee.deletedAt)
      )
    )
    .limit(1);

  if (!ref) {
    throw new Error(`Referrer not found: ${referrerId}`);
  }

  if (ref.depth >= MAX_DEPTH) {
    throw new Error(
      `加盟树深度上限 ${MAX_DEPTH} 层, 不能再添加下线 (ADR-0010 主人 override, referrer depth=${ref.depth})`
    );
  }

  // 1. 如果有 hint, 尝试该位置
  if (sideHint) {
    const occupied = await tx
      .select({ id: franchisee.id })
      .from(franchisee)
      .where(
        and(
          eq(franchisee.referrerId, referrerId),
          eq(franchisee.placementSide, sideHint),
          isNull(franchisee.deletedAt)
        )
      )
      .for("update"); // SELECT FOR UPDATE 锁行

    if (occupied.length === 0) {
      return { parentId: referrerId, side: sideHint, fallback: false };
    }
  }

  // 2. Fallback: BFS 左优先
  //   Bug fix (2026-09-16, task seed-test-data): 只检查 input.referrerId depth 不足
  //   BFS 下降到的节点 也需 depth < MAX_DEPTH — 否则叶子节点 (depth=MAX) 被当 parent,
  //   newDepth = MAX+1 > MAX_DEPTH 超限. 修法: 不把 depth >= MAX_DEPTH 的子节点 push 进 queue.
  const queue: bigint[] = [referrerId];
  while (queue.length > 0) {
    const parentId = queue.shift()!;

    // SELECT FOR UPDATE 锁父节点的所有直接子
    const children = await tx
      .select({ id: franchisee.id, side: franchisee.placementSide, depth: franchisee.placementDepth })
      .from(franchisee)
      .where(
        and(
          eq(franchisee.referrerId, parentId),
          isNull(franchisee.deletedAt)
        )
      )
      .for("update");

    const leftChild = children.find((c: any) => c.side === "left");
    const rightChild = children.find((c: any) => c.side === "right");

    if (!leftChild) {
      return { parentId, side: "left", fallback: !!sideHint };
    }
    if (!rightChild) {
      return { parentId, side: "right", fallback: !!sideHint };
    }

    // 左右都满, 递归下一层. 跳过 depth >= MAX_DEPTH 的子节点 (它们是叶子, 不能当 parent).
    for (const child of children) {
      if ((child as any).depth < MAX_DEPTH) {
        queue.push((child as any).id);
      }
    }
  }

  throw new Error(
    "placeNewFranchisee: No available position (should never happen)"
  );
}