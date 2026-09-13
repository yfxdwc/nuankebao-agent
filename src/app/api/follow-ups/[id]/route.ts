import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  completeFollowUpTask,
  cancelFollowUpTask,
} from "@/lib/db/queries/follow-up-task";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const CompleteSchema = z.object({
  action: z.enum(["complete", "cancel"]),
  notes: z.string().optional(),
});

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const body = await request.json();
    const input = CompleteSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const task =
      input.action === "complete"
        ? await completeFollowUpTask(BigInt(id), input.notes, ctx)
        : await cancelFollowUpTask(BigInt(id), ctx);

    if (!task) {
      return NextResponse.json({ error: "Not found or already completed" }, { status: 404 });
    }
    return NextResponse.json(task);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[PATCH /api/follow-ups/[id]]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}