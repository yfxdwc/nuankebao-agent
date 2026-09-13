import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { generateTemplate } from "@/lib/import/parser";

/**
 * GET /api/import/template
 * 下载客户导入 Excel 模板
 */
export async function GET() {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const buffer = generateTemplate();
  return new Response(new Uint8Array(buffer), {
    status: 200,
    headers: {
      "Content-Type":
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": 'attachment; filename="nuankebao-customer-template.xlsx"',
    },
  });
}