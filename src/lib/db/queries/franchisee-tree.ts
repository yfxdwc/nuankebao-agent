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
 *   - 层级**不限** (ADR-0011, 主人 2026-09-18 拍: 「层级不应该做限制, 理论上可以无限层级」)
 *     历史: ADR-0006 ≤3 层 (合规保守) → ADR-0010 ≤4 (dev seed 需求) → ADR-0011 不限
 *   - 运维手闸: env FRANCHISEE_MAX_DEPTH=7 可临时重新封顶 (默认 0 = 不限)
 *   - 返回 fallback=true 让 frontend 提示"已自动放到 XXX"
 */
export async function placeNewFranchisee(
  tx: TxType,
  referrerId: bigint,
  sideHint?: PlacementSide
): Promise<PlaceResult> {
  // ADR-0011 (主人 2026-09-18 拍): 层级不限
  //   - 原本 ADR-0010 硬限 4 层; 主人指出「层级理论上可以无限」→ 去掉业务上限
  //   - 合规依据见 ADR-0006 (关系展示/客户维护, 不做团队计酬/入门费/拉人头返利 →
  //     层级深度本身不构成《禁止传销条例》意义上的传销)
  //   - 仍需拦超深数据用 env 手闸 (FRANCHISEE_MAX_DEPTH), 默认 0=不限
  const MAX_DEPTH = Number(process.env.FRANCHISEE_MAX_DEPTH ?? "0") || 0;
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

  if (MAX_DEPTH > 0 && ref.depth >= MAX_DEPTH) {
    throw new Error(
      `加盟树深度上限 ${MAX_DEPTH} 层 (运维手闸 FRANCHISEE_MAX_DEPTH), referrer depth=${ref.depth}`
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
  //   ADR-0011: 不再按层剪枝 (层级不限) → BFS 会一直下降到第一个空位
  //   (历史 ADR-0010 曾跳过 depth >= MAX_DEPTH 的子节点; 现仅在运维手闸开启时跳过)
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

    // 左右都满 → 继续下降 (层级不限; MAX_DEPTH > 0 时按手闸剪枝)
    for (const child of children) {
      if (MAX_DEPTH === 0 || (child as any).depth < MAX_DEPTH) {
        queue.push((child as any).id);
      }
    }
  }

  throw new Error(
    MAX_DEPTH > 0
      ? `加盟树已达运维手闸上限 ${MAX_DEPTH} 层 (FRANCHISEE_MAX_DEPTH), 找不到空位`
      : "placeNewFranchisee: No available position (should never happen)"
  );
}