import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { getOverviewReport } from "@/lib/db/queries/reports";

export async function GET() {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const report = await getOverviewReport();
  return NextResponse.json(report);
}