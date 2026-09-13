import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { z } from "zod";
import {
  createInteraction,
  listInteractionsByCustomer,
} from "@/lib/db/queries/interaction";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const CreateSchema = z.object({
  customerId: z.string().regex(/^\d+$/),
  type: z.enum(["phone", "wechat", "visit", "holiday_greeting", "other"]),
  summary: z.string().optional(),
  followUpAt: z.string().datetime().optional(),
});

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const customerId = searchParams.get("customerId");
  if (!customerId) {
    return NextResponse.json({ error: "customerId required" }, { status: 400 });
  }

  const items = await listInteractionsByCustomer(customerId);
  return NextResponse.json({ items });
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = CreateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const interaction = await createInteraction(input, ctx, BigInt(session.user.id));

    return NextResponse.json(interaction, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[POST /api/interactions]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}