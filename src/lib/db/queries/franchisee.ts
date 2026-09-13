// ============================================
// 加盟商 CRUD + 树查询
// Plan F1 + ADR-0006 边界: 纯展示, 不算钱 / 不算业绩 / 不算提成
// ============================================

import { db } from "@/lib/db";
import {
  franchisee,
  user,
  type Franchisee,
  type NewFranchisee,
  type PlacementSide,
} from "@/lib/db/schema";
import { eq, isNull, and, desc, sql, ilike, or, ne, like, type SQL } from "drizzle-orm";
import {
  encryptField,
  decryptField,
  hashForLookup,
} from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { franchiseeRbacFilter, type RbacContext } from "@/lib/auth/rbac";
import { placeNewFranchisee } from "./franchisee-tree";

// ============================================
// 类型 (API 层用, 包含解密的明文)
// ============================================

export interface FranchiseeView {
  id: string;
  name: string;
  phone: string;
  referrerId: string | null;
  placementSide: PlacementSide | null;
  placementPath: string;
  placementDepth: number;
  joinedAt: Date;
  isActive: boolean;
  notes: string | null;
  createdAt: Date;
  updatedAt: Date;
}

function toView(row: Franchisee): FranchiseeView {
  return {
    id: row.id.toString(),
    name: row.name,
    phone: decryptField(row.phoneEncrypted),
    referrerId: row.referrerId ? row.referrerId.toString() : null,
    placementSide: row.placementSide as PlacementSide | null,
    placementPath: row.placementPath,
    placementDepth: row.placementDepth,
    joinedAt: row.joinedAt,
    isActive: row.isActive,
    notes: row.notesEncrypted ? decryptField(row.notesEncrypted) : null,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

export interface CreateFranchiseeInput {
  name: string;
  phone: string;
  referrerId?: bigint; // null = root (仅 master admin 可)
  sideHint?: PlacementSide; // 决策 3C: 推荐人手选
  notes?: string;
}

export interface UpdateFranchiseeInput {
  name?: string;
  phone?: string;
  notes?: string;
  isActive?: boolean;
}

export interface ListFranchiseesOptions {
  scope?: "mine_downline" | "mine_referrer" | "search" | "all";
  search?: string;
  referrerId?: bigint;
  /**当前 user 的 franchiseeId (用于 scope=mine_downline / mine_referrer) */
  currentFranchiseeId?: bigint;
  limit?: number;
  offset?: number;
  includeDeleted?: boolean;
  // W5 RBAC: 行级过滤上下文
  rbacCtx?: RbacContext;
}

export interface PlaceResult {
  parentId: bigint;
  side: PlacementSide;
  fallback: boolean;
}

// ============================================
// CRUD
// ============================================

/**
 * 创建加盟商
 * 步骤:
 *   1. 查 referrerId 是否有效
 *   2. 调 placeNewFranchisee 算法找位置
 *   3. 计算 placement_path / placement_depth
 *   4. INSERT franchisee
 *   5. INSERT user (1:1 强约束)
 *   6. UPDATE user.franchisee_id
 */
export async function createFranchisee(
  input: CreateFranchiseeInput,
  ctx: AuditContext,
  createdBy: bigint
): Promise<FranchiseeView> {
  return await withAuditContext(ctx, async (tx) => {
    // 1. 找位置
    let placement: PlaceResult;
    if (input.referrerId) {
      placement = await placeNewFranchisee(
        tx,
        input.referrerId,
        input.sideHint
      );
    } else {
      // root: 只允许无 referrer_id
      placement = { parentId: BigInt(0), side: "left", fallback: false };
    }

    // 2. 计算 path / depth
    let newPath: string;
    let newDepth: number;
    let newReferrerId: bigint | null;
    let newSide: PlacementSide | null;

    if (input.referrerId) {
      const [parent] = await tx
        .select()
        .from(franchisee)
        .where(eq(franchisee.id, placement.parentId))
        .limit(1);

      if (!parent) {
        throw new Error(`Referrer not found: ${placement.parentId}`);
      }

      newReferrerId = placement.parentId;
      newSide = placement.side;
      newPath = parent.placementPath + (placement.side === "left" ? "L." : "R.");
      newDepth = parent.placementDepth + 1;
    } else {
      newReferrerId = null;
      newSide = null;
      newPath = "";
      newDepth = 0;
    }

    // 3. INSERT franchisee
    const encryptedData: NewFranchisee = {
      name: input.name,
      phoneEncrypted: encryptField(input.phone),
      phoneHash: hashForLookup(input.phone),
      referrerId: newReferrerId,
      placementSide: newSide,
      placementPath: newPath,
      placementDepth: newDepth,
      isActive: true,
      notesEncrypted: input.notes ? encryptField(input.notes) : null,
      createdBy,
    };

    const [newFranchiseeRow] = await tx
      .insert(franchisee)
      .values(encryptedData)
      .returning();

    return toView(newFranchiseeRow);
  });
}

export async function getFranchiseeById(
  id: bigint,
  options?: { includeDeleted?: boolean }
): Promise<FranchiseeView | null> {
  const conditions = options?.includeDeleted
    ? eq(franchisee.id, id)
    : and(eq(franchisee.id, id), isNull(franchisee.deletedAt));

  const [row] = await db
    .select()
    .from(franchisee)
    .where(conditions)
    .limit(1);

  return row ? toView(row) : null;
}

export async function listFranchisees(
  options: ListFranchiseesOptions = {}
): Promise<{ items: FranchiseeView[]; total: number }> {
  const {
    scope = "all",
    search,
    referrerId,
    currentFranchiseeId,
    limit = 20,
    offset = 0,
    includeDeleted = false,
    rbacCtx,
  } = options;

  const conditions: SQL[] = [];

  if (!includeDeleted) {
    conditions.push(isNull(franchisee.deletedAt));
  }

  // scope 过滤
  if (scope === "mine_referrer" && currentFranchiseeId) {
    const me = await db
      .select({ referrerId: franchisee.referrerId })
      .from(franchisee)
      .where(eq(franchisee.id, currentFranchiseeId))
      .limit(1);

    if (me[0]?.referrerId) {
      conditions.push(eq(franchisee.id, me[0].referrerId));
    } else {
      return { items: [], total: 0 };
    }
  } else if (scope === "mine_downline" && currentFranchiseeId) {
    conditions.push(eq(franchisee.referrerId, currentFranchiseeId));
  } else if (referrerId) {
    conditions.push(eq(franchisee.referrerId, referrerId));
  }

  if (search) {
    const phoneHash = hashForLookup(search);
    conditions.push(
      or(
        ilike(franchisee.name, `%${search}%`),
        eq(franchisee.phoneHash, phoneHash)
      )!
    );
  }

  // W5 RBAC: 行级过滤 (Q4-A)
  if (rbacCtx) {
    const rbacFilter = await franchiseeRbacFilter(rbacCtx);
    if (rbacFilter) {
      conditions.push(rbacFilter);
    }
  }

  const whereClause = conditions.length > 0 ? and(...conditions) : undefined;

  const [rows, [{ count }]] = await Promise.all([
    db
      .select()
      .from(franchisee)
      .where(whereClause)
      .orderBy(desc(franchisee.createdAt))
      .limit(limit)
      .offset(offset),
    db
      .select({ count: sql<number>`count(*)::int` })
      .from(franchisee)
      .where(whereClause),
  ]);

  return {
    items: rows.map(toView),
    total: count,
  };
}

export async function updateFranchisee(
  id: bigint,
  input: UpdateFranchiseeInput,
  ctx: AuditContext
): Promise<FranchiseeView | null> {
  const updateData: Partial<NewFranchisee> = { updatedAt: new Date() };

  if (input.name !== undefined) updateData.name = input.name;
  if (input.phone !== undefined) {
    updateData.phoneEncrypted = encryptField(input.phone);
    updateData.phoneHash = hashForLookup(input.phone);
  }
  if (input.notes !== undefined) {
    updateData.notesEncrypted = input.notes ? encryptField(input.notes) : null;
  }
  if (input.isActive !== undefined) updateData.isActive = input.isActive;

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(franchisee)
      .set(updateData)
      .where(and(eq(franchisee.id, id), isNull(franchisee.deletedAt)))
      .returning();
  });

  return row ? toView(row) : null;
}

