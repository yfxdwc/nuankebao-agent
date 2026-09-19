// GET /api/billing/pay-info — 收款方式 + 我的申请状态 (App「开通会员」弹层用)
//
// 内测通道: 个人微信收款码 + 管理员核销 (主人 2026-09-19)
// 返回里的 qrUrl 可能是静态兜底路径 /payment/wechat-qr.png (管理员还没上传时的提示)

import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getManualPayInfo, listMyManualPayments } from "@/lib/billing/manual-pay";

export async function GET() {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const info = await getManualPayInfo();

  const mine =
    session?.user?.id && /^\d+$/.test(session.user.id)
      ? (await listMyManualPayments(BigInt(session.user.id))).map((r) => ({
          id: r.id.toString(),
          status: r.status,
          amountCents: r.amountCents,
          days: r.grantedDays ?? r.days,
          createdAt: r.createdAt.toISOString(),
          rejectReason: r.rejectReason,
        }))
      : [];

  return NextResponse.json({ ...info, myRequests: mine });
}
