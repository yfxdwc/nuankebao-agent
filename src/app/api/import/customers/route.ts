import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { parseImportFile } from "@/lib/import/parser";
import { validateImport } from "@/lib/import/validator";
import { importCustomers } from "@/lib/import/importer";
import { getAuditContextFromRequest } from "@/lib/audit/context";

export const runtime = "nodejs";

/**
 * POST /api/import/customers
 * multipart/form-data: file=...
 *
 * 两种模式:
 * - ?mode=preview  返回校验结果(不写入)
 * - ?mode=commit   写入 DB
 */
export async function POST(request: NextRequest) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const formData = await request.formData();
  const file = formData.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json({ error: "未提供文件" }, { status: 400 });
  }

  const { searchParams } = new URL(request.url);
  const mode = searchParams.get("mode") ?? "preview";

  try {
    const arrayBuffer = await file.arrayBuffer();
    const parsed = parseImportFile(arrayBuffer);
    const validation = await validateImport(parsed.rows);

    if (mode === "preview") {
      return NextResponse.json({
        mode: "preview",
        fileName: file.name,
        fileSize: file.size,
        total: parsed.totalRows,
        validCount: validation.validCount,
        invalidCount: validation.invalidCount,
        duplicateCount: validation.duplicateCount,
        results: validation.results,
      });
    }

    // commit 模式: 写入 DB
    const ctx = getAuditContextFromRequest(request, session);
    const userId = BigInt(session.user.id);
    const validRows = validation.results.filter((r) => r.valid);
    const summary = await importCustomers(validRows, userId, ctx.ipAddress ?? null);

    return NextResponse.json({
      mode: "commit",
      ...summary,
    });
  } catch (error) {
    console.error("[POST /api/import/customers]", error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "导入失败" },
      { status: 500 }
    );
  }
}