export async function softDeleteFranchisee(
  id: bigint,
  ctx: AuditContext
): Promise<boolean> {
  const result = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(franchisee)
      .set({ deletedAt: new Date() })
      .where(and(eq(franchisee.id, id), isNull(franchisee.deletedAt)))
      .returning({ id: franchisee.id });
  });
  return result.length > 0;
}

// ============================================
// 树查询
// ============================================

export interface TreeNode {
  id: string;
  name: string;
  placementSide: PlacementSide | null;
  placementDepth: number;
  children: TreeNode[];
}

/**
 * 以 rootId 为中心, 向下载 depth 层
 * 用 placement_path LIKE 递归查子树 (避免 N+1)
 */
export async function getFranchiseeTree(
  rootId: bigint,
  depth: number = 3
): Promise<TreeNode | null> {
  // 查 root
  const [root] = await db
    .select()
    .from(franchisee)
    .where(and(eq(franchisee.id, rootId), isNull(franchisee.deletedAt)))
    .limit(1);

  if (!root) return null;

  // 查所有子树 (递归 path LIKE)
  // root.path = '' → 所有非 root 节点的 path 都以 'L' 或 'R' 开头
  // depth = 1 → path LIKE 'L.%' OR 'R.%' (depth 1)
  // depth = 2 → path LIKE 'L.%.%' OR 'R.%.%'... 用正则
  const pathPrefix = root.placementPath;

  // 简单做法: 查所有 path 起始于 root.path 的节点, 然后在应用层剪枝
  const allDescendants = await db
    .select({
      id: franchisee.id,
      name: franchisee.name,
      placementSide: franchisee.placementSide,
      placementPath: franchisee.placementPath,
      placementDepth: franchisee.placementDepth,
      referrerId: franchisee.referrerId,
    })
    .from(franchisee)
    .where(
      and(
        isNull(franchisee.deletedAt),
        // path 是 '' (root) 时, 所有非 root 都是子孙
        // path 非 '' 时, 找 path 以 root.path 开头的节点
        root.placementPath === ""
          ? ne(franchisee.placementPath, "")
          : like(franchisee.placementPath, pathPrefix + "%")
      )
    )
    .orderBy(franchisee.placementPath);

  // 应用层剪枝到 depth 层 + 构建树
  return buildTree(
    {
      id: root.id.toString(),
      name: root.name,
      placementSide: root.placementSide as PlacementSide | null,
      placementDepth: root.placementDepth,
      placementPath: root.placementPath,
      referrerId: root.referrerId?.toString() ?? null,
    },
    allDescendants.map((r) => ({
      id: r.id.toString(),
      name: r.name,
      placementSide: r.placementSide as PlacementSide | null,
      placementDepth: r.placementDepth,
      placementPath: r.placementPath,
      referrerId: r.referrerId?.toString() ?? null,
    })),
    depth
  );
}

