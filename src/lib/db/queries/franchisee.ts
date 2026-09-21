// ============================================
// 加盟商 CRUD + 树查询
// Plan F1 + ADR-0006 边界: 纯展示, 不算钱 / 不算业绩 / 不算提成
// ============================================

import { db } from "@/lib/db";
import {
  franchisee,
  customer,
  user,
  type Franchisee,
  type NewFranchisee,
  type PlacementSide,
} from "@/lib/db/schema";
import { eq, isNull, and, desc, sql, ilike, or, ne, like, inArray, type SQL } from "drizzle-orm";
import {
  encryptField,
  decryptField,
  hashForLookup,
} from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { logger } from "@/lib/errors";
import {
  assertNodeHasAccount,
  linkAccountAndCustomer,
  requireAccountForNode,
} from "./franchisee-account";
import { franchiseeRbacFilter, type RbacContext } from "@/lib/auth/rbac";
import { memberExistsSql } from "@/lib/billing/member-flag";
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
 *   0. **节点 ⇒ 账号** 门槛 (主人 2026-09-21 拍): 该手机号必须已有账号, 否则直接拒
 *   1. 查 referrerId 是否有效
 *   2. 调 placeNewFranchisee 算法找位置
 *   3. 计算 placement_path / placement_depth
 *   4. INSERT franchisee
 *   5. 绑账号 (user.franchisee_id) + 落客户档案 + 自检绑定成功
 */
export async function createFranchisee(
  input: CreateFranchiseeInput,
  ctx: AuditContext,
  createdBy: bigint
): Promise<FranchiseeView> {
  const view = await withAuditContext(ctx, async (tx) => {
    // 0. 节点必须对应一个账号 (主人 2026-09-21 拍)
    await requireAccountForNode(tx, hashForLookup(input.phone));

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
    let newRootId: bigint | null;

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
      // 同树 (B1): 跟着落位的父节点走
      newRootId = parent.rootId ?? parent.id;
    } else {
      newReferrerId = null;
      newSide = null;
      newPath = "";
      newDepth = 0;
      newRootId = null; // 新根 → INSERT 后自指 (见下)
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
      rootId: newRootId,
      isActive: true,
      notesEncrypted: input.notes ? encryptField(input.notes) : null,
      createdBy,
    };

    let [newFranchiseeRow] = await tx
      .insert(franchisee)
      .values(encryptedData)
      .returning();

    // 新根: root_id 自指 (INSERT 时没有 id, 只能建完补)
    if (newRootId == null) {
      [newFranchiseeRow] = await tx
        .update(franchisee)
        .set({ rootId: newFranchiseeRow.id, updatedAt: sql`NOW()` })
        .where(eq(franchisee.id, newFranchiseeRow.id))
        .returning();
    }

    // 4. 打通: 绑账号 + 加盟商同步落一份客户档案 (主人 2026-09-18 拍, 方案 A)
    //    - 同一事务 → 任一步失败一起回滚 (不会出现“有加盟商没客户/没账号”)
    //    - onConflictDoNothing: 同手机号已有客户 → 保留客户侧数据 (幂等)
    //    - 审计: customer 表有 audit trigger, 写入自动进 audit_log
    await linkAccountAndCustomer(tx, {
      fid: newFranchiseeRow.id,
      phoneHash: newFranchiseeRow.phoneHash,
      phoneEncrypted: newFranchiseeRow.phoneEncrypted,
      name: input.name,
      createdBy,
    });
    // 节点 ⇒ 账号 不变量: 建完必须真绑上 (没有 → 回滚)
    await assertNodeHasAccount(tx, newFranchiseeRow.id, "新加盟节点");

    return toView(newFranchiseeRow);
  });

  // 会员推荐奖励 (ADR-0012 D23): 被推荐人成为加盟者 → 给推荐人 15 天会员权益
  //   为什么不放事务里: grantDays 自己开事务 (不可嵌套); 奖励失败也不能回滚落位
  try {
    const { exitRewardIfReferral } = await import("@/lib/billing/entitlements");
    await exitRewardIfReferral({ newFranchiseePhoneHash: hashForLookup(input.phone) });
  } catch (e) {
    logger.error("billing: referral reward failed (ignored)", {}, e);
  }

  return view;
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

export type TreeNodeRelation = "root" | "direct" | "downline" | "upline";

