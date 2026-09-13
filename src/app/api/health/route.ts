import { NextResponse } from "next/server";
import { checkDb } from "@/lib/db";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * 健康检查端点
 * W1 验收标准: GET /api/health → 200 { status: "healthy", checks: { db: "ok" } }
 */
export async function GET() {
  const checks: Record<string, "ok" | "error"> = {};
  const errors: string[] = [];

  // 数据库健康
  try {
    const dbOk = await checkDb();
    checks.db = dbOk ? "ok" : "error";
    if (!dbOk) errors.push("database check returned false");
  } catch (error) {
    checks.db = "error";
    errors.push(`database: ${String(error)}`);
  }

  const isHealthy = Object.values(checks).every((v) => v === "ok");

  return NextResponse.json(
    {
      status: isHealthy ? "healthy" : "unhealthy",
      checks,
      errors: errors.length > 0 ? errors : undefined,
      version: "0.1.0",
      phase: "Phase 1 W1",
      timestamp: new Date().toISOString(),
    },
    { status: isHealthy ? 200 : 503 }
  );
}