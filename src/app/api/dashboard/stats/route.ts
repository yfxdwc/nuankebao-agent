import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import {
  getDashboardStats,
  getServiceDistribution,
} from "@/lib/db/queries/dashboard";

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const [stats, distribution] = await Promise.all([
    getDashboardStats(),
    getServiceDistribution(),
  ]);

  return NextResponse.json({ stats, distribution });
}