export interface TreeNode {
  id: string;
  name: string;
  placementSide: PlacementSide | null;
  placementDepth: number;
  /** 谁推荐加盟的 (= 直推判定源). null = 无推荐人 (root / 数据异常) */
  referrerId: string | null;
  /**
   * 相对当前树 root 的关系 (客户图谱三维区分用):
   *   root     = 我自己 (树根)
   *   direct   = 直推 (referrerId == 我)
   *   downline = 下级引荐 (referrerId 是我的下线 → 在我的 placement 子树里)
   *   upline   = 上级引荐 (referrerId 不在我的子树里, 含 null 异常数据)
   */
  relation: TreeNodeRelation;
  children: TreeNode[];
  /**
   * 该节点是否有下级 (全深度真值, 不受本次 depth 限制) — 图谱懒加载用 (ADR-0011):
   *   true + children=[] → 前端显示「展开下级」按钮, 点了再请求子级
   */
  hasChildren: boolean;
  /**
   * 仅树根节点有: 我的下级**全深度总数** (不受 depth 影响)
   * — 图谱顶部「共 N 位」用这个, 避免懒加载后数字缩水
   */
  totalDescendants?: number;
  /**
   * 会员标识 (主人 2026-09-21 拍: 「会员在别人的图谱里也要有明显标识」)
   *   口径 = 该节点**绑定账号**的会员状态 (role='admin' 或 member_until > now()),
   *   见 src/lib/billing/member-flag.ts。没有账号的节点恒 false。
   *   ★ 每次查询现算 (不落库) → 充值 / 到期后下次拉树即变, 无需同步任务
   */
  member: boolean;
}

interface BuildCtx {
  rootId: string;
  /** 不限深度的「我」的 placement 子树 id 集 (判 downline / upline 用) */
  subtreeIds: Set<string>;
}

function classifyRelation(
  nodeId: string,
  referrerId: string | null,
  ctx: BuildCtx
): TreeNodeRelation {
  if (nodeId === ctx.rootId) return "root";
  if (referrerId == null) return "upline";
  if (referrerId === ctx.rootId) return "direct";
  return ctx.subtreeIds.has(referrerId) ? "downline" : "upline";
}

/** placement_path 最后一段 → 左/右侧 ('L.L.' → left) */
function sideFromPath(path: string): PlacementSide | null {
  const segs = path.split(".").filter(Boolean);
  if (segs.length === 0) return null;
  return segs[segs.length - 1] === "L" ? "left" : "right";
}

/** 'L.L.' → 'L.' (root 的子节点 path 的 parent = '') */
function parentPath(path: string): string | null {
  const segs = path.split(".").filter(Boolean);
  if (segs.length === 0) return null;
  segs.pop();
  return segs.length === 0 ? "" : segs.join(".") + ".";
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
    .select({
      id: franchisee.id,
      name: franchisee.name,
      placementSide: franchisee.placementSide,
      placementPath: franchisee.placementPath,
      placementDepth: franchisee.placementDepth,
      referrerId: franchisee.referrerId,
      rootId: franchisee.rootId,
      member: memberExistsSql(sql`u.franchisee_id = ${franchisee.id}`),
    })
    .from(franchisee)
    .where(and(eq(franchisee.id, rootId), isNull(franchisee.deletedAt)))
    .limit(1);

  if (!root) return null;

  // 查所有子树 (递归 path LIKE)
  // root.path = '' → 所有非 root 节点的 path 都以 'L' 或 'R' 开头
  // depth = 1 → path LIKE 'L.%' OR 'R.%' (depth 1)
  // depth = 2 → path LIKE 'L.%.%' OR 'R.%.%'... 用正则
  const pathPrefix = root.placementPath;
  // ⚠ 多根 (B1): path 只在根内唯一 → 必须同时限定 root_id, 否则根的 '所有 path<>'' 的节点'
  //   会把别的树整棵吞进来
  const rootIdOf = root.rootId;

  // 简单做法: 查所有 path 起始于 root.path 的节点, 然后在应用层剪枝
  const allDescendants = await db
    .select({
      id: franchisee.id,
      name: franchisee.name,
      placementSide: franchisee.placementSide,
      placementPath: franchisee.placementPath,
      placementDepth: franchisee.placementDepth,
      referrerId: franchisee.referrerId,
      member: memberExistsSql(sql`u.franchisee_id = ${franchisee.id}`),
    })
    .from(franchisee)
    .where(
      and(
        isNull(franchisee.deletedAt),
        sql`${franchisee.rootId} IS NOT DISTINCT FROM ${rootIdOf}`,
        // path 是 '' (root) 时, 所有非 root 都是子孙
        // path 非 '' 时, 找 path 以 root.path 开头的节点
        root.placementPath === ""
          ? ne(franchisee.placementPath, "")
          : like(franchisee.placementPath, pathPrefix + "%")
      )
    )
    .orderBy(franchisee.placementPath);

  // 应用层剪枝到 depth 层 + 构建树
  const rows: RawNode[] = allDescendants.map((r) => ({
    id: r.id.toString(),
    name: r.name,
    placementSide: r.placementSide as PlacementSide | null,
    placementDepth: r.placementDepth,
    placementPath: r.placementPath,
    referrerId: r.referrerId?.toString() ?? null,
    member: r.member === true,
  }));
  const ctx: BuildCtx = {
    rootId: root.id.toString(),
    subtreeIds: new Set<string>([
      root.id.toString(),
      ...rows.map((r) => r.id),
    ]),
  };
  return buildTree(
    {
      id: root.id.toString(),
      name: root.name,
      placementSide: root.placementSide as PlacementSide | null,
      placementDepth: root.placementDepth,
      placementPath: root.placementPath,
      referrerId: root.referrerId?.toString() ?? null,
      member: root.member === true,
    },
    rows,
    depth,
    ctx
  );
}

