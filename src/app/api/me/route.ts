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
//   - stats 用**跟客户列表同一口径**的全库非软删统计 (getStatsOverview(null)),
//     不是「只看我创建的」—— 客户列表本身还没接行级过滤 (listCustomers 未传 rbacCtx),
//     两块对不上就是页面自己打自己脸。口径切换点在 queries/dashboard.ts 注释里
//     (列表接了 RBAC 行级过滤后, 这里传 rbacCtx 就切换)
//   - phone 同时给 full + masked: masked 给默认展示, full 只在用户点
//     "显示" 时用 (自己看自己的号, 不算越权)
//   - 加盟关系是 1:1 但**可空** (user.franchisee_id nullable) → franchisee 可为 null,
//     客户端按「未加盟」渲染, 不是错误
//   - 软删加盟商视同未加盟 (deleted_at 过滤在 getFranchiseeById 里)
//
// 不做的事:
//   - 不返回任何金额/业绩字段 (ADR-0006 边界: 纯展示, 不算钱)
//   - 不返回其他加盟商的手机号 (只给自己的直推上级)

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { type UserRole } from "@/lib/auth/rbac";
import { db } from "@/lib/db";
import { user as userTable, store as storeTable } from "@/lib/db/schema";
import {
  getFranchiseeById,
  getFranchiseeIdByUserId,
  countDirectDownline,
} from "@/lib/db/queries/franchisee";
import { getStatsOverview, type StatsOverview } from "@/lib/db/queries/dashboard";
import { maskPhone } from "@/lib/utils";
import { parseAvatarValue, readAvatarValue } from "@/lib/avatar";
import { ensureReferralCode, getMembershipView } from "@/lib/billing/entitlements";
import { withAuditContext, getAuditContextFromRequest } from "@/lib/audit/context";
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
    // ⚠ 这里的 `referrer` 键 (= Flutter「我的上级」卡) 读 **点位父** (`placement_parent_id`),
    //   不是 `referrer_id` (推荐人) —— 拆栏后两者可以不是同一个人 (主人 2026-09-21 拍, migration 0019)。
    //   键名是历史遗留 (Flutter 已按 `referrer` 反序列化), 语义 = 我的上层点位。
    const [referrer, downline] = await Promise.all([
      franchiseeRow.placementParentId
        ? getFranchiseeById(BigInt(franchiseeRow.placementParentId))
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

  // ---- 数据概览 (口径 = 客户列表) ----
  // userId = 0 (dev 空 session) → 没有「我」, 不查统计, 明确给 null 让客户端隐藏这块
  let stats: StatsOverview | null = null;
  if (userId > BigInt(0)) {
    stats = await getStatsOverview(null);
  }

  // ---- 会员状态 + 我的推荐码 (ADR-0012) ----
  // 没有 user 行 (dev mock) → membership = null, 客户端按"免费档"渲染但不显示推荐码
  let membershipBlock = null;
  if (userId > BigInt(0) && userRow) {
    try {
      await ensureReferralCode(userId); // 幂等: 第一次访问时分配固定 6 位码
      membershipBlock = await getMembershipView(userId);
    } catch (e) {
      // 会员信息读失败不能把「我的」页打挂 —— 页面还有账号/加盟/统计要看
      console.error("[GET /api/me] membership block failed", e);
    }
  }

  return NextResponse.json({
    membership: membershipBlock,
    user: {
      id: userId.toString(),
      name: accountName,
      role,
      roleLabel: ROLE_LABELS[role] ?? "销售员",
      isActive: userRow?.isActive ?? true,
      // 自定义头像 (null = 前端画姓名首字); 脏数据当 null 读, 不让旧值把页面搞崩
      avatarUrl: readAvatarValue(userRow?.avatarUrl),
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

// ============================================
// PATCH /api/me — 自助改头像
// ============================================
// 为什么单独开 PATCH 而不是复用别的:
//   「我的」页能改的东西分两类, 权限模型不一样:
//     - 头像 / (以后) 本机偏好 → **账号自己的**: 只能改自己, 白名单字段
//     - 姓名 / 备注            → **加盟商身份**: 走 PATCH /api/franchisees/:id (有自己的审计与 RBAC)
//   混在一个端点里迟早会有人顺手把 name 也写进来, 那就绕过了加盟商那条路的校验
//
// 边界:
//   - 只接受 avatarUrl 一个字段 (Zod strict) —— 防止客户端顺手塞别的列
//   - 值必须过 src/lib/avatar.ts 白名单 (内置 preset / 本站上传), 拒外链
//   - user 表挂了 user_audit 触发器 → 改头像自动进审计日志 (谁/什么时候/改成什么)
//   - dev 空 session (DEV_SKIP_AUTH 且无 cookie) → 401, 不猜"你是 1 号"
export async function PATCH(request: NextRequest) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json(
      { error: "未登录, 不能改头像" },
      { status: 401 }
    );
  }

  const rawUserId = session.user.id;
  if (!/^\d+$/.test(rawUserId)) {
    return NextResponse.json({ error: "账号 ID 异常" }, { status: 400 });
  }
  const userId = BigInt(rawUserId);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "请求体不是合法 JSON" }, { status: 400 });
  }

  const parsedBody = z
    .object({ avatarUrl: z.unknown() })
    .strict()
    .safeParse(body);
  if (!parsedBody.success) {
    return NextResponse.json(
      { error: "只支持改 avatarUrl 这一个字段" },
      { status: 400 }
    );
  }

  const parsed = parseAvatarValue(parsedBody.data.avatarUrl);
  if (!parsed.ok) {
    return NextResponse.json({ error: parsed.reason }, { status: 400 });
  }

  const ctx = getAuditContextFromRequest(request, session);
  const updated = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(userTable)
      .set({ avatarUrl: parsed.value, updatedAt: new Date() })
      .where(eq(userTable.id, userId))
      .returning({ id: userTable.id, avatarUrl: userTable.avatarUrl });
  });

  if (updated.length === 0) {
    return NextResponse.json(
      { error: "账号不存在 (开发模式登录没有 user 行)" },
      { status: 404 }
    );
  }

  return NextResponse.json({ ok: true, avatarUrl: readAvatarValue(updated[0].avatarUrl) });
}
