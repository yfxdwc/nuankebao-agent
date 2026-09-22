// /api/franchisees
// GET 列表 / POST 新增加盟商
// Plan F1 + ADR-0006 边界: 纯展示, 不算钱

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { referralCode } from "@/lib/db/schema";
import { normalizeReferralCode } from "@/lib/billing/referral";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  listFranchisees,
  createFranchisee,
  getFranchiseeIdByUserId,
} from "@/lib/db/queries/franchisee";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { getRbacContext } from "@/lib/auth/rbac";
import { resolvePlacementActor } from "@/lib/auth/viewer";
import { hashForLookup } from "@/lib/crypto/field";

const CreateFranchiseeSchema = z.object({
  name: z.string().min(1).max(100),
  // ★ P6 (ADR-0016 D1, 主人 2026-09-22 拍): 找账号的 handle = **邀请码**;
  //   手机号变成可选 (给了码就按码找, 姓名/手机号取自账号)
  referralCode: z.string().min(1).max(20).optional(),
  phone: z.string().regex(/^1[3-9]\d{9}$/, "手机号格式错误").optional(),
  referrerId: z.string().regex(/^\d+$/).optional().transform((v) => v ? BigInt(v) : undefined),
  sideHint: z.enum(["left", "right"]).optional(),
  notes: z.string().max(500).optional(),
}).refine((v) => !!v.referralCode || !!v.phone, {
  message: "请填对方的邀请码 (或存量兼容: 手机号)",
  path: ["referralCode"],
});

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
  const { searchParams } = new URL(request.url);
  const scope = (searchParams.get("scope") ?? "all") as
    | "mine_downline"
    | "mine_referrer"
    | "search"
    | "all";
  const search = searchParams.get("search") ?? undefined;
  const limit = parseInt(searchParams.get("limit") ?? "20");
  const offset = parseInt(searchParams.get("offset") ?? "0");

  // W5 RBAC (2026-09-22 ADR-0015 步骤 0): 角色由 getRbacContext 从 DB 读,
  //   session.user.role 只作兜底 (老 JWT 没该字段) → 管理员不再被当 sales 过滤。
  const rbacCtx = await getRbacContext(
    userId,
    (session?.user as { role?: string } | undefined)?.role
  );

  // 查 currentFranchiseeId (用于 scope=mine_*)
  let currentFranchiseeId: bigint | undefined;
  if (scope === "mine_downline" || scope === "mine_referrer") {
    const fid = await getFranchiseeIdByUserId(userId);
    if (!fid) {
      return NextResponse.json({ items: [], total: 0 });
    }
    currentFranchiseeId = fid;
  }

  const result = await listFranchisees({
    scope,
    search,
    currentFranchiseeId,
    limit,
    offset,
    rbacCtx,
  });
  return NextResponse.json(result);
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // 主人 2026-09-19 拍:
  //   ① 只有「已加盟用户或系统管理员」能设置加盟;
  //   ② 系统管理员设置加盟**不需要多方确认** → 本接口 (直接落位, 无三方确认) = 管理员专用;
  //      普通加盟商请走 POST /api/franchisees/placement-requests (三方确认)
  //   ③ 用户不能给自己设置成加盟用户
  try {
    const body = await request.json();
    const input = CreateFranchiseeSchema.parse(body);

    // 注意: 有 session 就必查 (dev DEV_SKIP_AUTH=1 只是跳过"未登录"拦截, 不是放开权限)
    if (session?.user?.id) {
      const actor = await resolvePlacementActor(session.user.id);
      if (!actor?.isAdmin) {
        return NextResponse.json(
          {
            error:
              "只有系统管理员可以直接新增加盟商；其他用户请走加盟落位（需三方确认）",
          },
          { status: 403 }
        );
      }
      // 不能给自己设置加盟 (管理员也不行)
      //   ★ P6 (ADR-0016 D3): 有邀请码时按**账号**判 (比 user id), 手机号只是存量兜底
      const isSelfByCode =
        !!input.referralCode &&
        (await (async () => {
          const mine = await db
            .select({ code: referralCode.code })
            .from(referralCode)
            .where(eq(referralCode.userId, actor.userId))
            .limit(1);
          return mine[0]?.code === normalizeReferralCode(input.referralCode);
        })());
      const selfPhoneHash = input.phone ? hashForLookup(input.phone) : null;
      const isSelfByPhone =
        !input.referralCode &&
        selfPhoneHash != null &&
        actor.phoneHash != null &&
        actor.phoneHash === selfPhoneHash;
      if (isSelfByCode || isSelfByPhone) {
        return NextResponse.json(
          { error: "不能给自己设置加盟 (必须由其他已加盟用户或系统管理员设置)" },
          { status: 400 }
        );
      }
    }

    const ctx = getAuditContextFromRequest(request, session);
    const createdBy = session?.user?.id ? BigInt(session.user.id) : BigInt(0);

    const franchisee = await createFranchisee(input, ctx, createdBy);
    return NextResponse.json(franchisee, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
          { error: "Invalid input", details: error.errors },
          { status: 400 }
        );
    }
    // Business 4xx 错误 (深度上限 / 树满 / referrer 不存在) 转 400, 避免误导用户「服务器错误」
    if (error instanceof Error) {
      const msg = error.message;
      if (msg.includes("深度上限") || msg.includes("No available position")) {
        return NextResponse.json({ error: msg }, { status: 400 });
      }
      if (msg.includes("Referrer not found")) {
        return NextResponse.json({ error: msg }, { status: 400 });
      }
    }
    console.error("[POST /api/franchisees]", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}