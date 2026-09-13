// /api/franchisees/me/tree
// GET 以当前 user 为中心的加盟二叉树
// Plan F1: depth 默认 3, 可选 ?depth=N (N<=10 安全限制)

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import {
  getFranchiseeIdByUserId,
  getFranchiseeTree,
} from "@/lib/db/queries/franchisee";

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
  const fid = await getFranchiseeIdByUserId(userId);
  if (!fid) {
    return NextResponse.json(
      { error: "User has no franchisee record" },
      { status: 404 }
    );
  }

  const { searchParams } = new URL(request.url);
  const depth = Math.min(
    parseInt(searchParams.get("depth") ?? "3"),
    3 // W5 RBAC: ≤3 层硬限 (ADR-0006 / 《禁止传销条例》红线)
  );

  const tree = await getFranchiseeTree(fid, depth);
  if (!tree) {
    return NextResponse.json({ error: "Tree root not found" }, { status: 404 });
  }
  return NextResponse.json(tree);
}