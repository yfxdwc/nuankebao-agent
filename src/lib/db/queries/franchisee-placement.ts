// ============================================
// 加盟落位「三方确认」工作流 (主人 2026-09-18 拍)
//
// 见 docs/placement-confirmation-design.md
//   - 新设 / 移动节点 → 三方确认: 设置者本人 + 新加盟商本人 + 新位置父节点加盟商
//     (父节点 == 设置者 → 双方)
//   - 确认载体 = App 内「待我确认」(Q1/Q2 都走 in_app; 没账号的人先注册登录再确认)
//   - 超时 72h 自动失效 (Q3); pending 期间点位**预占** (Q4, DB 部分唯一索引兜底)
//   - 移动: 原父节点不确认、推荐人不变 (Q5); 权限: 只能操作自己子树内点位 (Q7)
//   - 历史数据回填「已确认」记录 (Q6)
// ============================================

import { and, desc, eq, isNull, or, sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  customer,
  franchisee,
  franchisePlacementConfirm,
  franchisePlacementRequest,
} from "@/lib/db/schema";
import { decryptField, encryptField, hashForLookup } from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { franchiseeCustomerValues } from "./customer";

/** Q3: 待确认超时 (小时) */
export const PLACEMENT_TIMEOUT_HOURS = 72;

export type PlacementRequestKind = "create" | "move";
export type PlacementConfirmerRole =
  | "initiator"
  | "new_franchisee"
  | "target_parent";

/** 需要哪几方确认: 父节点 == 设置者 → 双方 (主人规则) */
export function requiredRoles(
  initiatorFid: bigint,
  targetParentFid: bigint
): PlacementConfirmerRole[] {
  return targetParentFid === initiatorFid
    ? ["initiator", "new_franchisee"]
    : ["initiator", "new_franchisee", "target_parent"];
}

export interface PlacementConfirmView {
  role: PlacementConfirmerRole;
  decision: "approve" | "reject";
  verifiedBy: string;
  decidedAt: string;
}

export interface PlacementRequestView {
  id: string;
  kind: PlacementRequestKind;
  status: string;
  initiatorFid: string;
  initiatorName: string;
  newName: string | null;
  moveFid: string | null;
  moveName: string | null;
  targetParentFid: string;
  targetParentName: string;
  targetSide: "left" | "right";
  required: PlacementConfirmerRole[];
  confirms: PlacementConfirmView[];
  /** 当前账号在这张单子里能确认的角色 (null = 旁观/无关) */
  myRole: PlacementConfirmerRole | null;
  myDecision: "approve" | "reject" | null;
  backfilled: boolean;
  expiresAt: string;
  createdAt: string;
}

/** 请求上下文 (调用方从 session 取) */
export interface PlacementActor {
  userId: bigint;
  /** 我的 franchisee.id (未加盟 → null) */
  fid: bigint | null;
  /** 我的手机号 hash (没账号 / 未加盟时用于匹配「新加盟商本人」) */
  phoneHash: string | null;
}

// ============================================
// 内部工具
// ============================================

interface RawRequest {
  id: bigint;
  kind: string;
  status: string;
  initiatorFid: bigint;
  initiatorUserId: bigint;
  newName: string | null;
  newPhoneEncrypted: string | null;
  newPhoneHash: string | null;
  moveFid: bigint | null;
  targetParentFid: bigint;
  targetSide: "left" | "right";
  resultFid: bigint | null;
  backfilled: boolean;
  expiresAt: Date;
  createdAt: Date;
}

function roleFor(
  raw: RawRequest,
  actor: PlacementActor,
  confirms: { role: string; decision: string }[]
): PlacementConfirmerRole | null {
  const decided = new Set(confirms.map((c) => c.role));
  const needed = requiredRoles(raw.initiatorFid, raw.targetParentFid);
  const candidates: PlacementConfirmerRole[] = [];
  if (raw.kind === "move" && raw.moveFid != null && actor.fid === raw.moveFid) {
    candidates.push("new_franchisee");
  }
  if (raw.kind === "create" && raw.newPhoneHash != null && actor.phoneHash === raw.newPhoneHash) {
    candidates.push("new_franchisee");
  }
  if (actor.fid != null && actor.fid === raw.targetParentFid) {
    candidates.push("target_parent");
  }
  if (actor.fid != null && actor.fid === raw.initiatorFid) {
    candidates.push("initiator");
  }
  for (const c of candidates) {
    if (needed.includes(c) && !decided.has(c)) return c;
  }
  // 已经确认过 → 返回他确认过的角色 (前端显示「我已确认」)
  for (const c of candidates) {
    if (needed.includes(c)) return c;
  }
  return null;
}

