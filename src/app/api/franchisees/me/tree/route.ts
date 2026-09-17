// /api/franchisees/me/tree
// GET 以当前 user 为中心的加盟树
//   ?depth=N (N<=4 安全限制, ADR-0010)
//   ?mode=referrer|placement (默认 referrer = 旧行为, 冻结的 web admin 不受影响)
//     - referrer  : 推荐树 (按 referrer_id 连)
//     - placement : 二叉树 (按 placement_path 连) + 每节点 relation 直推/下级引荐/上级引荐

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import {
  getFranchiseeIdByUserId,
  getFranchiseeTree,
  getPlacementTree,
} from "@/lib/db/queries/franchisee";

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
  const fid = await getFranchiseeIdByUserId(userId);

  const { searchParams } = new URL(request.url);
  const depth = Math.min(
    parseInt(searchParams.get("depth") ?? "3"),
    4 // ADR-0010: ≤4 层硬限 (主人 2026-09-16 override, dev/test seed data 需求)
  );

  // ★ 业务空状态 (非错误): user 没加盟关系 → 返回 200 + 空树.
  //   旧版返回 404 + 'User has no franchisee record', Flutter ErrorState
  //   兜底为「网络不太好」, 误导用户. 业务上「未加盟」是合法状态,
  //   应走 empty state, 不是网络错误.
  if (!fid) {
    return NextResponse.json({
      id: "0",
      name: "未加盟",
      placementSide: null,
      placementDepth: 0,
      placementPath: "",
      referrerId: null,
      relation: "root",
      children: [],
    });
  }

  const mode = searchParams.get("mode") === "placement" ? "placement" : "referrer";
  const tree =
    mode === "placement"
      ? await getPlacementTree(fid, depth)
      : await getFranchiseeTree(fid, depth);
  if (!tree) {
    // franchiseeId 存在但记录被删/查不到 → 真正的 404 (前后端不一致)
    return NextResponse.json({ error: "Tree root not found" }, { status: 404 });
  }
  return NextResponse.json(tree);
}