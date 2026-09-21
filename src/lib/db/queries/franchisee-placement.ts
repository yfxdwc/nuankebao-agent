// ============================================
// 加盟落位「三方确认」工作流 (主人 2026-09-18 拍)
//
// 见 docs/placement-confirmation-design.md
//   - 新设 / 移动 / **解除加盟** → 三方确认: 设置者本人 + 该加盟商本人 + 其上级
//     (上级 == 设置者 → 双方)
//   - 解除加盟 (kind=unjoin, 主人 2026-09-18 拍): 有下线的节点**不允许**解除 (先处理完下线)
//   - 确认载体 = App 内「待我确认」(Q1/Q2 都走 in_app; 没账号的人先注册登录再确认)
//   - 超时 72h 自动失效 (Q3); pending 期间点位**预占** (Q4, DB 部分唯一索引兜底)
//   - 移动: 原父节点不确认、推荐人不变 (Q5); 权限: 只能操作自己子树内点位 (Q7)
//   - 历史数据回填「已确认」记录 (Q6)
//
// 追加 (主人 2026-09-21 拍 B2): kind='promote' = **向上认领上级** —— 往根部发展
//   - 背景: 客户公司现实里已有固有加盟体系; app 只是"同步现公司的加盟树".
//     新团队初始用户 (admin 指定的加盟节点) 大概率只是公司体系里的**中间层** →
//     老的三方确认只能往下长 (自己这一枝), 他没法把**上面**的加盟商拉进来
//   - 做法: 现根 A 认领现实里的直接上级 U → U 成为**新根**, A 整棵子树下降一层
//     (path 统一加 'L.'/'R.' 前缀, depth +1, root_id 迁到 U)
//   - 确认方: **双方** (发起人 A + 新加盟商本人 U) —— 与"父节点==设置者 → 双方"同构:
//     promote 里 app 内根本不存在的"上上层"不参与, 也不需要参与 (U 本人点头即可)
//   - 原"往下生长"的三方确认**完全不变** (本次只新增 kind, 不动 create/unjoin)
// ============================================

import { and, desc, eq, isNull, or, sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  franchisee,
  franchisePlacementConfirm,
  franchisePlacementRequest,
  user,
} from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { logger } from "@/lib/errors";
import { rewardReferrerOnFranchisee } from "@/lib/billing/entitlements";
import {
  assertNodeHasAccount,
  requireAccountForNode,
  linkAccountAndCustomer,
} from "./franchisee-account";

/** Q3: 待确认超时 (小时) */
export const PLACEMENT_TIMEOUT_HOURS = 72;

// 主人 2026-09-19 拍: 'move' (直接移动点位) 已下线 → 点位变更只能「解除加盟 → 重新加盟落位」
export type PlacementRequestKind = "create" | "unjoin" | "promote";
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
  /** unjoin 单主体节点 (兼容旧客户端字段名 moveFid/moveName, 语义相同) */
  unjoinFid: string | null;
  unjoinName: string | null;
  targetParentFid: string;
  targetParentName: string;
  targetSide: "left" | "right";
  required: PlacementConfirmerRole[];
  confirms: PlacementConfirmView[];
  /** 执行结果: create/promote → 新节点 id; unjoin → 被解除的节点 id */
  resultFid: string | null;
  /** promote: 认领的上级节点 id (已在 app 里时) / null = 上级是新人, 执行时才建 */
  uplineFid: string | null;
  /** promote: 上级节点名字 (承接 tooltip / 列表文案) */
  uplineName: string | null;
  /**
   * promote: 上级**当前空着的**点位 (主人 2026-09-21 拍: 我在上级的 A/B 线由上级自己决定)。
   * 上级是新人(还没节点) → 两条都空; 上级已有节点 → 看他的子位占用情况。
   * 上级本人打开时按这个选项来挑线; 两条都空才能认领。
   */
  availableSides: ("left" | "right")[];
  /** 当前账号在这张单子里能确认的角色 (null = 旁观/无关) */
  myRole: PlacementConfirmerRole | null;
  myDecision: "approve" | "reject" | null;
  backfilled: boolean;
  expiresAt: string;
  createdAt: string;
}

