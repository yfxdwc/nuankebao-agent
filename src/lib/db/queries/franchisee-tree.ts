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
 *   - 二叉树深度理论无限 (W5 RBAC 时再加 ≤3 层硬约束)
 *   - 返回 fallback=true 让 frontend 提示"已自动放到 XXX"
 */
export async function placeNewFranchisee(
  tx: TxType,
  referrerId: bigint,
  sideHint?: PlacementSide
): Promise<PlaceResult> {
  // W5 RBAC: ≤3 层硬约束 (ADR-0006 / 《禁止传销条例》)
  // referrer depth >= 3 不能添加下线 (DB CHECK 也会拒, 这是双层防御)
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

  if (ref.depth >= 3) {
    throw new Error(
      `加盟树深度上限 3 层, 不能再添加下线 (ADR-0006 红线, referrer depth=${ref.depth})`
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
  const queue: bigint[] = [referrerId];
  while (queue.length > 0) {
    const parentId = queue.shift()!;

    // SELECT FOR UPDATE 锁父节点的所有直接子
    const children = await tx
      .select({ id: franchisee.id, side: franchisee.placementSide })
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

    // 左右都满, 递归下一层
    if (leftChild) queue.push((leftChild as any).id);
    if (rightChild) queue.push((rightChild as any).id);
  }

  throw new Error(
    "placeNewFranchisee: No available position (should never happen)"
  );
}