/**
 * 以 rootId 为中心的**二叉树 (placement) 视图** — 客户图谱「对碰」布局用
 *
 * 与 getFranchiseeTree (推荐树, 按 referrerId 连) 的区别:
 *   - 本函数按 placement_path 连父子 → 真正的左右两区二叉树
 *   - 每个节点带 referrerId + relation (直推/下级引荐/上级引荐), 供图谱三维区分
 *
 * 为什么图谱要用 placement 树:
 *   - 「我上级引荐、但放在我下线」的人 referrerId 不是我 → 推荐树里根本看不到;
 *     二叉树里能看到, 并能标成「上级引荐」(主人 2026-09-17 拍板三级区分)
 */
export async function getPlacementTree(
  rootId: bigint,
  depth: number = 3
): Promise<TreeNode | null> {
  const [root] = await db
    .select({
      id: franchisee.id,
      name: franchisee.name,
      placementSide: franchisee.placementSide,
      placementPath: franchisee.placementPath,
      placementDepth: franchisee.placementDepth,
      referrerId: franchisee.referrerId,
      rootId: franchisee.rootId,
      member: memberExistsSql(sql`u.franchisee_id = ${franchisee.id}`),
    })
    .from(franchisee)
    .where(and(eq(franchisee.id, rootId), isNull(franchisee.deletedAt)))
    .limit(1);

  if (!root) return null;

  // 我的 placement 子树全部节点 (不限深度) — 既用于建树, 也用于判 downline/upline
  const rows: RawNode[] = (
    await db
      .select({
        id: franchisee.id,
        name: franchisee.name,
        placementSide: franchisee.placementSide,
        placementPath: franchisee.placementPath,
        placementDepth: franchisee.placementDepth,
        referrerId: franchisee.referrerId,
        member: memberExistsSql(sql`u.franchisee_id = ${franchisee.id}`),
      })
      .from(franchisee)
      .where(
        and(
          isNull(franchisee.deletedAt),
          // 多根 (B1): 同树限定; 少了它, 根用户的图谱会把别的树整棵画进来
          sql`${franchisee.rootId} IS NOT DISTINCT FROM ${root.rootId}`,
          root.placementPath === ""
            ? ne(franchisee.placementPath, "")
            : like(franchisee.placementPath, root.placementPath + "%")
        )
      )
      .orderBy(franchisee.placementPath)
  ).map((r) => ({
    id: r.id.toString(),
    name: r.name,
    placementSide: r.placementSide as PlacementSide | null,
    placementDepth: r.placementDepth,
    placementPath: r.placementPath,
    referrerId: r.referrerId?.toString() ?? null,
    member: r.member === true,
  }));

  const rootRaw: RawNode = {
    id: root.id.toString(),
    name: root.name,
    placementSide: root.placementSide as PlacementSide | null,
    placementDepth: root.placementDepth,
    placementPath: root.placementPath,
    referrerId: root.referrerId?.toString() ?? null,
    member: root.member === true,
  };

  const ctx: BuildCtx = {
    rootId: rootRaw.id,
    subtreeIds: new Set<string>([rootRaw.id, ...rows.map((r) => r.id)]),
  };

  // path → 直接子节点 (path 精确匹配, 不是 LIKE, 避免跨层)
  const childrenByParentPath = new Map<string, RawNode[]>();
  for (const r of rows) {
    const parent = parentPath(r.placementPath);
    if (parent == null) continue;
    const list = childrenByParentPath.get(parent);
    if (list) list.push(r);
    else childrenByParentPath.set(parent, [r]);
  }

  const build = (node: RawNode, depthRemaining: number): TreeNode => {
    const allChildren = childrenByParentPath.get(node.placementPath) ?? [];
    const rawChildren = depthRemaining > 0 ? allChildren : [];
    return {
      id: node.id,
      name: node.name,
      // 侧别以 path 为准 (BFS 填充节点的 placement_side 也跟 path 一致, 但 path 更可靠)
      placementSide: sideFromPath(node.placementPath) ?? node.placementSide,
      placementDepth: node.placementDepth,
      referrerId: node.referrerId,
      relation: classifyRelation(node.id, node.referrerId, ctx),
      children: rawChildren.map((c) => build(c, depthRemaining - 1)),
      // 全深度真值: 本次没取到的子级也算「有下级」→ 前端才知道能不能展开
      hasChildren: allChildren.length > 0,
      member: node.member,
    };
  };

  const tree = build(rootRaw, depth);
  // 树根带全深度下级总数 (懒加载后顶部「共 N 位」不缩水)
  tree.totalDescendants = rows.length;
  return tree;
}