/** 'L.L.R.' → 'L.' ; 'L.' → '' (placement 父节点路径) */
function parentPathOf(path: string): string {
  const segs = path.split(".").filter(Boolean);
  if (segs.length === 0) return "";
  segs.pop();
  return segs.length === 0 ? "" : segs.join(".") + ".";
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
  /** unjoin 单: 要解除的加盟商节点 id (DB 列名历史遗留 move_fid; 语义 = 单子主体) */
  moveFid: bigint | null;
  /** promote 单: 认领的上级**已在 app 里**时的现存节点 id (null = 新建) */
  uplineFid: bigint | null;
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
  if (
    raw.kind === "unjoin" &&
    raw.moveFid != null &&
    actor.fid === raw.moveFid
  ) {
    candidates.push("new_franchisee");
  }
  if (
    (raw.kind === "create" || raw.kind === "promote") &&
    raw.newPhoneHash != null &&
    actor.phoneHash === raw.newPhoneHash
  ) {
    candidates.push("new_franchisee");
  }
  // promote 认领「已在 app 里的节点」: 上级本人可能没绑这个节点 (老 seed 节点),
  //   但按 fid 认得更稳 (手机号只是弱约定)
  if (
    raw.kind === "promote" &&
    raw.uplineFid != null &&
    actor.fid === raw.uplineFid
  ) {
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
    if (r.uplineFid != null) fids.add(r.uplineFid.toString());
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

  // promote 单: 逐个算上级当前空着的子位 (上级本人挑线用)
  const uplineRows = new Map<
    string,
    { id: bigint; rootId: bigint | null; placementPath: string } | null
  >();
  for (const r of rows) {
    if (r.kind !== "promote") continue;
    if (r.uplineFid == null) {
      uplineRows.set(r.id.toString(), null); // 上级是新人 → 两条都空
      continue;
    }
    const [u] = await exec
      .select({
        id: franchisee.id,
        rootId: franchisee.rootId,
        placementPath: franchisee.placementPath,
      })
      .from(franchisee)
      .where(
        and(eq(franchisee.id, r.uplineFid), isNull(franchisee.deletedAt))
      )
      .limit(1);
    uplineRows.set(r.id.toString(), u ?? null);
  }
  const availableSidesCache = new Map<string, ("left" | "right")[]>();
  for (const r of rows) {
    if (r.kind !== "promote") continue;
    availableSidesCache.set(
      r.id.toString(),
      await freeSidesOf(exec, uplineRows.get(r.id.toString()) ?? null)
    );
  }

  return rows.map((r) => {
    const mine = confirms.filter((c) => c.requestId === r.id);
    // 系统管理员单 (verifiedBy='admin') = 免多方确认 → 不需要任何角色再点
    const adminMade = mine.some((c) => c.verifiedBy === "admin");
    const needed = adminMade
      ? []
      : requiredRoles(r.initiatorFid, r.targetParentFid);
    const mineMapped = mine.map((c) => ({
      role: c.confirmerRole as string,
      decision: c.decision as string,
    }));
    const myRole = adminMade ? null : roleFor(r, actor, mineMapped);
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
      unjoinFid: r.moveFid?.toString() ?? null,
      unjoinName:
        r.moveFid != null ? names.get(r.moveFid.toString()) ?? '?' : null,
      targetParentFid: r.targetParentFid.toString(),
      targetParentName: names.get(r.targetParentFid.toString()) ?? '?',
      targetSide: r.targetSide,
      resultFid: r.resultFid?.toString() ?? null,
      uplineFid: r.uplineFid?.toString() ?? null,
      uplineName:
        r.uplineFid != null ? names.get(r.uplineFid.toString()) ?? '?' : null,
      availableSides: availableSidesCache.get(r.id.toString()) ?? [],
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
  /** 发起人加盟商 id; 系统管理员可能没有加盟商记录 → null (配合 initiatorIsAdmin) */
  initiatorFid: bigint | null;
  initiatorUserId: bigint;
  /**
   * 发起人是否系统管理员 (route 从 session.role 解析) — 主人 2026-09-19 拍:
   *   「系统管理员设置加盟用户不需要多方确认」+ 可全网任意点位
   */
  initiatorIsAdmin?: boolean;
  /** 发起人自己的手机号 hash — 用于「用户不能给自己设置成加盟用户」校验 */
  initiatorPhoneHash?: string | null;
  targetParentFid: bigint;
  targetSide: "left" | "right";
  /** kind=create */
  newName?: string;
  newPhone?: string;
  newNotes?: string;
  /** kind=move / unjoin: 被移动 / 被解除的节点 */
  /** unjoin: 要解除的加盟商节点 id */
  unjoinFid?: bigint;
}

/**
 * 点位是否被占 (placement 树口径: 看 path, 不是 referrer_id)
 *
 * ⚠ `rootFid` 必传: path 只在**根内**唯一 —— 多根时两棵树都有 'L.' 点位,
 *   不带 root_id 会把别的树的节点当成"这个点位有人了"
 */
async function slotTaken(
  tx: typeof db,
  parentRootId: bigint | null,
  parentPath: string,
  side: "left" | "right"
): Promise<bigint | null> {
  const path = parentPath + (side === "left" ? "L." : "R.");
  const [row] = await tx
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(
      and(
        eq(franchisee.placementPath, path),
        parentRootId == null
          ? isNull(franchisee.rootId)
          : eq(franchisee.rootId, parentRootId),
        isNull(franchisee.deletedAt)
      )
    )
    .limit(1);
  return row?.id ?? null;
}

/**
 * 某个节点**当前空着的**子位 (promote 用: 上级得有空位才放得下我)
 *   - 按 placement 口径: path + 'L.'/'R.' 且同樹 (不是 referrer_id)
 *   - 节点是软删的 / 找不到 → 视为两条都空 (调用方自己保证语义)
 */
async function freeSidesOf(
  exec: typeof db,
  node: { id: bigint; rootId: bigint | null; placementPath: string } | null
): Promise<("left" | "right")[]> {
  if (!node) return ["left", "right"];
  const rows = await exec
    .select({ side: franchisee.placementSide, path: franchisee.placementPath })
    .from(franchisee)
    .where(
      and(
        eq(franchisee.rootId, node.rootId ?? node.id),
        sql`${franchisee.placementPath} IN (${node.placementPath + "L."}, ${node.placementPath + "R."})`,
        isNull(franchisee.deletedAt)
      )
    );
  const taken = new Set(
    rows.map((r) =>
      r.path.endsWith("L.") && r.path.startsWith(node.placementPath)
        ? "left"
        : "right"
    )
  );
  return (["left", "right"] as const).filter((sd) => !taken.has(sd));
}

/** 同树 + 在自己子树内? (path 前缀 + root_id 双条件; 多根下少了 root_id 会跨树误判) */
function inSubtreeSql(
  candidateRootId: bigint | null,
  candidatePath: string,
  viewerRootId: bigint | null,
  viewerPath: string
): SQL {
  const sameRoot =
    viewerRootId == null
      ? sql`true`
      : sql`${candidateRootId ?? sql`NULL`} = ${viewerRootId}`;
  const prefix =
    viewerPath === ""
      ? sql`${candidatePath} <> ''`
      : sql`${candidatePath} LIKE ${viewerPath + "%"}`;
  return sql`(${sameRoot} AND ${prefix})`;
}

/** 两个节点是否在同一棵树 (root_id 尚未回填时退回"看是不是同一个根") */
function sameRootAsInput(
  a: { rootId: bigint | null; id: bigint },
  b: { rootId: bigint | null; id: bigint }
): boolean {
  const ra = a.rootId ?? a.id;
  const rb = b.rootId ?? b.id;
  return ra === rb;
}

export async function createPlacementRequest(
  input: CreatePlacementRequestInput,
  ctx: AuditContext
): Promise<PlacementRequestView> {
  await expireStaleRequests();

  // 事务内收集"新建加盟商的手机号 hash", 提交后再发推荐奖励 (不能嵌事务)
  let rewardPhoneHash: string | null = null;

  const view = await withAuditContext(ctx, async (tx) => {
    const isAdmin = input.initiatorIsAdmin === true;
    const initiator =
      input.initiatorFid == null
        ? undefined
        : (
            await tx
              .select()
              .from(franchisee)
              .where(
                and(
                  eq(franchisee.id, input.initiatorFid),
                  isNull(franchisee.deletedAt)
                )
              )
              .limit(1)
          )[0];
    // 主人 2026-09-19: 只有「已加盟用户」或「系统管理员」能设置加盟
    if (!initiator && !isAdmin) {
      throw new Error("只有已加盟用户或系统管理员才能设置加盟");
    }

    // 向上认领 (promote): 锚点 = **发起人自己这个根**; 客户端只需给 side + 上级资料
    //   (她现实里的上级 = app 里还不存在的那个人 → 没有 targetParentId 可传)
    if (input.kind === "promote") {
      if (!initiator) {
        throw new Error("认领上级必须由该树根节点本人发起 (管理员无加盟节点, 不能代替)");
      }
      if (initiator.placementPath !== "") {
        throw new Error("只有树根才能向上认领上级 (往上发展只能从根往上接)");
      }
      input = { ...input, targetParentFid: initiator.id };
    }

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

    // Q7: 只能操作自己 placement 子树内的点位 (系统管理员例外: 可全网任意)
    //   ⚠ 多根 (B1): 除了 path 前缀, 还必须**同一棵树** —— 否则别的树的 'L.' 也以 'L.' 开头? 不,
    //     它是"根用户 path='' 时任何 path 都算前缀" 这一类误判 (根能操作别人树)
    //    ⚠ promote 例外: 锚点**就是发起人自己那个根** (把上级接到我头上),
    //      用"目标必须在我子树内"去量它必然失败 —— 它的语义是"我自己往上长"
    if (
      !isAdmin &&
      initiator != null &&
      input.kind !== "promote" &&
      !(
        sameRootAsInput(initiator, parent) &&
        (initiator.placementPath === ""
          ? parent.placementPath !== ""
          : parent.placementPath.startsWith(initiator.placementPath))
      )
    ) {
      throw new Error("目标点位不在我的图谱里 (只能在自己子树内落位)");
    }
    // 发起人加盟商 id: admin 没加盟商记录时用目标父节点占位 (审计可读, 不影响落位)
    const initiatorFid = initiator?.id ?? input.targetParentFid;

    // 点位空位校验 (预占 = 无子节点 + 无 pending 单)
    // ⚠ 只有 create 会占一个**空位**:
    //   - unjoin: 要解除的节点本来就占着那个点位
    //   - promote: target_parent_fid 是"锚点" (要被上移的现根), 不是未来的父;
    //     锚点自己的左/右子位与本次操作无关 (锚点会整体挪到新根下面)
    if (input.kind === "create") {
      const occupied = await slotTaken(
        tx,
        parent.rootId,
        parent.placementPath,
        input.targetSide
      );
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
    }

    let newPhoneHash: string | null = null;
    let newPhoneEncrypted: string | null = null;
    let newNotesEncrypted: string | null = null;
    let unjoinNodeId: bigint | null = null;
    /** promote: 上级已在 app 里 → 直接复用他的节点 id (不新建副本) */
    let uplineFid: bigint | null = null;

    if (input.kind === "create") {
      if (!input.newName || !input.newPhone) {
        throw new Error("新加盟商 姓名/手机号 必填");
      }
      newPhoneHash = hashForLookup(input.newPhone);
      newPhoneEncrypted = encryptField(input.newPhone);
      newNotesEncrypted = input.newNotes ? encryptField(input.newNotes) : null;

      // 主人 2026-09-19: 用户不能给自己设置成加盟用户 (哪怕他是管理员)
      if (
        input.initiatorPhoneHash != null &&
        input.initiatorPhoneHash === newPhoneHash
      ) {
        throw new Error("不能给自己设置加盟 (必须由其他已加盟用户或系统管理员设置)");
      }

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
    } else if (input.kind === "promote") {
      // 向上认领上级 (主人 2026-09-21 拍 B2 + 本次补充):
      //   把现实里的**直接上级 U** 变成我上层。两种情形:
      //     ① U 不在 app 里 → 执行时新建他的节点 (他成为新根, 我这棵树下降一层)
      //     ② U **已在 app 里** (别的树/别的枝) → **复用他现有的节点**, 我这棵树挂到他的空位
      //        (主人拍: 「一个人已经在别的树里是节点, 可以被认领为我的上级,
      //          前提是这个人的一层 2 个点位必需有空位」→ 两棵树在此合并)
      //   校验: ① 我是根 ② 不是我自己 ③ U 不能在我这棵树里 (会成环)
      //         ④ U 必须已有账号 (确认要他本人点) ⑤ 上级/锚点各自只能有 1 张 pending
      //   ⚠ 我在 U 的哪条线**不由我选** —— 由 U 本人在确认时决定 (拍板原话)
      if (!input.newName || !input.newPhone) {
        throw new Error("上级 姓名/手机号 必填");
      }
      newPhoneHash = hashForLookup(input.newPhone);
      newPhoneEncrypted = encryptField(input.newPhone);
      newNotesEncrypted = input.newNotes ? encryptField(input.newNotes) : null;

      // 用户不能把自己认领成自己的上级 (跟 create 同一条硬规则)
      if (
        input.initiatorPhoneHash != null &&
        input.initiatorPhoneHash === newPhoneHash
      ) {
        throw new Error("不能把自己认领为自己的上级 (必须是另一个人)");
      }

      const [existing] = await tx
        .select()
        .from(franchisee)
        .where(
          and(
            eq(franchisee.phoneHash, newPhoneHash ?? ""),
            isNull(franchisee.deletedAt)
          )
        )
        .limit(1);

      if (existing) {
        // 情形 ②: 认领已存在的节点 → 复用, 不新建副本
        if (initiator != null && (existing.rootId ?? existing.id) === (initiator.rootId ?? initiator.id)) {
          throw new Error("这位加盟商已经在您的加盟树里了, 不能认领为自己的上级 (会成环)");
        }
        const [uplineUser] = await tx
          .select({ id: user.id })
          .from(user)
          .where(
            and(eq(user.phoneHash, existing.phoneHash), eq(user.isActive, true))
          )
          .limit(1);
        if (!uplineUser) {
          throw new Error(
            "这位加盟商还没有可登录的账号 —— 认领必须他本人在「加盟落位确认」里点同意, 请先让他注册登录"
          );
        }
        // 他的两个点位必须还有空的 (否则没地方放我)
        const free = await freeSidesOf(tx, existing);
        if (free.length === 0) {
          throw new Error("这位加盟商下面的两个点位都已经有人了, 暂时接不了");
        }
        uplineFid = existing.id;
      }

      const [pendingSameAnchor] = await tx
        .select({ id: franchisePlacementRequest.id })
        .from(franchisePlacementRequest)
        .where(
          and(
            eq(franchisePlacementRequest.kind, "promote"),
            eq(franchisePlacementRequest.status, "pending"),
            eq(
              franchisePlacementRequest.targetParentFid,
              input.targetParentFid
            )
          )
        )
        .limit(1);
      if (pendingSameAnchor) throw new Error("这个树根已有一张待确认的「认领上级」申请");

      // 同一个上级同时只能有 1 张认领单 (避免两个枝同时抢他的空位)
      const [pendingSameUpline] = await tx
        .select({ id: franchisePlacementRequest.id })
        .from(franchisePlacementRequest)
        .where(
          and(
            eq(franchisePlacementRequest.kind, "promote"),
            eq(franchisePlacementRequest.status, "pending"),
            or(
              eq(
                franchisePlacementRequest.uplineFid,
                uplineFid ?? BigInt(-1)
              ),
              eq(franchisePlacementRequest.newPhoneHash, newPhoneHash ?? "")
            )!
          )
        )
        .limit(1);
      if (pendingSameUpline) {
        throw new Error("已经有人正在认领这位上级, 等他确认完再试");
      }
    } else if (input.kind === "unjoin") {
      // 解除加盟 (主人 2026-09-18 拍 Q3): 本人 + 上级 + 设置者三方确认;
      //   **有下线的节点不允许解除** (要先处理完下线)
      if (input.unjoinFid == null) throw new Error("解除加盟必须给节点 id");
      const unjoinFid = input.unjoinFid;
      const [node] = await tx
        .select()
        .from(franchisee)
        .where(and(eq(franchisee.id, unjoinFid), isNull(franchisee.deletedAt)))
        .limit(1);
      if (!node) throw new Error("要解除的加盟商不存在");
      if (node.placementPath === "") throw new Error("根节点不能解除");
      if (
        !isAdmin &&
        initiator != null &&
        !(
          sameRootAsInput(initiator, node) &&
          (initiator.placementPath === ""
            ? node.placementPath !== ""
            : node.placementPath.startsWith(initiator.placementPath))
        )
      ) {
        throw new Error("该加盟商不在我的图谱里");
      }
      // Q3: 有下线 → 不允许 (先处理完下线)
      const [child] = await tx
        .select({ id: franchisee.id })
        .from(franchisee)
        .where(
          and(
            sql`${franchisee.placementPath} LIKE ${node.placementPath + "%"}`,
            sql`${franchisee.placementPath} <> ${node.placementPath}`,
            eq(franchisee.rootId, node.rootId ?? node.id),
            isNull(franchisee.deletedAt)
          )
        )
        .limit(1);
      if (child) throw new Error("这位加盟商还有下线, 要先处理完下线才能解除");

      // 同一个节点不能有两张 pending 解除单
      const [pendingUnjoin] = await tx
        .select({ id: franchisePlacementRequest.id })
        .from(franchisePlacementRequest)
        .where(
          and(
            eq(franchisePlacementRequest.moveFid, unjoinFid),
            eq(franchisePlacementRequest.kind, "unjoin"),
            eq(franchisePlacementRequest.status, "pending")
          )
        )
        .limit(1);
      if (pendingUnjoin) throw new Error("这个加盟商已有待确认的解除申请");

      unjoinNodeId = unjoinFid;
      // 目标点位 = 该节点在**二叉树上的父节点** (不是 referrer: 新落位流程里
      //   referrer = 设置者, 而 placement 父节点可能更深 → 三方里的「上级」必须按点位算)
      const pp = parentPathOf(node.placementPath);
      const [placementParent] = await tx
        .select({ id: franchisee.id })
        .from(franchisee)
        .where(
          and(
            eq(franchisee.placementPath, pp),
            eq(franchisee.rootId, node.rootId ?? node.id),
            isNull(franchisee.deletedAt)
          )
        )
        .limit(1);
      input = {
        ...input,
        targetParentFid:
          placementParent?.id ?? node.referrerId ?? parent.id,
        targetSide: (node.placementSide ?? "left") as "left" | "right",
      };
    } else {
      // 主人 2026-09-19 拍: 点位不能直接移动 —— 必须先解除加盟, 再重新加盟落位
      throw new Error(
        "点位不能直接移动: 请先「解除加盟」, 再重新加盟落位 (新点位走三方确认)"
      );
    }

    const expiresAt = new Date(Date.now() + PLACEMENT_TIMEOUT_HOURS * 3600 * 1000);

    // 主人 2026-09-19: 系统管理员设置加盟 → **不需要多方确认**, 直接生效
    const [request] = await tx
      .insert(franchisePlacementRequest)
      .values({
        kind: input.kind,
        status: isAdmin ? "executed" : "pending",
        initiatorFid,
        initiatorUserId: input.initiatorUserId,
        newName: input.newName ?? null,
        newPhoneEncrypted,
        newPhoneHash,
        newNotesEncrypted,
        moveFid: unjoinNodeId,
        uplineFid,
        targetParentFid: input.targetParentFid,
        targetSide: input.targetSide,
        expiresAt,
        createdAt: sql`NOW()`,
        updatedAt: sql`NOW()`,
      })
      .returning();

    // 发起人自动算已确认 (他是"设置者本人"); admin 单 → verified_by='admin'
    await tx.insert(franchisePlacementConfirm).values({
      requestId: request.id,
      confirmerRole: "initiator",
      confirmerFid: initiatorFid,
      confirmerUserId: input.initiatorUserId,
      decision: "approve",
      verifiedBy: isAdmin ? "admin" : "in_app",
      decidedAt: sql`NOW()`,
    });

    // admin: 立即落位 (事务内) → 再把单子读回来
    let finalRow = request;
    if (isAdmin) {
      const outcome = await executeRequest(tx, request as unknown as RawRequest);
      rewardPhoneHash = outcome.createdPhoneHash;
      const [fresh] = await tx
        .select()
        .from(franchisePlacementRequest)
        .where(eq(franchisePlacementRequest.id, request.id))
        .limit(1);
      finalRow = fresh ?? request;
    }

    const views = await toViews(
      tx,
      [
        {
          id: finalRow.id,
          kind: finalRow.kind,
          status: finalRow.status,
          initiatorFid: finalRow.initiatorFid,
          initiatorUserId: finalRow.initiatorUserId,
          newName: finalRow.newName,
          newPhoneEncrypted: finalRow.newPhoneEncrypted,
          newPhoneHash: finalRow.newPhoneHash,
          moveFid: finalRow.moveFid,
          uplineFid: finalRow.uplineFid,
          targetParentFid: finalRow.targetParentFid,
          targetSide: finalRow.targetSide,
          resultFid: finalRow.resultFid,
          backfilled: finalRow.backfilled,
          expiresAt: finalRow.expiresAt,
          createdAt: finalRow.createdAt,
        },
      ],
      {
        userId: input.initiatorUserId,
        fid: initiatorFid,
        phoneHash: null,
      }
    );
    return views[0];
  });

  // D23: 被推荐人成为加盟者 → 发推荐人 15 天 (幂等 + 失败不影响落位)
  await safeRewardReferrer(rewardPhoneHash);
  return view;
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
    // 待我确认: 我是目标父节点 / 新加盟商本人 / **被认领的上级本人**
    //   ⚠ promote 认领「已在 app 里的节点」时, 本人是按 upline_fid 认的 —— 少了这一条,
    //     她的「待我确认」永远是空的 (promote 单就永远没人能拍板)
    const mine: SQL[] = [];
    if (actor.fid != null) {
      mine.push(eq(franchisePlacementRequest.targetParentFid, actor.fid));
      mine.push(eq(franchisePlacementRequest.moveFid, actor.fid));
      mine.push(eq(franchisePlacementRequest.uplineFid, actor.fid));
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

/**
 * 三方之一拍板
 *
 * `side` 只有一种情况用得上 (主人 2026-09-21 拍): **promote 单里的上级本人** ——
 *   「我在我的上级是处于 a线还是 b线由我的上级自己决定」→ 所以认领人发起时**不选线**,
 *   由上级在同意这一步挑一个自己空着的点位。
 */
export async function decidePlacementRequest(
  requestId: bigint,
  actor: PlacementActor,
  decision: "approve" | "reject",
  ctx: AuditContext,
  side?: "left" | "right"
): Promise<PlacementRequestView> {
  await expireStaleRequests();

  let rewardPhoneHash: string | null = null;

  const view = await withAuditContext(ctx, async (tx) => {
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

    // promote: 上级本人挑线 (「我在上级的 A线/B线 由上级自己决定」)
    if (
      decision === "approve" &&
      raw.kind === "promote" &&
      myRole === "new_franchisee"
    ) {
      const uplineNode =
        raw.uplineFid == null
          ? null
          : ((
              await tx
                .select({
                  id: franchisee.id,
                  rootId: franchisee.rootId,
                  placementPath: franchisee.placementPath,
                })
                .from(franchisee)
                .where(
                  and(
                    eq(franchisee.id, raw.uplineFid),
                    isNull(franchisee.deletedAt)
                  )
                )
                .limit(1)
            )[0] ?? null);
      const free = await freeSidesOf(tx, uplineNode);
      if (free.length === 0) {
        throw new Error("您下面的两个点位都已经有人了, 接不下这位下线");
      }
      const chosen = side ?? (free.length === 1 ? free[0] : null);
      if (chosen == null) {
        throw new Error("请选择这位下线放在您的 A线 还是 B线");
      }
      if (!free.includes(chosen)) {
        throw new Error("这条线已经有下线了, 请换一条");
      }
      await tx
        .update(franchisePlacementRequest)
        .set({ targetSide: chosen, updatedAt: sql`NOW()` })
        .where(eq(franchisePlacementRequest.id, requestId));
      raw.targetSide = chosen;
    }

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
        const outcome = await executeRequest(tx, raw);
        rewardPhoneHash = outcome.createdPhoneHash;
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

  // D23: 三方确认齐了 → 落位成功 → 发推荐人奖励 (幂等 + 失败不影响落位)
  await safeRewardReferrer(rewardPhoneHash);
  return view;
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

/** 落位结果: 新建加盟商时带上手机号 hash —— 用于会员推荐奖励 (D23) */
interface ExecuteOutcome {
  /** 本次落位是否"新建"了一个加盟商 (unjoin/移动 时为空) */
  createdPhoneHash: string | null;
}

/**
 * 安全发推荐奖励 (D23: 被推荐人成为加盟者 → 给推荐人 15 天)
 *
 * 边界 (重要):
 *   - **不抛异常**: 会员奖励失败绝不能把"落位"这种核心业务搞挂 (落位已提交, 奖励可补)
 *   - 幂等: 内部靠 (referrer, referee) 唯一 + grant idempotencyKey
 *   - 事务外调用: grantDays 自己开事务, 不能嵌在落位事务里
 */
async function safeRewardReferrer(phoneHash: string | null): Promise<void> {
  if (!phoneHash || phoneHash.startsWith("pending:")) return;
  try {
    const { rewarded } = await rewardReferrerOnFranchisee({
      newFranchiseePhoneHash: phoneHash,
    });
    if (rewarded > 0) {
      logger.info("billing: referral reward granted", { rewarded });
    }
  } catch (e) {
    logger.error("billing: referral reward failed (ignored)", {}, e);
  }
}

async function executeRequest(tx: Tx, raw: RawRequest): Promise<ExecuteOutcome> {
  // 再校验一次点位 (预占期间理论上没人抢, 兜底)
  const [parent] = await tx
    .select()
    .from(franchisee)
    .where(
      and(eq(franchisee.id, raw.targetParentFid), isNull(franchisee.deletedAt))
    )
    .limit(1);
  if (!parent) throw new Error("目标父节点已被删除");
  // 只有 create 会占一个空位 (unjoin 本来就占着; promote 的 targetParentFid 是锚点不是父)
  if (raw.kind === "create") {
    const taken = await slotTaken(
      tx,
      parent.rootId,
      parent.placementPath,
      raw.targetSide
    );
    if (taken) throw new Error("该点位已被占, 落位失败");
  }

  const newPath =
    parent.placementPath + (raw.targetSide === "left" ? "L." : "R.");
  const newDepth = parent.placementDepth + 1;

  let resultFid: bigint;
  let createdOutcome: ExecuteOutcome = { createdPhoneHash: null };

  if (raw.kind === "create") {
    // 节点 ⇒ 账号 门槛 (主人 2026-09-21 拍): 先给一句人话的拒, 再谈落位
    //   (执行末段的 assertNodeHasAccount 是兜底自检 —— 那条报错会带一个其实不存在的节点 id,
    //    给用户看不好, 所以能提前判的都提前判)
    if (raw.newPhoneHash && !raw.newPhoneHash.startsWith("pending:")) {
      await requireAccountForNode(tx, raw.newPhoneHash);
    }
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
        // 同树 (B1): 新节点跟着它落位的父节点走, 不是跟"设置者"走
        rootId: parent.rootId ?? parent.id,
        isActive: true,
        notesEncrypted: null,
        createdBy: raw.initiatorUserId,
      })
      .returning({ id: franchisee.id });
    resultFid = inserted.id;

    await linkAccountAndCustomer(tx, {
      fid: inserted.id,
      phoneHash: raw.newPhoneHash,
      phoneEncrypted: raw.newPhoneEncrypted,
      name: raw.newName ?? "(未命名)",
      createdBy: raw.initiatorUserId,
    });

    // 节点 ⇒ 账号 不变量 (主人 2026-09-21 拍): 建完必须绑上账号, 否则整单回滚
    await assertNodeHasAccount(tx, inserted.id, "新加盟节点");

    createdOutcome = { createdPhoneHash: raw.newPhoneHash ?? null };
  } else if (raw.kind === "promote") {
    // 向上认领 (主人 2026-09-21 拍 B2 + 补充): 让 U 成为我的上层。
    // 两种情形统一成一件事 —— **把我这棵树挂到 U 的一个空位上**:
    //   ① U 不在 app 里 (upline_fid = null) → 先建 U 的节点 (path='' depth=0) 再挂
    //      → 等价于「U 成为新根, 我整棵树下降一层」
    //   ② U 已在 app 里 (upline_fid) → **复用他现有的节点**, 直接挂到他的空位
    //      → 两棵树在这里合并 (同一加盟系统上不同枝 → 上溯到共同上层)
    // 我在 U 的哪条线 = raw.targetSide, **由 U 本人在确认时决定** (拍板原话)
    const anchor = parent; // promote 里 target_parent_fid 存的是锚点 (我的现根)
    if (anchor.placementPath !== "") {
      throw new Error("锚点不是树根, 认领失败");
    }
    const oldRootId = anchor.rootId ?? anchor.id;
    const side: "left" | "right" = raw.targetSide === "right" ? "right" : "left";

    let upline: {
      id: bigint;
      rootId: bigint | null;
      placementPath: string;
      placementDepth: number;
    };
    let uplineIsNew = false;

    if (raw.uplineFid == null) {
      // 认领的上级还没进 app → 要给他建节点 → 他必须已有账号 (节点 ⇒ 账号)
      if (raw.newPhoneHash && !raw.newPhoneHash.startsWith("pending:")) {
        await requireAccountForNode(tx, raw.newPhoneHash);
      }
      const [created] = await tx
        .insert(franchisee)
        .values({
          name: raw.newName ?? "(未命名)",
          phoneEncrypted: raw.newPhoneEncrypted ?? "",
          phoneHash: raw.newPhoneHash ?? `pending:${raw.id}`,
          // 推荐关系: 沿锚点原来的推荐人 (根一般为 null) —— 新根不是把 A "推荐"进来的
          referrerId: anchor.referrerId,
          placementSide: null,
          placementPath: "",
          placementDepth: 0,
          rootId: null,
          isActive: true,
          notesEncrypted: null,
          createdBy: raw.initiatorUserId,
        })
        .returning({
          id: franchisee.id,
          rootId: franchisee.rootId,
          placementPath: franchisee.placementPath,
          placementDepth: franchisee.placementDepth,
        });
      upline = created;
      uplineIsNew = true;
    } else {
      const [u] = await tx
        .select({
          id: franchisee.id,
          rootId: franchisee.rootId,
          placementPath: franchisee.placementPath,
          placementDepth: franchisee.placementDepth,
        })
        .from(franchisee)
        .where(and(eq(franchisee.id, raw.uplineFid), isNull(franchisee.deletedAt)))
        .limit(1);
      if (!u) throw new Error("要认领的上级节点已被删除, 认领失败");
      if ((u.rootId ?? u.id) === oldRootId) {
        throw new Error("这位加盟商已经在您的加盟树里了, 不能认领为自己的上级 (会成环)");
      }
      upline = u;
    }

    const uplineRootId = upline.rootId ?? upline.id;
    const uplinePath = upline.placementPath;
    const depthShift = upline.placementDepth + 1;
    const newBasePath = uplinePath + (side === "left" ? "L." : "R.");

    // 空位兜底 (确认期间可能被人抢了 / 上级本来满了)
    const taken = await slotTaken(tx, uplineRootId, uplinePath, side);
    if (taken) throw new Error("上级这条线已经有下线了, 认领失败");

    // 我这棵树整体挂过去 (path 加基路径 + depth 整体下移 + 改宗到新树)
    // ⚠ 必须限定 root_id = 我的树 (多根: 不加这条会把别的树也一起搬走)
    await tx.execute(sql`
      UPDATE franchisee
      SET placement_path = ${newBasePath} || placement_path,
          placement_depth = placement_depth + ${depthShift},
          root_id = ${uplineRootId},
          updated_at = NOW()
      WHERE root_id = ${oldRootId} AND deleted_at IS NULL
    `);

    // 我的现根点位 = side; **不动 referrer_id** (Q5: 推荐关系不变, 点位父由 path 表达)
    await tx
      .update(franchisee)
      .set({ placementSide: side, updatedAt: sql`NOW()` })
      .where(eq(franchisee.id, anchor.id));

    if (uplineIsNew) {
      // 新节点: root_id 自指 (INSERT 时还没有 id)
      await tx
        .update(franchisee)
        .set({ rootId: upline.id, updatedAt: sql`NOW()` })
        .where(eq(franchisee.id, upline.id));
    }

    // 上级的账号绑定 + 客户档案 (新节点必绑; 已有节点则补齐缺失的绑定, 他才能登录看自己这棵树)
    await linkAccountAndCustomer(tx, {
      fid: upline.id,
      phoneHash: raw.newPhoneHash,
      phoneEncrypted: raw.newPhoneEncrypted,
      name: raw.newName ?? "(未命名)",
      createdBy: raw.initiatorUserId,
    });

    // 节点 ⇒ 账号 不变量 (主人 2026-09-21 拍)
    await assertNodeHasAccount(tx, upline.id, "上级节点");

    resultFid = upline.id;
    // 只有"新建了上级节点"才算新增了一个加盟商 → 才发推荐奖励; 复用已有节点不算
    createdOutcome = { createdPhoneHash: uplineIsNew ? raw.newPhoneHash ?? null : null };
  } else if (raw.kind === "unjoin") {
    // 解除加盟: 软删加盟记录 (点位释放; 客户档案保留 → 客户退回 种子/普通 判定)
    if (raw.moveFid == null) throw new Error("unjoin 单缺节点 id");
    const [node] = await tx
      .select()
      .from(franchisee)
      .where(and(eq(franchisee.id, raw.moveFid), isNull(franchisee.deletedAt)))
      .limit(1);
    if (!node) throw new Error("要解除的加盟商不存在");
    // 兜底再查一次 (三方确认期间可能有人给他加了下线)
    const [child] = await tx
      .select({ id: franchisee.id })
      .from(franchisee)
      .where(
        and(
          sql`${franchisee.placementPath} LIKE ${node.placementPath + "%"}`,
          sql`${franchisee.placementPath} <> ${node.placementPath}`,
          eq(franchisee.rootId, node.rootId ?? node.id),
          isNull(franchisee.deletedAt)
        )
      )
      .limit(1);
    if (child) throw new Error("这位加盟商还有下线, 解除失败");
    await tx
      .update(franchisee)
      .set({ deletedAt: sql`NOW()`, updatedAt: sql`NOW()` })
      .where(eq(franchisee.id, raw.moveFid));
    resultFid = raw.moveFid;
  } else {
    // 主人 2026-09-19: 'move' 已下线 (点位变更走 解除 → 重新加盟)
    throw new Error(
      "「移动到其他点位」功能已下线: 请解除加盟后重新落位"
    );
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

  return createdOutcome;
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

/**
 * 我发起的、还在 pending 的「认领上级」单 (图谱里「上层」那格显示「待她确认」)
 *   - 一个根同时只能有一张 (createPlacementRequest 已硬校验)
 */
export async function getMyPendingPromoteRequest(
  initiatorFid: bigint
): Promise<{ id: string; newName: string | null; uplineFid: string | null } | null> {
  const [row] = await db
    .select({
      id: franchisePlacementRequest.id,
      newName: franchisePlacementRequest.newName,
      uplineFid: franchisePlacementRequest.uplineFid,
    })
    .from(franchisePlacementRequest)
    .where(
      and(
        eq(franchisePlacementRequest.kind, "promote"),
        eq(franchisePlacementRequest.status, "pending"),
        eq(franchisePlacementRequest.initiatorFid, initiatorFid)
      )
    )
    .limit(1);
  if (!row) return null;
  return {
    id: row.id.toString(),
    newName: row.newName,
    uplineFid: row.uplineFid?.toString() ?? null,
  };
}

export async function listPendingPlacementsUnder(
  rootFid: bigint
): Promise<PendingPlacementSlot[]> {
  const [root] = await db
    .select({ path: franchisee.placementPath, rootId: franchisee.rootId })
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
        // 只有「新增加盟商」(create) 会在未来占一个**空位** → 才画虚位。
        //   解除加盟 (unjoin) 单不画 (那个点位本来就有人, 画虚位会误导)
        eq(franchisePlacementRequest.kind, "create"),
        // 同树 (B1): 只画我这一棵里的虚位
        sql`${franchisee.rootId} = ${root.rootId ?? rootFid}`,
        sql`${franchisee.placementPath} LIKE ${root.path + "%"}`
      )
    );

  return rows.map((r) => ({
    requestId: r.id.toString(),
    targetParentFid: r.targetParentFid.toString(),
    targetSide: r.targetSide,
    label: `${r.newName ?? "新加盟商"} (待确认)`,
    initiatorFid: r.initiatorFid.toString(),
  }));
}

// ============================================
// admin 强删 (主人 2026-09-18 拍): 绕过三方确认, 直接解除加盟
//   - 用途: 本人账号失效 / 无法完成三方确认的「死账」
//   - 限制: 仍然**不允许有下线** (要先处理完下线), 根节点不能删
//   - 审计: 走 withAuditContext (写 audit_log) + 这里不建申请单 (短路径)
// ============================================
export async function forceUnjoinFranchisee(
  fid: bigint,
  ctx: AuditContext
): Promise<void> {
  await withAuditContext(ctx, async (tx) => {
    const [node] = await tx
      .select()
      .from(franchisee)
      .where(and(eq(franchisee.id, fid), isNull(franchisee.deletedAt)))
      .limit(1);
    if (!node) throw new Error("加盟商不存在或已解除");
    if (node.placementPath === "") throw new Error("根节点不能解除");

    const [child] = await tx
      .select({ id: franchisee.id })
      .from(franchisee)
      .where(
        and(
          sql`${franchisee.placementPath} LIKE ${node.placementPath + "%"}`,
          sql`${franchisee.placementPath} <> ${node.placementPath}`,
          eq(franchisee.rootId, node.rootId ?? node.id),
          isNull(franchisee.deletedAt)
        )
      )
      .limit(1);
    if (child) throw new Error("这位加盟商还有下线, 要先处理完下线才能解除");

    // 同一节点若有 pending 单 → 一并关掉 (避免点位预占卡住)
    await tx
      .update(franchisePlacementRequest)
      .set({ status: "cancelled", updatedAt: sql`NOW()` })
      .where(
        and(
          eq(franchisePlacementRequest.status, "pending"),
          or(
            eq(franchisePlacementRequest.moveFid, fid),
            eq(franchisePlacementRequest.targetParentFid, fid)
          )!
        )
      );

    await tx
      .update(franchisee)
      .set({ deletedAt: sql`NOW()`, updatedAt: sql`NOW()` })
      .where(eq(franchisee.id, fid));
  });
}