async function toViews(
  exec: typeof db,
  rows: RawRequest[],
  actor: PlacementActor
): Promise<PlacementRequestView[]> {
  if (rows.length === 0) return [];
  const requestIds = rows.map((r) => r.id);
  const fids = new Set<string>();
  for (const r of rows) {
    fids.add(r.initiatorFid.toString());
    fids.add(r.targetParentFid.toString());
    if (r.moveFid != null) fids.add(r.moveFid.toString());
  }
  const names = new Map<string, string>();
  // ⚠ 必须走 exec (事务里传 tx): dev 的 postgres 池 max=1, 事务里用全局 db 会死锁
  const inst = await exec
    .select({ id: franchisee.id, name: franchisee.name })
    .from(franchisee)
    .where(
      sql`${franchisee.id} IN (${sql.join(
        [...fids].map((f) => sql`${BigInt(f)}`),
        sql`, `
      )})`
    );
  for (const i of inst) names.set(i.id.toString(), i.name);

  const confirms = await exec
    .select()
    .from(franchisePlacementConfirm)
    .where(
      sql`${franchisePlacementConfirm.requestId} IN (${sql.join(
        requestIds.map((id) => sql`${id}`),
        sql`, `
      )})`
    );

  return rows.map((r) => {
    const mine = confirms.filter((c) => c.requestId === r.id);
    const needed = requiredRoles(r.initiatorFid, r.targetParentFid);
    const mineMapped = mine.map((c) => ({
      role: c.confirmerRole as string,
      decision: c.decision as string,
    }));
    const myRole = roleFor(r, actor, mineMapped);
    const myConfirm = myRole
      ? mine.find((c) => c.confirmerRole === myRole) ?? null
      : null;
    return {
      id: r.id.toString(),
      kind: r.kind as PlacementRequestKind,
      status: r.status,
      initiatorFid: r.initiatorFid.toString(),
      initiatorName: names.get(r.initiatorFid.toString()) ?? '?',
      newName: r.newName,
      moveFid: r.moveFid?.toString() ?? null,
      moveName: r.moveFid != null ? names.get(r.moveFid.toString()) ?? '?' : null,
      targetParentFid: r.targetParentFid.toString(),
      targetParentName: names.get(r.targetParentFid.toString()) ?? '?',
      targetSide: r.targetSide,
      required: needed,
      confirms: mine.map((c) => ({
        role: c.confirmerRole as PlacementConfirmerRole,
        decision: c.decision as "approve" | "reject",
        verifiedBy: c.verifiedBy,
        decidedAt: c.decidedAt.toISOString(),
      })),
      myRole,
      myDecision: (myConfirm?.decision as "approve" | "reject" | undefined) ?? null,
      backfilled: r.backfilled,
      expiresAt: r.expiresAt.toISOString(),
      createdAt: r.createdAt.toISOString(),
    };
  });
}

/** Q3: 把超时的 pending 置 expired (顺手释放点位预占) — 所有读/写入口都先调一次 */
export async function expireStaleRequests(): Promise<number> {
  const rows = await db
    .update(franchisePlacementRequest)
    .set({ status: "expired", updatedAt: sql`NOW()` })
    .where(
      and(
        eq(franchisePlacementRequest.status, "pending"),
        sql`${franchisePlacementRequest.expiresAt} < NOW()`
      )
    )
    .returning({ id: franchisePlacementRequest.id });
  return rows.length;
}

// ============================================
// 发起申请
// ============================================

export interface CreatePlacementRequestInput {
  kind: PlacementRequestKind;
  initiatorFid: bigint;
  initiatorUserId: bigint;
  targetParentFid: bigint;
  targetSide: "left" | "right";
  /** kind=create */
  newName?: string;
  newPhone?: string;
  newNotes?: string;
  /** kind=move */
  moveFid?: bigint;
}