/**
 * 我的「上层点位」= **点位父** (不是推荐码提供人!) —— 主人 2026-09-21 拍.
 *
 * 图谱里画在「我」上面那一个节点 (每个用户有且只有一个上层节点):
 *   - 口径: 我的 `placement_path` 去掉最后一段, 在**同一棵树** (root_id) 里找那个节点
 *   - 我是 app 这棵树的根 (`placement_path === ''`) → 无上层 → 返回 null
 *     (前端画「上层 · 虚位以待」, 且只有这种根用户能去认领; 见 promote 单)
 *   - ⚠ **上层一旦有人就不可撤换** (主人拍) —— 本函数只读; 仓内没有任何"换上层"的入口,
 *     确需调整只能联系系统管理员按运营流程处理
 */
export interface UplineView {
  id: string;
  name: string;
  /** 我在她下面的线别 (left = A线 / right = B线) */
  side: PlacementSide | null;
  /** 她的绝对层号 (相对本树; 我是根时为 -1 的性质, 不返回) */
  depth: number;
  /** 会员标识 (与树节点同口径; 她没有账号 → false) */
  member: boolean;
}

export async function getPlacementUpline(
  fid: bigint
): Promise<UplineView | null> {
  const [me] = await db
    .select({
      placementPath: franchisee.placementPath,
      rootId: franchisee.rootId,
    })
    .from(franchisee)
    .where(and(eq(franchisee.id, fid), isNull(franchisee.deletedAt)))
    .limit(1);
  if (!me) return null;
  const parent = parentPath(me.placementPath); // '' 的有根 → null
  if (parent == null) return null; // 我是树根 → 上层虚位以待

  const [up] = await db
    .select({
      id: franchisee.id,
      name: franchisee.name,
      placementDepth: franchisee.placementDepth,
      member: memberExistsSql(sql`u.franchisee_id = ${franchisee.id}`),
    })
    .from(franchisee)
    .where(
      and(
        isNull(franchisee.deletedAt),
        // 多根 (B1): 必须同树, 否则两个根 path 都是 ''/前缀会串味
        sql`${franchisee.rootId} IS NOT DISTINCT FROM ${me.rootId}`,
        eq(franchisee.placementPath, parent)
      )
    )
    .limit(1);
  if (!up) return null; // 数据异常 (父节点被删) → 当作虚位, 不炸页面

  return {
    id: up.id.toString(),
    name: up.name,
    side: sideFromPath(me.placementPath),
    depth: up.placementDepth,
    member: up.member === true,
  };
}

/**
 * 懒加载: 取某节点的直接子级 (ADR-0011, 主人 2026-09-18 拍「按需展开」)
 *
 * - 权限: children 必须在我 (viewerFranchiseeId) 的 placement 子树里, 否则返回空
 *   (客户页图谱只展示我的下线; 前端不会请求别人的子树, 这里是服务端兼底)
 * - relation: referrerId == 我 → 'direct', 否则 'downline' (子树内只可能是这两种)
 * - 软删节点不计入
 * - 每级自带 hasChildren, 前端知道下一层能否再展开
 */
