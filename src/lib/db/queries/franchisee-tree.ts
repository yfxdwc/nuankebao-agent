// ============================================
// 二叉树填位算法 (Plan F1 决策 3C)
// 策略: 推荐人手选 left/right (hint), 空就填; 不空 fallback BFS 左优先 (子节点按点位父列找)
// 并发: SELECT FOR UPDATE 锁父节点
//
// ⚠ 导航口径 (主人 2026-09-21 拍"拆栏"后改): **只认 `placement_parent_id` (点位父)**,
//   不再认 `referrer_id` (推荐人)。
//   老实现的坑: 按 referrer_id 找子节点 —— 而 `referrer_id` 是"谁推荐了她",
//     三方确认落位时 发起人 ≠ 落位父 (见 franchisee-placement.ts), 于是
//     ① 落位父名下明明有人, 这里却看成空位 → 生成两条相同 placement_path 的节点
//     ② BFS 顺着推荐树乱走, 把人放到不相干的枝上
//   现在两栏分家 (migration 0019), 点位算法读 `placement_parent_id`, 推荐关系读 `referrer_id`。
//   函数开头还有一道"缺列保护": 本树里若有 path ≠ '' 却 placement_parent_id IS NULL 的活节点
//   (= 0019 回填没跑完), 直接报错 —— 不准静默产出重复位置。
// ============================================

import { and, eq, isNull, ne } from "drizzle-orm";
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
 * @param referrerId 起点节点 franchisee.id —— 调用方给的是**推荐人** (她选的位置 hint 在她名下);
 *                   ⚠ 本函数只用它当 BFS 起点, 找子节点一律按 `placement_parent_id` (点位父)
 * @param sideHint 推荐人选的位置 hint ('left' | 'right'), 可选
 *
 * 行为:
 *   1. 如果有 sideHint, 尝试该位置, 空就返回
 *   2. 该位置已满 → fallback 到 BFS 左优先
 *   3. BFS 找最近的空 left → 空 right → 递归下一层
 *
 * 边界:
 *   - referrerId 必须存在 (调用方保证)
 *   - 该树里不能有"缺点位父列"的活节点 —— 有就当场报错 (migration 0019 的回填前提, 见第 0 步)
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
    .select({
      id: franchisee.id,
      depth: franchisee.placementDepth,
      rootId: franchisee.rootId,
      path: franchisee.placementPath,
    })
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

  // 0. 缺列保护 (migration 0019 拆栏的前提, 主人 2026-09-21)
  //    `placement_parent_id` 是 0019 新加的列, 存量行由 migration 回填。
  //    这棵树里只要还有「非根节点 (path ≠ '') 但点位父列为 NULL」的行, 就说明回填没跑完 ——
  //    按列导航会**看不见**那棵子树, 于是把"已经有人"的位子当成空的 → 同一层两个位子坐两个人
  //    (拆栏前的老 bug 换个姿势复发)。宁可当场报错, 也不要静默产出坏数据。
  const [stale] = await tx
    .select({ id: franchisee.id, path: franchisee.placementPath })
    .from(franchisee)
    .where(
      and(
        eq(franchisee.rootId, ref.rootId),
        isNull(franchisee.placementParentId),
        isNull(franchisee.deletedAt),
        ne(franchisee.placementPath, "")
      )
    )
    .limit(1);

  if (stale) {
    throw new Error(
      `加盟树数据没回填好: 节点 #${stale.id} (path="${stale.path}") 没有 placement_parent_id。` +
        ` 落位算法按「点位父」列导航, 会看不见这棵子树并生成重复位置。` +
        ` 请先跑 pnpm db:migrate 回填, 再跑 npx tsx scripts/audit-placement-integrity.ts 复核。`
    );
  }

  if (MAX_DEPTH > 0 && ref.depth >= MAX_DEPTH) {
    throw new Error(
      `加盟树深度上限 ${MAX_DEPTH} 层 (运维手闸 FRANCHISEE_MAX_DEPTH), referrer depth=${ref.depth}`
    );
  }

  // 1. 如果有 hint, 尝试该位置
  //    "这个位置有没有人" = 有没有**点位父是她、且落在这一侧**的节点 (按点位父列判)
  if (sideHint) {
    const occupied = await tx
      .select({ id: franchisee.id })
      .from(franchisee)
      .where(
        and(
          eq(franchisee.placementParentId, referrerId),
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

    // SELECT FOR UPDATE 锁父节点的所有直接子 (按点位父列找子)
    const children = await tx
      .select({ id: franchisee.id, side: franchisee.placementSide, depth: franchisee.placementDepth })
      .from(franchisee)
      .where(
        and(
          eq(franchisee.placementParentId, parentId),
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