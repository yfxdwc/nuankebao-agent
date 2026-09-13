import { NextRequest, NextResponse } from "next/server";
import { savePhotoFromBase64 } from "@/lib/storage/photos";
import { z } from "zod";
import { apiGuard } from "@/lib/api-guard";
import { logger } from "@/lib/errors";

export const runtime = "nodejs";

const Schema = z.object({
  base64: z.string().min(1, "base64 数据缺失"),
  mimeType: z.string().regex(/^image\/(jpeg|png|webp)$/, "仅支持 jpeg/png/webp").optional(),
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