/** 点位是否被占 (placement 树口径: 看 path, 不是 referrer_id) */
async function slotTaken(
  tx: typeof db,
  parentPath: string,
  side: "left" | "right"
): Promise<bigint | null> {
  const path = parentPath + (side === "left" ? "L." : "R.");
  const [row] = await tx
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(
      and(eq(franchisee.placementPath, path), isNull(franchisee.deletedAt))
    )
    .limit(1);
  return row?.id ?? null;
}

export async function createPlacementRequest(
  input: CreatePlacementRequestInput,
  ctx: AuditContext
): Promise<PlacementRequestView> {
  await expireStaleRequests();

  return await withAuditContext(ctx, async (tx) => {
    const [initiator] = await tx
      .select()
      .from(franchisee)
      .where(
        and(eq(franchisee.id, input.initiatorFid), isNull(franchisee.deletedAt))
      )
      .limit(1);
    if (!initiator) throw new Error("发起人加盟商不存在");

    const [parent] = await tx
      .select()
      .from(franchisee)
      .where(
        and(
          eq(franchisee.id, input.targetParentFid),
          isNull(franchisee.deletedAt)
        )
      )
      .limit(1);
    if (!parent) throw new Error("目标点位(父节点)不存在");

    // Q7: 只能操作自己 placement 子树内的点位
    if (!parent.placementPath.startsWith(initiator.placementPath)) {
      throw new Error("目标点位不在我的图谱里 (只能在自己子树内落位)");
    }

    // 点位空位校验 (预占 = 无子节点 + 无 pending 单)
    const occupied = await slotTaken(tx, parent.placementPath, input.targetSide);
    if (occupied) throw new Error("该点位已经有下线了");

    const [pendingSame] = await tx
      .select({ id: franchisePlacementRequest.id })
      .from(franchisePlacementRequest)
      .where(
        and(
          eq(franchisePlacementRequest.targetParentFid, input.targetParentFid),
          eq(franchisePlacementRequest.targetSide, input.targetSide),
          eq(franchisePlacementRequest.status, "pending")
        )
      )
      .limit(1);
    if (pendingSame) throw new Error("该点位已有待确认的落位申请 (预占中)");

    let newPhoneHash: string | null = null;
    let newPhoneEncrypted: string | null = null;
    let newNotesEncrypted: string | null = null;
    let moveFid: bigint | null = null;

    if (input.kind === "create") {
      if (!input.newName || !input.newPhone) {
        throw new Error("新加盟商 姓名/手机号 必填");
      }
      newPhoneHash = hashForLookup(input.newPhone);
      newPhoneEncrypted = encryptField(input.newPhone);
      newNotesEncrypted = input.newNotes ? encryptField(input.newNotes) : null;

      const [dup] = await tx
        .select({ id: franchisee.id })
        .from(franchisee)
        .where(
          and(
            eq(franchisee.phoneHash, newPhoneHash ?? ""),
            isNull(franchisee.deletedAt)
          )
        )
        .limit(1);
      if (dup) throw new Error("该手机号已经是加盟商了");
    } else {
      if (input.moveFid == null) throw new Error("移动节点必须给 moveFid");
      moveFid = input.moveFid;
      const [moved] = await tx
        .select()
        .from(franchisee)
        .where(and(eq(franchisee.id, moveFid), isNull(franchisee.deletedAt)))
        .limit(1);
      if (!moved) throw new Error("被移动的加盟商不存在");
      if (moved.placementPath === "") throw new Error("根节点不能移动");
      if (!moved.placementPath.startsWith(initiator.placementPath)) {
        throw new Error("被移动的加盟商不在我的图谱里");
      }
      // 防环: 不能挪到自己的子孙下面 (含自己)
      if (parent.placementPath.startsWith(moved.placementPath)) {
        throw new Error("不能把节点挪到它自己的子孙下面");
      }
    }

    const expiresAt = new Date(Date.now() + PLACEMENT_TIMEOUT_HOURS * 3600 * 1000);

    const [request] = await tx
      .insert(franchisePlacementRequest)
      .values({
        kind: input.kind,
        status: "pending",
        initiatorFid: input.initiatorFid,
        initiatorUserId: input.initiatorUserId,
        newName: input.newName ?? null,
        newPhoneEncrypted,
        newPhoneHash,
        newNotesEncrypted,
        moveFid,
        targetParentFid: input.targetParentFid,
        targetSide: input.targetSide,
        expiresAt,
        createdAt: sql`NOW()`,
        updatedAt: sql`NOW()`,
      })
      .returning();

    // 发起人自动算已确认 (他是"设置者本人")
    await tx.insert(franchisePlacementConfirm).values({
      requestId: request.id,
      confirmerRole: "initiator",
      confirmerFid: input.initiatorFid,
      confirmerUserId: input.initiatorUserId,
      decision: "approve",
      verifiedBy: "in_app",
      decidedAt: sql`NOW()`,
    });

    const views = await toViews(
      tx,
      [
        {
          id: request.id,
          kind: request.kind,
          status: request.status,
          initiatorFid: request.initiatorFid,
          initiatorUserId: request.initiatorUserId,
          newName: request.newName,
          newPhoneEncrypted: request.newPhoneEncrypted,
          newPhoneHash: request.newPhoneHash,
          moveFid: request.moveFid,
          targetParentFid: request.targetParentFid,
          targetSide: request.targetSide,
          resultFid: request.resultFid,
          backfilled: request.backfilled,
          expiresAt: request.expiresAt,
          createdAt: request.createdAt,
        },
      ],
      {
        userId: input.initiatorUserId,
        fid: input.initiatorFid,
        phoneHash: null,
      }
    );
    return views[0];
  });
}

