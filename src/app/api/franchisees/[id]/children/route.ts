// /api/franchisees/:id/children
// GET 某加盟商的**直接子级** (客户页图谱懒加载, ADR-0011 主人 2026-09-18 拍)
//
// 为什么单开一个端点:
//   - 层级不限后, 一个大网络全量拉树会拉爆 JSON (满二叉 10 层 = 2047 节点, 16 层 = 13 万)
//   - 图谱改成「先画 1-2 层 → 用户点节点再展开」→ 单次只拉一级, 载荷恒定为 O(子级数)
//
// 权限: :id 必须在我 (session → user.franchisee_id) 的 placement 子树里, 否则空数组
//       (服务端兼底; 客户页图谱本来就只画我的下线)
// 响应: { id, name, children: TreeNode[] }  (子女带 hasChildren, 前端知道还能不能再展开)
// 404: :id 这个加盟商不存在 / 已软删

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { resolveViewerFranchiseeId } from "@/lib/auth/viewer";
import { getFranchiseeChildren, getFranchiseeById } from "@/lib/db/queries/franchisee";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  const viewerFranchiseeId = await resolveViewerFranchiseeId(session?.user?.id);
  const node = await getFranchiseeById(BigInt(id));
  if (!node) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const children = await getFranchiseeChildren(BigInt(id), viewerFranchiseeId);

  return NextResponse.json({
    id: node.id,
    name: node.name,
    children: children ?? [],
  });
}
