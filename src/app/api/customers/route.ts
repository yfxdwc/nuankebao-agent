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
import { hasFeatureAccess } from "@/lib/billing/guard";
import { stripBirthdayReminderFromList } from "@/lib/billing/membership-filter";
import { FEATURES } from "@/lib/billing/features";
import {
  attachFollowUp,
  sortByUrgency,
  summarizeFollowUp,
} from "@/lib/follow-up/attach";
import { batchRepurchaseWindows } from "@/lib/follow-up/repurchase";

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

// 排序 (主人 2026-09-20 拍: 跟进紧急度是第一排序规则; **紧急度排序只给会员**)
//   urgency = 跟进紧急度 (默认; 非会员自动降级为 new 并在响应里标 urgencyLocked)
//   recent  = 最近联系 / new = 最近添加 / name = 姓名
const SortSchema = z.enum(["urgency", "recent", "new", "name"]);
const SORT_SAFETY_LIMIT = 2000;

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const search = searchParams.get("search") ?? undefined;
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "20"), 100);
  const offset = parseInt(searchParams.get("offset") ?? "0");

  // 排序参数: 非法 → 400 (不静默降级, 免得前端传错还以为排了)
  const rawSort = searchParams.get("sort") ?? undefined;
  const parsedSort = SortSchema.safeParse(rawSort);
  if (rawSort !== undefined && !parsedSort.success) {
    return NextResponse.json(
      { error: "Invalid sort", expected: ["urgency", "recent", "new", "name"] },
      { status: 400 }
    );
  }

  // 类型筛选: 非法值 → 400 (不静默降级为 all, 免得前端传错还以为筛了)
  const rawType = searchParams.get("type") ?? undefined;
  const parsedType = CustomerTypeSchema.safeParse(rawType);
  if (rawType !== undefined && !parsedType.success) {
    return NextResponse.json(
      { error: "Invalid type", expected: ["all", "franchisee", "seed", "normal"] },
      { status: 400 }
    );
  }

  // 会员判权: 紧急度排序 = 会员功能 (主人 Q1); 生日提醒沿用既有 key
  const [urgencySortOn, birthdayReminderOn] = await Promise.all([
    hasFeatureAccess(session?.user?.id, FEATURES.AI_REPURCHASE),
    hasFeatureAccess(session?.user?.id, FEATURES.CRM_BIRTHDAY_REMINDER),
  ]);

  // 实际生效的排序: 非会员请求 urgency → 降级为 new (响应里说明)
  const requestedSort = parsedSort.success ? parsedSort.data : undefined;
  const wantsUrgency = requestedSort === undefined || requestedSort === "urgency";
  const urgencyLocked = wantsUrgency && !urgencySortOn;
  const effectiveSort = wantsUrgency
    ? urgencySortOn
      ? "urgency"
      : "new"
    : requestedSort!;

  const viewerFranchiseeId = await resolveViewerFranchiseeId(session?.user?.id);
  const listOptions = {
    search,
    type: parsedType.success ? parsedType.data : undefined,
    viewerFranchiseeId,
  };

  // 1) 取数据: 紧急度排序要在"命中全集"上排序再切片 (见 attach.ts 规模说明)
  const needAll = effectiveSort === "urgency";
  const result = await listCustomers({
    ...listOptions,
    sort: effectiveSort,
    limit: needAll ? SORT_SAFETY_LIMIT : limit,
    offset: needAll ? 0 : offset,
  });

  // 2) 会员: 批量算复购窗口 (一次 SQL; 非会员不传 → 天然不参与, 不浪费查询)
  const repurchaseWindows = urgencySortOn
    ? await batchRepurchaseWindows(result.items.map((i) => BigInt(i.id)))
    : undefined;

  // 3) 挂 followUp 块 (标签/天数/复购; 分数与复购仅会员)
  let items = await attachFollowUp(result.items, {
    isMember: urgencySortOn,
    repurchaseWindows,
  });

  // 4) 会员: 按紧急度排序 + 内存分页; 非会员: 已由 SQL 排好
  let total = result.total;
  let sortedAll: typeof items | null = null;
  if (effectiveSort === "urgency") {
    const sorted = sortByUrgency(items);
    sortedAll = sorted;
    total = sorted.length;
    items = sorted.slice(offset, offset + limit);
  }

  const payload = {
    items,
    total,
    sort: effectiveSort,
    sortRequested: requestedSort ?? "urgency",
    urgencyLocked,
    // 顶部提醒条/分组计数: 仅会员 (与紧急度同一判权, 非会员没有这套体系)
    ...(urgencySortOn
      ? { summary: summarizeFollowUp(sortedAll ?? items) }
      : {}),
  };

  // ADR-0012: 生日提醒是会员功能 —— 非会员读出来 birthdayRemindDays = null (提醒自然不触发),
  // 底层数据保留 (续费后设置自动回来)。放在 route 层而不是 query 层: 不动被 web admin 复用的查询
  if (!birthdayReminderOn) {
    return NextResponse.json(stripBirthdayReminderFromList(payload));
  }
  return NextResponse.json(payload);

  // ADR-0012: 生日提醒是会员功能 —— 非会员读出来 birthdayRemindDays = null (提醒自然不触发),
  // 底层数据保留 (续费后设置自动回来)。放在 route 层而不是 query 层: 不动被 web admin 复用的查询
  const reminderOn = await hasFeatureAccess(session?.user?.id, FEATURES.CRM_BIRTHDAY_REMINDER);
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