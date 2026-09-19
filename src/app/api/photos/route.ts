import { NextRequest, NextResponse } from "next/server";
import { savePhotoFromBase64 } from "@/lib/storage/photos";
import { z } from "zod";
import { apiGuard } from "@/lib/api-guard";
import { featureGuard } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";
import { logger } from "@/lib/errors";

export const runtime = "nodejs";

const Schema = z.object({
  base64: z.string().min(1, "base64 数据缺失"),
  mimeType: z.string().regex(/^image\/(jpeg|png|webp)$/, "仅支持 jpeg/png/webp").optional(),
  // 用途: 决定要不要会员 (ADR-0012 §5)
  //   wellness/salon/other (默认) = 业务照片 → 会员功能
  //   avatar        = 个人账号头像 → 免费 (换个头像不该收费)
  //   payment_proof = 付款截图 → 免费 (**付钱的人还没会员**, 拦了就没法核对到账)
  //   payment_qr    = 收款码图片 (管理员上传) → 免费
  purpose: z
    .enum(["wellness", "salon", "avatar", "payment_proof", "payment_qr", "other"])
    .optional(),
});

/**
 * POST /api/photos
 * 上传图片 (base64), 返回 URL
 *
 * Body: { base64: "data:image/jpeg;base64,..." | "...", mimeType?: "image/jpeg" }
 * Response: { url: "/uploads/xxx.jpg", filename: "...", size: 1234 }
 */
export async function POST(request: NextRequest) {
  const guard = await apiGuard(request, { auth: true, rateLimit: "upload" });
  if (guard.response) return guard.response;

  try {
    const body = await request.json();
    const input = Schema.parse(body);

    // ADR-0012: 业务照片是会员功能 (头像 / 付款凭证 / 收款码 免费)
    const freePurposes = ["avatar", "payment_proof", "payment_qr"];
    if (!input.purpose || !freePurposes.includes(input.purpose)) {
      const gate = await featureGuard(guard.userId, FEATURES.MEDIA_UPLOAD);
      if (gate) return gate;
    }

    const result = await savePhotoFromBase64(input.base64, input.mimeType ?? undefined);

    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Invalid input", details: error.errors },
        { status: 400 }
      );
    }
    logger.error("POST /api/photos failed", {
      userId: guard.userId ?? undefined,
      ip: guard.ip ?? undefined,
    }, error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Upload failed" },
      { status: 500 }
    );
  }
}