export async function getFranchiseeChildren(
  nodeId: bigint,
  viewerFranchiseeId: bigint | null
): Promise<TreeNode[] | null> {
  const [node] = await db
    .select()
    .from(franchisee)
    .where(and(eq(franchisee.id, nodeId), isNull(franchisee.deletedAt)))
    .limit(1);
  if (!node) return null;

  // 越权拉底: node 必须在我子树里 (或者就是我)
  if (viewerFranchiseeId === null) return [];
  const [me] = await db
    .select()
    .from(franchisee)
    .where(and(eq(franchisee.id, viewerFranchiseeId), isNull(franchisee.deletedAt)))
    .limit(1);
  if (!me) return [];

  // 多根 (B1): 先判同树, 再判 path 前缀 (根用户 path='' 时"谁都是我的子孙"只在同一棵树里成立)
  const sameRoot = (node.rootId ?? node.id) === (me.rootId ?? me.id);
  const inMySubtree =
    node.id === me.id ||
    (sameRoot &&
      (me.placementPath === ""
        ? node.placementPath !== ""
        : node.placementPath.startsWith(me.placementPath)));
  if (!inMySubtree) return [];

  const children = await db
    .select({
      id: franchisee.id,
      name: franchisee.name,
      placementSide: franchisee.placementSide,
      placementPath: franchisee.placementPath,
      placementDepth: franchisee.placementDepth,
      referrerId: franchisee.referrerId,
      member: memberExistsSql(sql`u.franchisee_id = ${franchisee.id}`),
    })
    .from(franchisee)
    .where(
      and(
        eq(franchisee.referrerId, nodeId),
        isNull(franchisee.deletedAt)
      )
    )
    .orderBy(franchisee.placementPath);

  // 一次查完下一层, 标 hasChildren (避免 N+1)
  const childIds = children.map((c) => c.id);
  const grandchildRows =
    childIds.length === 0
      ? []
      : await db
          .select({ referrerId: franchisee.referrerId })
          .from(franchisee)
          .where(
            and(
              inArray(franchisee.referrerId, childIds),
              isNull(franchisee.deletedAt)
            )
          );
  const hasGrandchild = new Set(
    grandchildRows.map((r) => r.referrerId?.toString() ?? "")
  );

  return children.map((c) => ({
    id: c.id.toString(),
    name: c.name,
    placementSide: (sideFromPath(c.placementPath) ??
      c.placementSide) as PlacementSide | null,
    placementDepth: c.placementDepth,
    referrerId: c.referrerId?.toString() ?? null,
    relation: c.referrerId?.toString() === me.id.toString() ? "direct" : "downline",
    children: [],
    hasChildren: hasGrandchild.has(c.id.toString()),
    member: c.member === true,
  }));
}

interface RawNode {
  id: string;
  name: string;
  placementSide: PlacementSide | null;
  placementDepth: number;
  placementPath: string;
  referrerId: string | null;
  /** 绑定账号是不是会员 (无账号恒 false); 判定口径见 member-flag.ts */
  member: boolean;
}

function buildTree(
  root: RawNode,
  descendants: RawNode[],
  depthRemaining: number,
  ctx: BuildCtx
): TreeNode {
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
        referrerId: c.referrerId,
        relation: classifyRelation(c.id, c.referrerId, ctx),
        children: [],
        // 推荐树模式也标全深度真值 (该节点是否还有更低层下级)
        hasChildren: descendants.some((d) => d.referrerId === c.id),
        member: c.member,
      };
    }
    return buildTree(c, descendants, depthRemaining - 1, ctx);
  });

  return {
    id: root.id,
    name: root.name,
    placementSide: root.placementSide,
    placementDepth: root.placementDepth,
    referrerId: root.referrerId,
    relation: classifyRelation(root.id, root.referrerId, ctx),
    children,
    hasChildren: descendants.some((d) => d.referrerId === root.id),
    member: root.member,
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

/**
 * 直接下级加盟商计数 (「我的」页: 我的下线 N 人 · A线 X / B线 Y)
 *
 * 只算**直接下线** (referrer_id = 我), 不递归 —— 递归计数是图谱/树页的活,
 * 这里只要一个「我有几个人」的数字, 一次 GROUP BY 拿完, 不做 N+1。
 * 边界: 软删 (deleted_at) 不计入
 */
export async function countDirectDownline(franchiseeId: bigint): Promise<{
  total: number;
  left: number;
  right: number;
  unknown: number;
}> {
  const rows = await db
    .select({
      side: franchisee.placementSide,
      count: sql<number>`count(*)::int`,
    })
    .from(franchisee)
    .where(
      and(eq(franchisee.referrerId, franchiseeId), isNull(franchisee.deletedAt))
    )
    .groupBy(franchisee.placementSide);

  const pick = (side: string) =>
    Number(rows.find((r) => r.side === side)?.count ?? 0);
  const left = pick("left");
  const right = pick("right");
  const unknown = rows
    .filter((r) => r.side !== "left" && r.side !== "right")
    .reduce((sum, r) => sum + Number(r.count ?? 0), 0);

  return { total: left + right + unknown, left, right, unknown };
}