// ============================================
// 查询
// ============================================

export type PlacementRequestScope = "mine" | "to_confirm";

export async function listPlacementRequests(
  actor: PlacementActor,
  scope: PlacementRequestScope,
  options?: { status?: string }
): Promise<PlacementRequestView[]> {
  await expireStaleRequests();

  const status = (options?.status ?? "pending") as
    | "pending"
    | "executed"
    | "rejected"
    | "expired"
    | "cancelled";
  const conds = [eq(franchisePlacementRequest.status, status)];

  if (scope === "mine") {
    if (actor.fid == null) return [];
    conds.push(eq(franchisePlacementRequest.initiatorFid, actor.fid));
  } else {
    // 待我确认: 我是目标父节点 / 新加盟商本人
    const mine: SQL[] = [];
    if (actor.fid != null) {
      mine.push(eq(franchisePlacementRequest.targetParentFid, actor.fid));
      mine.push(eq(franchisePlacementRequest.moveFid, actor.fid));
    }
    if (actor.phoneHash != null) {
      mine.push(eq(franchisePlacementRequest.newPhoneHash, actor.phoneHash));
    }
    if (mine.length === 0) return [];
    conds.push(or(...mine)!);
  }

  const rows = await db
    .select()
    .from(franchisePlacementRequest)
    .where(and(...conds))
    .orderBy(desc(franchisePlacementRequest.createdAt))
    .limit(50);

  const views = await toViews(db, rows as RawRequest[], actor);
  // "待我确认" 只留我还没拍板、且确实需要我拍板的
  return scope === "mine"
    ? views
    : views.filter((v) => v.myRole != null && v.myDecision == null);
}

export async function getPlacementRequest(
  id: bigint,
  actor: PlacementActor
): Promise<PlacementRequestView | null> {
  const [row] = await db
    .select()
    .from(franchisePlacementRequest)
    .where(eq(franchisePlacementRequest.id, id))
    .limit(1);
  if (!row) return null;
  const views = await toViews(db, [row as RawRequest], actor);
  return views[0];
}

// ============================================
// 确认 / 拒绝
// ============================================

