// /api/franchisees/placement-requests/candidates
// 落位时「直推者」候选清单 (Phase B §6 E1, migration 0027, 主人 2026-09-25 拍)
//
// GET ?targetParentId=xxx → 返回落位后**她的祖先链**:
//   - targetParentFid 本身 (depth=0, level=0)
//   - 其上层直系 3 层 (depth=-1 / -2 / -3, level=1 / 2 / 3, 与 getUplineAncestors 同口径)
//   - 每条标 { id, name, depth, level, isSelf }
//     · depth: 该候选节点的 placement_depth (相对所在树根, 根=0)
//     · level: 相对 targetParent 的层数 (0 = 自己, 1 = 直接上层, 2 = 上 2 层, 3 = 上 3 层)
//     · isSelf: 该候选是否就是发起人 (actor.fid)
//
// 用途:
//   - Flutter 「选直推者」 picker 直接调这个接口拿数据, 默认选项 = actor.fid (若在链) 否则 = targetParent
//   - 选完回传 referrerFid 给 POST /api/franchisees/placement-requests
//
// 权限:
//   - 必须「已加盟用户」或「系统管理员」 (与 POST /api/franchisees/placement-requests 同口径)
//   - 不要求 targetParentFid 在 actor 子树内 (admin 全森林; 普通用户也可能跨枝落位;
//     这一条选直推者只看"祖先链", 落位合法性由 POST 校验)
//
// 参数:
//   - targetParentId: 必填, 正整数 (大 fid)

import { NextRequest, NextResponse } from "next/server";
import { and, eq, isNull } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { resolvePlacementActor } from "@/lib/auth/viewer";
import { db } from "@/lib/db";
import { franchisee } from "@/lib/db/schema";
import { getUplineAncestors } from "@/lib/db/queries/franchisee";

export interface ReferrerCandidate {
  /** 候选节点 id (字符串) */
  id: string;
  /** 候选节点姓名 (脱敏: 仅当 viewer 可见时给; 否则 '?') */
  name: string;
  /** 该候选的绝对层号 (相对所在树根) */
  depth: number;
  /** 该候选相对 targetParent 的层数 (0 = 自己, 1 = 直接上层, ...) */
  level: number;
  /** 是否就是发起人 (actor.fid); 用于前端默认高亮 */
  isSelf: boolean;
}

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const actor = await resolvePlacementActor(session?.user?.id);
  if (!actor) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  // 主人 2026-09-19: 只有「已加盟用户」或「系统管理员」能发起落位 → 也才有"选直推者"资格
  if (actor.fid == null && !actor.isAdmin) {
    return NextResponse.json(
      { error: "只有已加盟用户或系统管理员才能设置加盟" },
      { status: 403 },
    );
  }

  const { searchParams } = new URL(request.url);
  const targetParentIdRaw = searchParams.get("targetParentId");
  if (!targetParentIdRaw || !/^\d+$/.test(targetParentIdRaw)) {
    return NextResponse.json(
      { error: "targetParentId 必填 (正整数)" },
      { status: 400 },
    );
  }
  const targetParentFid = BigInt(targetParentIdRaw);

  // 校验 targetParentFid 是活节点 (软删/不存在 → 400, 避免前端拿到空链)
  const [parent] = await db
    .select({ id: franchisee.id, name: franchisee.name, depth: franchisee.placementDepth })
    .from(franchisee)
    .where(and(eq(franchisee.id, targetParentFid), isNull(franchisee.deletedAt)))
    .limit(1);
  if (!parent) {
    return NextResponse.json({ error: "目标点位父节点不存在" }, { status: 400 });
  }

  // 候选链 = parent 本身 + 其上层直系 3 层 (与 createPlacementRequest::resolveReferrerCandidate 同口径)
  const uplines = await getUplineAncestors(targetParentFid, 3);

  const candidates: ReferrerCandidate[] = [
    {
      id: parent.id.toString(),
      name: parent.name,
      depth: parent.depth,
      level: 0,
      isSelf: actor.fid != null && actor.fid === parent.id,
    },
    ...uplines.map((u) => ({
      id: u.id,
      name: u.name,
      depth: u.depth,
      level: u.level,
      isSelf: actor.fid != null && actor.fid === BigInt(u.id),
    })),
  ];

  // 默认直推者 = 发起人 (若在候选集内) 否则 = targetParent 本身 (候选首节点)
  const defaultReferrerFid =
    candidates.find((c) => c.isSelf)?.id ?? parent.id.toString();

  return NextResponse.json({
    targetParentId: parent.id.toString(),
    candidates,
    defaultReferrerFid,
    /** 当前账号是否在候选链内 (admin / 已加盟用户 都可能不在; admin 也不该"自己推荐自己") */
    actorInCandidates: actor.fid != null && candidates.some((c) => c.isSelf),
  });
}