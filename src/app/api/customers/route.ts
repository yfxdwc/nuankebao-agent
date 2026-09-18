import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { resolveViewerFranchiseeId } from "@/lib/auth/viewer";
import { z } from "zod";
import {
  listCustomers,
  createCustomer,
} from "@/lib/db/queries/customer";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const CreateCustomerSchema = z.object({
  name: z.string().min(1).max(100),
  phone: z.string().regex(/^1[3-9]\d{9}$/, "手机号格式错误"),
  gender: z.enum(["M", "F", "U"]).optional(),
  birthYear: z.number().int().min(1900).max(new Date().getFullYear()).optional(),
  // 生日细化 (主人 2026-09-18): 月/日可缺; 历法 solar/lunar; 提醒强度 7/3/0
  birthMonth: z.number().int().min(1).max(12).nullable().optional(),
  birthDay: z.number().int().min(1).max(31).nullable().optional(),
  birthCalendar: z.enum(["solar", "lunar"]).optional(),
  birthdayRemindDays: z.number().int().refine((v) => [7, 3, 0].includes(v), {
    message: "提醒强度只能是 7 / 3 / 0 (天)",
  }).nullable().optional(),
  healthTags: z.array(z.string()).optional(),
  diseaseHistory: z.string().optional(),
  allergyHistory: z.string().optional(),
  notes: z.string().optional(),
  // 客户推荐人 (客户页图谱关系边). null/undefined = 无推荐人
  referrerId: z.string().regex(/^\d+$/, "推荐人 ID 格式错误").nullable().optional(),
  // 客户头像: 'preset:<id>' / '/uploads/x.jpg' / null(= 默认首字)
  // 白名单/格式校验在 src/lib/avatar.ts (query 层执行, 非法值 → 400)
  avatar: z.string().max(300).nullable().optional(),
  // 种子客户 (潜在客户开关, 主人 2026-09-18). 缺省 false (老客户端不发也能跑)
  isSeed: z.boolean().optional(),
});

// 列表类型筛选 (胶囊按键: 全部/加盟/普通/种子)
const CustomerTypeSchema = z.enum(["all", "franchisee", "seed", "normal"]);

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const search = searchParams.get("search") ?? undefined;
  const limit = parseInt(searchParams.get("limit") ?? "20");
  const offset = parseInt(searchParams.get("offset") ?? "0");

  // 类型筛选: 非法值 → 400 (不静默降级为 all, 免得前端传错还以为筛了)
  const rawType = searchParams.get("type") ?? undefined;
  const parsedType = CustomerTypeSchema.safeParse(rawType);
  if (rawType !== undefined && !parsedType.success) {
    return NextResponse.json(
      { error: "Invalid type", expected: ["all", "franchisee", "seed", "normal"] },
      { status: 400 }
    );
  }

  const result = await listCustomers({
    search,
    limit,
    offset,
    type: parsedType.success ? parsedType.data : undefined,
    viewerFranchiseeId: await resolveViewerFranchiseeId(session?.user?.id),
  });
  return NextResponse.json(result);
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = CreateCustomerSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
    const customer = await createCustomer(
      input,
      ctx,
      userId,
      await resolveViewerFranchiseeId(session?.user?.id)
    );

    return NextResponse.json(customer, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[POST /api/customers]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}