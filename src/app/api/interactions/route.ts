import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
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
  if (!isAuthSkipped() && !session?.user?.id) {
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
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = CreateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    // dev 模式 (DEV_SKIP_AUTH=1) session 为 null → 同 customers/route.ts 约定用 0
    const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
    const interaction = await createInteraction(input, ctx, userId);

    return NextResponse.json(interaction, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[POST /api/interactions]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}