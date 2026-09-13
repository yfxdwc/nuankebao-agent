import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  listFollowUpTasks,
  createFollowUpTask,
} from "@/lib/db/queries/follow-up-task";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const CreateSchema = z.object({
  customerId: z.string().regex(/^\d+$/),
  dueAt: z.string().datetime(),
  reason: z.string().min(1),
  aiSuggestion: z.string().optional(),
  assignedTo: z.string().regex(/^\d+$/).optional(),
});

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const status = (searchParams.get("status") ?? "pending") as
    | "pending"
    | "done"
    | "cancelled";
  const assignedTo = searchParams.get("assignedTo") ?? undefined;
  const limit = parseInt(searchParams.get("limit") ?? "50");
  const offset = parseInt(searchParams.get("offset") ?? "0");

  const result = await listFollowUpTasks({ status, assignedTo, limit, offset });
  return NextResponse.json(result);
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = CreateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
    const task = await createFollowUpTask(input, ctx, userId);

    return NextResponse.json(task, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[POST /api/follow-ups]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}