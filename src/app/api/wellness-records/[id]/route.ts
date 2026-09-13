import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { z } from "zod";
import {
  getWellnessRecordById,
  updateWellnessRecord,
  deleteWellnessRecord,
} from "@/lib/db/queries/wellness-record";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const UpdateSchema = z.object({
  serviceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  serviceItemId: z.string().regex(/^\d+$/).optional(),
  staffId: z.string().regex(/^\d+$/).nullable().optional(),
  storeId: z.string().regex(/^\d+$/).nullable().optional(),
  bodyPartIds: z.array(z.string().regex(/^\d+$/)).optional(),
  productUsages: z
    .array(
      z.object({
        productId: z.string().regex(/^\d+$/),
        quantity: z.number().nonnegative().optional(),
      })
    )
    .optional(),
  preCondition: z.record(z.string(), z.unknown()).optional(),
  postCondition: z.record(z.string(), z.unknown()).optional(),
  processNote: z.string().optional(),
  customerFeedback: z.string().optional(),
  photos: z.array(z.string()).optional(),
  nextAdviceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
});

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const record = await getWellnessRecordById(BigInt(id));
  if (!record) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(record);
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const body = await request.json();
    const input = UpdateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const record = await updateWellnessRecord(BigInt(id), input, ctx);

    if (!record) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    return NextResponse.json(record);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[PATCH /api/wellness-records/[id]]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const ctx = getAuditContextFromRequest(request, session);
  const success = await deleteWellnessRecord(BigInt(id), ctx);

  if (!success) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ success: true });
}