interface RawNode {
  id: string;
  name: string;
  placementSide: PlacementSide | null;
  placementDepth: number;
  placementPath: string;
  referrerId: string | null;
}

function buildTree(root: RawNode, descendants: RawNode[], depthRemaining: number): TreeNode {
  // 过滤直接子节点
  const childrenRaw = descendants.filter(
    (n) => n.referrerId === root.id
  );

  // 深度限制: 子节点的 placementDepth 不超过 root.placementDepth + depthRemaining
  const maxDepth = root.placementDepth + depthRemaining;
  const validChildren = childrenRaw.filter(
    (n) => n.placementDepth <= maxDepth
  );

  // 递归时 depthRemaining - 1 (因为子节点比父节点深 1 层)
  const children: TreeNode[] = validChildren.map((c) => {
    if (depthRemaining <= 1) {
      // 边界: 子节点不递归
      return {
        id: c.id,
        name: c.name,
        placementSide: c.placementSide,
        placementDepth: c.placementDepth,
        children: [],
      };
    }
    return buildTree(c, descendants, depthRemaining - 1);
  });

  return {
    id: root.id,
    name: root.name,
    placementSide: root.placementSide,
    placementDepth: root.placementDepth,
    children,
  };
}

/**
 * 获取推荐放置位置 (frontend preview)
 * 不实际写入, 只返回推荐位置 + fallback 标志
 */
export async function getAvailablePosition(
  referrerId: bigint
): Promise<{ leftOccupied: boolean; rightOccupied: boolean }> {
  const children = await db
    .select({ side: franchisee.placementSide })
    .from(franchisee)
    .where(
      and(eq(franchisee.referrerId, referrerId), isNull(franchisee.deletedAt))
    );

  return {
    leftOccupied: children.some((c) => c.side === "left"),
    rightOccupied: children.some((c) => c.side === "right"),
  };
}

/**
 * 查 user.franchisee_id (用于 scope=mine_* 时)
 */
export async function getFranchiseeIdByUserId(userId: bigint): Promise<bigint | null> {
  const [u] = await db
    .select({ franchiseeId: user.franchiseeId })
    .from(user)
    .where(eq(user.id, userId))
    .limit(1);

  return u?.franchiseeId ?? null;
}