// ============================================
// GET /api/me — 当前登录者的完整资料 (Flutter 「我的」页)
// ============================================
// 为什么单独开一个端点 (而不是让客户端拼 3 个请求):
//   「我的」页首屏要的东西全是"关于我"的: 账号(user) / 加盟身份(franchisee)
//   / 上级(referrer) / 门店(store) / 我的数据(stats) —— 客户端拼 = 4 个
//   串行请求 + 各自的 loading/error 状态; 服务端一次 join 完给一份快照,
//   页面只有一个 loading, 一次能刷新。
//
// 边界 (跟 CHARTER §3.6 RBAC 对齐):
//   - stats 用 **当前登录者 RBAC 口径** (getMyStats), 不是全库数字
//     (旧「我的」页显示的是全库统计, 销售员看到的是别人的客户数 = 误导)
//   - phone 同时给 full + masked: masked 给默认展示, full 只在用户点
//     "显示" 时用 (自己看自己的号, 不算越权)
//   - 加盟关系是 1:1 但**可空** (user.franchisee_id nullable) → franchisee 可为 null,
//     客户端按「未加盟」渲染, 不是错误
//   - 软删加盟商视同未加盟 (deleted_at 过滤在 getFranchiseeById 里)
//
// 不做的事:
//   - 不返回任何金额/业绩字段 (ADR-0006 边界: 纯展示, 不算钱)
//   - 不返回其他加盟商的手机号 (只给自己的直推上级)

import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getRbacContext, type UserRole } from "@/lib/auth/rbac";
import { db } from "@/lib/db";
import { user as userTable, store as storeTable } from "@/lib/db/schema";
import {
  getFranchiseeById,
  getFranchiseeIdByUserId,
  countDirectDownline,
} from "@/lib/db/queries/franchisee";
import { getMyStats, type MyStats } from "@/lib/db/queries/dashboard";
import { maskPhone } from "@/lib/utils";
import type { PlacementSide } from "@/lib/db/schema";

export const dynamic = "force-dynamic";

const ROLE_LABELS: Record<UserRole, string> = {
  admin: "管理员",
  manager: "店长",
  sales: "销售员",
};

interface PhonePair {
  full: string;
  masked: string;
}

function phonePair(phone: string | null | undefined): PhonePair | null {
  if (!phone) return null;
  return { full: phone, masked: maskPhone(phone) };
}

/** 二叉树位置 → 大白话 (中老年销售看得懂: A线/B线 是客户图谱里的叫法) */
function sideLabel(side: PlacementSide | null | undefined): string {
  if (side === "left") return "A 线 (左)";
  if (side === "right") return "B 线 (右)";
  return "顶级 (无上级)";
}

function depthLabel(depth: number): string {
  return depth === 0 ? "顶级" : `第 ${depth} 层`;
}

export async function GET() {
  const session = await auth();
  const authSkipped = isAuthSkipped();

  if (!authSkipped && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // dev / DEV_SKIP_AUTH 下可能完全没有 session → 走 userId 0 (查不到任何行),
  // 下面统一走「账号信息缺失」分支, 不抛 500
  const rawUserId = session?.user?.id ?? "";
  const userId = /^\d+$/.test(rawUserId) ? BigInt(rawUserId) : BigInt(0);

  const [userRow] = await db
    .select()
    .from(userTable)
    .where(eq(userTable.id, userId))
    .limit(1);

  // 账号行不存在 (dev mock 登录 / 老数据): 只用 session 里有的东西兜底
  // (session.name / session.phone 是 Auth.js jwt callback 塞进去的)
  const sessionUser = session?.user as
    | { name?: string | null; phone?: string | null }
    | undefined;

  const role = ((userRow?.role as UserRole) ??
    (session?.user as { role?: string } | undefined)?.role ??
    "sales") as UserRole;

  const accountName = userRow?.name ?? sessionUser?.name ?? "未命名账号";
  const accountPhone = userRow
    ? phonePair(sessionUser?.phone ?? null) // user 表只有 phone_encrypted, session 里有明文
    : phonePair(sessionUser?.phone);

  // ---- 我的加盟身份 (1:1, 可空) ----
  const franchiseeId = userRow ? await getFranchiseeIdByUserId(userId) : null;
  const franchiseeRow = franchiseeId
    ? await getFranchiseeById(franchiseeId)
    : null;

  let franchisee = null;
  if (franchiseeRow) {
    const [referrer, downline] = await Promise.all([
      franchiseeRow.referrerId
        ? getFranchiseeById(BigInt(franchiseeRow.referrerId))
        : Promise.resolve(null),
      countDirectDownline(franchiseeId as bigint),
    ]);

    franchisee = {
      id: franchiseeRow.id,
      name: franchiseeRow.name,
      phone: phonePair(franchiseeRow.phone),
      isActive: franchiseeRow.isActive,
      notes: franchiseeRow.notes,
      joinedAt: franchiseeRow.joinedAt,
      placement: {
        side: franchiseeRow.placementSide,
        sideLabel: sideLabel(franchiseeRow.placementSide),
        depth: franchiseeRow.placementDepth,
        depthLabel: depthLabel(franchiseeRow.placementDepth),
        path: franchiseeRow.placementPath,
      },
      referrer: referrer
        ? {
            id: referrer.id,
            name: referrer.name,
            phone: phonePair(referrer.phone),
          }
        : null,
      downline,
    };
  }

  // ---- 门店 (user.default_store_id, 多数账号为空) ----
  let store: { id: string; name: string } | null = null;
  if (userRow?.defaultStoreId != null) {
    const [storeRow] = await db
      .select({ id: storeTable.id, name: storeTable.name })
      .from(storeTable)
      .where(eq(storeTable.id, userRow.defaultStoreId))
      .limit(1);
    if (storeRow) {
      store = { id: storeRow.id.toString(), name: storeRow.name };
    }
  }

  // ---- 我的数据 (RBAC 口径) ----
  // userId = 0 (dev 空 session) 时不查统计: RBAC 会退化成「sales 无店 → created_by = 0」,
  // 返回全 0 没意义, 不如明确给 null 让客户端隐藏这块
  let stats: MyStats | null = null;
  if (userId > BigInt(0)) {
    const rbacCtx = await getRbacContext(userId, role);
    stats = await getMyStats(rbacCtx);
  }

  return NextResponse.json({
    user: {
      id: userId.toString(),
      name: accountName,
      role,
      roleLabel: ROLE_LABELS[role] ?? "销售员",
      isActive: userRow?.isActive ?? true,
      createdAt: userRow?.createdAt ?? null,
      // dev mock 登录没有 user 行 → 告诉客户端"账号信息不完整", 页面给提示而不是装没事
      hasUserRecord: Boolean(userRow),
    },
    phone: accountPhone,
    store,
    franchisee,
    stats,
    dev: {
      authSkipped,
      sessionUserId: rawUserId || null,
    },
  });
}
