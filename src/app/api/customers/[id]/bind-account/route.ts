// ============================================
// POST /api/customers/[id]/bind-account — 绑定 app 身份 (填邀请码)
// ============================================
// 主人 2026-09-22 拍:
//   「当用户先自建的客户 (没注册 app 账号), 之后这个客户注册使用了 app,
//     要能在**客户详情页**中填写客户的**邀请码 (身份识别码)** 绑定用户身份,
//     并在**客户列表**中显示标识。同为 app 用户方便在 app 内邀请/通过会议。」
//
// 与「加为我的客户 (claim)」的区别:
//   claim        = 归属声明 (谁负责维护她) → 写 customer.owner_id
//   bind-account = 身份绑定 (她是不是 app 用户) → 写 user.customer_id
//   两件事互不依赖: 可以先建档后绑定, 也可以先 claim 后绑定。
//
// 安全: 只能绑定**在我可见范围内** (我的客户) 的档案 —— 口径与 /api/customers/[id] 一致。

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { bindCustomerAccount } from "@/lib/db/queries/customer";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getCustomerById } from "@/lib/db/queries/customer";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const BindSchema = z.object({
  /** 她的邀请码 (6 位, 身份识别码) */
  referralCode: z.string().min(1).max(20),
  /** 手机号不一致时, 是否用账号手机号更新客户档案 (默认不动档案上的号) */
  syncPhone: z.boolean().optional(),
});

const FAILURE: Record<
  "NOT_FOUND" | "CODE_NOT_FOUND" | "BOUND_TO_OTHER" | "PHONE_CONFLICT",
  { status: number; error: string }
> = {
  NOT_FOUND: { status: 404, error: "客户不存在" },
  CODE_NOT_FOUND: {
    status: 400,
    error: "这个邀请码没有对应的账号 —— 请核对 6 位码, 或让对方先注册 app",
  },
  BOUND_TO_OTHER: { status: 409, error: "绑定冲突" },
  PHONE_CONFLICT: { status: 409, error: "手机号冲突" },
};

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  try {
    const body = await request.json();
    const input = BindSchema.parse(body);

    // 范围校验 (与详情接口同口径): 不在我的客户里 → 404, 不泄露存在性
    const rbacCtx = await getRbacContextForSession(session);
    const visible = await getCustomerById(BigInt(id), {
      viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
      scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
    });
    if (!visible) {
      return NextResponse.json({ error: "客户不存在" }, { status: 404 });
    }

    const res = await bindCustomerAccount(
      BigInt(id),
      input.referralCode,
      { syncPhone: input.syncPhone },
      getAuditContextFromRequest(request, session)
    );

    if (!res.ok) {
      const f = FAILURE[res.code];
      return NextResponse.json(
        { error: res.detail ? `${f.error}: ${res.detail}` : f.error, code: res.code },
        { status: f.status }
      );
    }

    return NextResponse.json({
      ok: true,
      alreadyBound: res.alreadyBound,
      phoneMismatch: res.phoneMismatch,
      phoneSynced: res.phoneSynced,
      replacedEmptyProfile: res.replacedEmptyProfile,
      account: {
        userId: res.account.userId.toString(),
        name: res.account.name,
        phoneMasked: res.account.phoneMasked,
      },
      message: res.alreadyBound
        ? `已经是绑定的账号 (${res.account.name})`
        : res.replacedEmptyProfile
          ? `已绑定 (${res.account.name}) —— 她注册时系统自动建的空档案已并入这条`
          : res.phoneMismatch && !res.phoneSynced
            ? `已绑定 (${res.account.name}); ⚠ 与账号手机号不一致 (账号: ${res.account.phoneMasked})`
            : res.phoneSynced
              ? `已绑定 (${res.account.name}), 手机号已同步为 ${res.account.phoneMasked}`
              : `已绑定 (${res.account.name})`,
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Invalid input", details: error.errors },
        { status: 400 }
      );
    }
    console.error("[POST /api/customers/[id]/bind-account]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
