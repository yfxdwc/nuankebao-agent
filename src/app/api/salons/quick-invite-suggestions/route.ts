// ============================================
// 沙龙创建 - 快速邀请建议 (v0.1.5+)
// ============================================
// GET /api/salons/quick-invite-suggestions
//   - 不传 salonId → 创建场景用, 拉「我的客户 + 图谱上层 ≤3 层」
//   - 传 salonId  → 编辑场景预占位 (本期不做 dedup; 主理人去 manage 页管理)
// 返回 (脱敏后的明文, 仅发起人可见):
//   customers: 我 created_by = 我的 customer 档案, 最多 50
//   ancestors: 我 (按 user.franchisee_id) 沿 placement_path 向上 N=3 层加盟商
//
// 边界:
//   - 未登录 → 401 (与既有 salon route 一致)
//   - 我不是加盟节点 (没 franchisee_id) → ancestors = []
//   - 我是树根 → ancestors = []
//   - 客户/上层已软删 → 不计入
//   - 多根 (B1): ancestors 必须同 rootId, 防止跨根串味
//   - 上限: 客户 50 + 上层 3 = 53 条候选, UI 默认全选? 由用户决定
// ============================================

import { NextResponse } from "next/server";
import { and, desc as descSql, eq, isNull, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import { decryptField } from "@/lib/crypto/field";
import { requireUserId, handleRouteError } from "@/lib/salon/route-helpers";
import { getFranchiseeIdByUserId, getUplineAncestors } from "@/lib/db/queries/franchisee";

const MAX_CUSTOMER_SUGGESTIONS = 50;
const MAX_ANCESTOR_LEVELS = 3;

export async function GET() {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  try {
    const userId = authRes.userId;

    // 1) 我的客户: created_by = 我, 未软删
    //    按最近联系优先 (lastInteractionAt DESC NULLS LAST), 再按创建时间
    const customerRows = await db
      .select({
        id: customer.id,
        name: customer.name,
        phoneEncrypted: customer.phoneEncrypted,
        // ★ ID 化 (ADR-0016 D3): 只看已建客户里"也注册了账号"的 (走 user.customer_id)
        isMember: sql<boolean>`EXISTS (
          SELECT 1 FROM "user" u
          WHERE u.customer_id = ${customer.id} AND u.is_active = true
        )`,
      })
      .from(customer)
      .where(
        and(eq(customer.createdBy, userId), isNull(customer.deletedAt))
      )
      .orderBy(
        descSql(customer.lastInteractionAt),
        descSql(customer.createdAt)
      )
      .limit(MAX_CUSTOMER_SUGGESTIONS);

    // 2) 加盟图谱上层 (≤3 层)
    const fid = await getFranchiseeIdByUserId(userId);
    const ancestorRows = fid == null ? [] : await getUplineAncestors(fid, MAX_ANCESTOR_LEVELS);

    return NextResponse.json({
      customers: customerRows.map((c) => ({
        id: c.id.toString(),
        name: c.name,
        phone: decryptField(c.phoneEncrypted),
        isMember: c.isMember === true,
      })),
      ancestors: ancestorRows.map((a) => ({
        id: a.id,
        name: a.name,
        phone: decryptField(a.phoneEncrypted),
        isMember: a.isMember,
        /** 上层层号: 1 = 我的直接上层, 2 = 上 2 层, 3 = 上 3 层 */
        level: a.level,
        /** 我在她下面的线别 ('left' = A线 / 'right' = B线 / null = 树根) */
        side: a.side,
      })),
    });
  } catch (e) {
    return handleRouteError(e, "GET /api/salons/quick-invite-suggestions");
  }
}