export async function decidePlacementRequest(
  requestId: bigint,
  actor: PlacementActor,
  decision: "approve" | "reject",
  ctx: AuditContext
): Promise<PlacementRequestView> {
  await expireStaleRequests();

  return await withAuditContext(ctx, async (tx) => {
    const [row] = await tx
      .select()
      .from(franchisePlacementRequest)
      .where(eq(franchisePlacementRequest.id, requestId))
      .limit(1);
    if (!row) throw new Error("申请单不存在");
    if (row.status !== "pending") {
      throw new Error(`申请单状态是 ${row.status}, 不能再确认`);
    }

    const raw = row as RawRequest;
    const confirms = await tx
      .select()
      .from(franchisePlacementConfirm)
      .where(eq(franchisePlacementConfirm.requestId, requestId));
    const myRole = roleFor(
      raw,
      actor,
      confirms.map((c) => ({ role: c.confirmerRole, decision: c.decision }))
    );
    if (myRole == null) throw new Error("这张单子跟你无关, 无法确认");

    // upsert 我的确认
    await tx
      .insert(franchisePlacementConfirm)
      .values({
        requestId,
        confirmerRole: myRole,
        confirmerFid: actor.fid,
        confirmerUserId: actor.userId,
        decision,
        verifiedBy: "in_app",
        decidedAt: sql`NOW()`,
      })
      .onConflictDoUpdate({
        target: [
          franchisePlacementConfirm.requestId,
          franchisePlacementConfirm.confirmerRole,
        ],
        set: {
          decision,
          confirmerFid: actor.fid,
          confirmerUserId: actor.userId,
          verifiedBy: "in_app",
          decidedAt: sql`NOW()`,
        },
      });

    if (decision === "reject") {
      await tx
        .update(franchisePlacementRequest)
        .set({ status: "rejected", updatedAt: sql`NOW()` })
        .where(eq(franchisePlacementRequest.id, requestId));
    } else {
      // 全部 approve → 执行
      const need = requiredRoles(raw.initiatorFid, raw.targetParentFid);
      const all = await tx
        .select()
        .from(franchisePlacementConfirm)
        .where(eq(franchisePlacementConfirm.requestId, requestId));
      const approved = new Set(
        all.filter((c) => c.decision === "approve").map((c) => c.confirmerRole)
      );
      const ok = need.every((r) => approved.has(r));
      if (ok) {
        await executeRequest(tx, raw);
      }
    }

    const [fresh] = await tx
      .select()
      .from(franchisePlacementRequest)
      .where(eq(franchisePlacementRequest.id, requestId))
      .limit(1);
    const views = await toViews(tx, [fresh as RawRequest], actor);
    return views[0];
  });
}

/** 发起人撤回 (pending → cancelled, 点位释放) */
export async function cancelPlacementRequest(
  requestId: bigint,
  actor: PlacementActor,
  ctx: AuditContext
): Promise<void> {
  await withAuditContext(ctx, async (tx) => {
    const [row] = await tx
      .select()
      .from(franchisePlacementRequest)
      .where(eq(franchisePlacementRequest.id, requestId))
      .limit(1);
    if (!row) throw new Error("申请单不存在");
    if (row.status !== "pending") throw new Error(`申请单状态是 ${row.status}`);
    if (actor.fid == null || row.initiatorFid !== actor.fid) {
      throw new Error("只有发起人能撤回");
    }
    await tx
      .update(franchisePlacementRequest)
      .set({ status: "cancelled", updatedAt: sql`NOW()` })
      .where(eq(franchisePlacementRequest.id, requestId));
  });
}

// ============================================
// 执行落位 (三方确认齐了才调; 事务内)
// ============================================

type Tx = typeof db;

async function executeRequest(tx: Tx, raw: RawRequest): Promise<void> {
  // 再校验一次点位 (预占期间理论上没人抢, 兜底)
  const [parent] = await tx
    .select()
    .from(franchisee)
    .where(
      and(eq(franchisee.id, raw.targetParentFid), isNull(franchisee.deletedAt))
    )
    .limit(1);
  if (!parent) throw new Error("目标父节点已被删除");
  const taken = await slotTaken(tx, parent.placementPath, raw.targetSide);
  if (taken) throw new Error("该点位已被占, 落位失败");

  const newPath =
    parent.placementPath + (raw.targetSide === "left" ? "L." : "R.");
  const newDepth = parent.placementDepth + 1;

  let resultFid: bigint;

  if (raw.kind === "create") {
    // 客户档案要明文 (franchiseeCustomerValues 内部再加密); 申请单里存的是密文 → 这里解密
    const plainPhone = raw.newPhoneEncrypted
      ? decryptField(raw.newPhoneEncrypted)
      : "";
    const [inserted] = await tx
      .insert(franchisee)
      .values({
        name: raw.newName ?? "(未命名)",
        phoneEncrypted: raw.newPhoneEncrypted ?? "",
        phoneHash: raw.newPhoneHash ?? `pending:${raw.id}`,
        // 推荐人 = 发起人 (设置者); 点位 = 目标父节点 + 方向
        referrerId: raw.initiatorFid,
        placementSide: raw.targetSide,
        placementPath: newPath,
        placementDepth: newDepth,
        isActive: true,
        notesEncrypted: null,
        createdBy: raw.initiatorUserId,
      })
      .returning({ id: franchisee.id });
    resultFid = inserted.id;

    // 跟 createFranchisee 一致: 加盟商同步落一份客户档案
    await tx
      .insert(customer)
      .values(
        franchiseeCustomerValues({
          name: raw.newName ?? "(未命名)",
          phone: plainPhone,
          createdBy: raw.initiatorUserId,
        })
      )
      .onConflictDoNothing({ target: customer.phoneHash });
  } else {
    if (raw.moveFid == null) throw new Error("move 单缺 moveFid");
    const [moved] = await tx
      .select()
      .from(franchisee)
      .where(eq(franchisee.id, raw.moveFid))
      .limit(1);
    if (!moved) throw new Error("被移动节点不存在");

    const oldPrefix = moved.placementPath;
    const delta = newDepth - moved.placementDepth;

    // 整棵子树搬迁: path 前缀替换 + depth 平移 (含被移动节点自己)
    await tx.execute(sql`
      UPDATE franchisee
      SET placement_path = ${newPath} || substring(placement_path from ${oldPrefix.length + 1}),
          placement_depth = placement_depth + ${delta},
          updated_at = NOW()
      WHERE placement_path LIKE ${oldPrefix + "%"} AND deleted_at IS NULL
    `);
    // 被移动节点: 更新自己的 side (推荐人不变 = Q5)
    await tx
      .update(franchisee)
      .set({ placementSide: raw.targetSide, updatedAt: sql`NOW()` })
      .where(eq(franchisee.id, raw.moveFid));
    resultFid = raw.moveFid;
  }

  await tx
    .update(franchisePlacementRequest)
    .set({
      status: "executed",
      resultFid,
      executedAt: sql`NOW()`,
      updatedAt: sql`NOW()`,
    })
    .where(eq(franchisePlacementRequest.id, raw.id));
}

// ============================================
// 图谱用: 我子树内的待确认点位 (画虚位)
// ============================================

export interface PendingPlacementSlot {
  requestId: string;
  targetParentFid: string;
  targetSide: "left" | "right";
  label: string;
  initiatorFid: string;
}

export async function listPendingPlacementsUnder(
  rootFid: bigint
): Promise<PendingPlacementSlot[]> {
  const [root] = await db
    .select({ path: franchisee.placementPath })
    .from(franchisee)
    .where(eq(franchisee.id, rootFid))
    .limit(1);
  if (!root) return [];
  const rows = await db
    .select({
      id: franchisePlacementRequest.id,
      kind: franchisePlacementRequest.kind,
      targetParentFid: franchisePlacementRequest.targetParentFid,
      targetSide: franchisePlacementRequest.targetSide,
      newName: franchisePlacementRequest.newName,
      moveFid: franchisePlacementRequest.moveFid,
      initiatorFid: franchisePlacementRequest.initiatorFid,
    })
    .from(franchisePlacementRequest)
    .innerJoin(franchisee, eq(franchisee.id, franchisePlacementRequest.targetParentFid))
    .where(
      and(
        eq(franchisePlacementRequest.status, "pending"),
        sql`${franchisee.placementPath} LIKE ${root.path + "%"}`
      )
    );

  return rows.map((r) => ({
    requestId: r.id.toString(),
    targetParentFid: r.targetParentFid.toString(),
    targetSide: r.targetSide,
    label:
      r.kind === "create"
        ? `${r.newName ?? "新加盟商"} (待确认)`
        : `节点 #${r.moveFid} (待移动)`,
    initiatorFid: r.initiatorFid.toString(),
  }));
}
