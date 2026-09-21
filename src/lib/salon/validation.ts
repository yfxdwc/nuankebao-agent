// ============================================
// 沙龙 API 校验 schema (v0.1.5 Phase 7)
// ============================================
// POST /api/salons 与 PATCH /api/salons/[id] 共用; 更新走 partial。
// 手机号格式与 customer / franchisee 一致 (^1[3-9]\d{9}$)。
// ============================================

import { z } from "zod";

export const SalonStatusSchema = z.enum([
  "draft",
  "published",
  "registration_closed",
  "ongoing",
  "finished",
  "cancelled",
]);

export const SalonInvitationStatusSchema = z.enum([
  "pending",
  "accepted",
  "tentative",
  "declined",
  "waitlist",
  "attended",
  "absent",
  "cancelled",
]);

export const SalonGuestStatusSchema = z.enum([
  "pending",
  "accepted",
  "declined",
  "attended",
  "absent",
  "cancelled",
]);

export const SalonVisibilitySchema = z.enum(["all", "staff", "organizer"]);

export const PhoneSchema = z
  .string()
  .regex(/^1[3-9]\d{9}$/, "手机号格式错误");

export const SalonAgendaItemSchema = z.object({
  start: z.string().max(20).optional(),
  end: z.string().max(20).optional(),
  title: z.string().min(1).max(100),
  desc: z.string().max(500).optional(),
});

export const SalonFormFieldSchema = z.object({
  key: z.string().min(1).max(50),
  label: z.string().min(1).max(50),
  type: z.enum(["text", "number", "select", "multiselect", "textarea", "date", "boolean"]),
  required: z.boolean().optional(),
  options: z.array(z.string().max(50)).max(50).optional(),
  placeholder: z.string().max(100).optional(),
});

export const SalonVisibilitySettingsSchema = z.object({
  attendeeList: z.enum(["all", "staff", "organizer"]),
  staffContact: z.enum(["all", "staff"]),
});

const nullableText = (max = 500) => z.string().max(max).nullable().optional();

/** 沙龙可写字段 (create 与 update 共用) */
export const SalonWritableSchema = z.object({
  title: z.string().min(1).max(100).optional(),
  subtitle: nullableText(100),
  description: nullableText(2000),
  coverUrl: nullableText(300),
  themeTags: z.array(z.string().max(20)).max(10).optional(),
  status: SalonStatusSchema.optional(),

  startAt: z.string().datetime({ offset: true }).optional(),
  endAt: z.string().datetime({ offset: true }).nullable().optional(),
  registrationDeadlineAt: z.string().datetime({ offset: true }).nullable().optional(),
  timezone: z.string().max(50).optional(),

  locationName: nullableText(100),
  address: nullableText(200),
  floorRoom: nullableText(50),
  lat: z.coerce.string().max(24).nullable().optional(),
  lng: z.coerce.string().max(24).nullable().optional(),
  parkingInfo: nullableText(500),

  transportPublic: nullableText(500),
  transportDriving: nullableText(500),
  transportPickup: nullableText(500),

  cateringMealType: z.enum(["none", "breakfast", "lunch", "dinner", "tea"]).nullable().optional(),
  cateringCuisine: nullableText(100),
  cateringDietary: nullableText(500),
  cateringTime: nullableText(50),
  cateringPayer: nullableText(50),

  lodgingHotelName: nullableText(100),
  lodgingRoomType: nullableText(100),
  lodgingPriceCents: z.number().int().min(0).max(100_000_00).nullable().optional(),
  lodgingContactName: nullableText(50),
  lodgingContactPhone: PhoneSchema.nullable().optional(),
  lodgingDeadlineAt: z.string().datetime({ offset: true }).nullable().optional(),
  lodgingNote: nullableText(500),

  dressCode: nullableText(100),
  feeType: z.enum(["free", "aa", "organizer_pays", "paid"]).optional(),
  feeAmountCents: z.number().int().min(0).max(100_000_00).nullable().optional(),
  feeNote: nullableText(300),

  capacityTotal: z.number().int().min(1).max(100_000).nullable().optional(),
  capacityReserved: z.number().int().min(0).max(100_000).optional(),

  agenda: z.array(SalonAgendaItemSchema).max(50).optional(),
  registrationFormSchema: z.array(SalonFormFieldSchema).max(30).optional(),
  visibilitySettings: SalonVisibilitySettingsSchema.optional(),
});

export const StaffInputSchema = z.object({
  name: z.string().min(1).max(50),
  phone: PhoneSchema,
  staffRole: z.string().max(50).nullable().optional(),
});

export const InviteeInputSchema = z.object({
  name: z.string().min(1).max(50),
  phone: PhoneSchema,
  expectedGuestCount: z.number().int().min(0).max(1000).optional(),
});

// 沙龙时间校验 (create + update 共用):
// - startAt 给出时, 不能早于当前时间
// - endAt 与 startAt 同时给出时, endAt 不能早于 startAt
// - update 为 partial, 不传 startAt / endAt 则跳过 (走原值, 不再校验)
// - 只传 endAt 不传 startAt 时, 本层无 DB 上下文, 跳过; 已知限制, 不在 schema 层查 DB
type SalonTimeCheck = { startAt?: string | null; endAt?: string | null };
function checkSalonTimes(val: SalonTimeCheck, ctx: z.RefinementCtx) {
  if (!val.startAt) return;
  const startMs = Date.parse(val.startAt);
  if (Number.isNaN(startMs)) return; // 格式错误已由 .datetime() 拦下
  if (startMs < Date.now()) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["startAt"],
      message: "开始时间不能早于当前时间",
    });
  }
  if (!val.endAt) return;
  const endMs = Date.parse(val.endAt);
  if (!Number.isNaN(endMs) && endMs < startMs) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["endAt"],
      message: "结束时间不能早于开始时间",
    });
  }
}

/** 创建: title / startAt 必填; 可带首批会务 + 受邀者 */
export const SalonCreateSchema = SalonWritableSchema.extend({
  title: z.string().min(1).max(100),
  startAt: z.string().datetime({ offset: true }),
  staff: z.array(StaffInputSchema).max(50).optional(),
  invitees: z.array(InviteeInputSchema).max(500).optional(),
}).superRefine(checkSalonTimes);

/** 更新: 全字段可选 (partial, 不含首批名单); 复用时间校验 */
export const SalonUpdateSchema = SalonWritableSchema.partial().superRefine(
  // partial 后 startAt 可能为 undefined; refine 签名已声明 startAt?: string | null
  checkSalonTimes as (val: unknown, ctx: z.RefinementCtx) => void
);

export const InvitationCreateSchema = z.object({
  name: z.string().min(1).max(50),
  phone: PhoneSchema,
  roleInSalon: z.enum(["attendee", "staff"]).optional(),
  staffRole: z.string().max(50).nullable().optional(),
  expectedGuestCount: z.number().int().min(0).max(1000).optional(),
});

export const InvitationUpdateSchema = z.object({
  name: z.string().min(1).max(50).optional(),
  status: SalonInvitationStatusSchema.optional(),
  staffRole: z.string().max(50).nullable().optional(),
  actualGuestCount: z.number().int().min(0).max(1000).nullable().optional(),
  roleInSalon: z.enum(["attendee", "staff"]).optional(),
});

export const RsvpSchema = z.object({
  status: z.enum(["accepted", "declined", "tentative"]),
  expectedGuestCount: z.number().int().min(0).max(1000).optional(),
  notes: z.string().max(500).nullable().optional(),
  registrationData: z.record(z.unknown()).nullable().optional(),
});

export const QuotaUpsertSchema = z.object({
  assignedToUserId: z.string().regex(/^\d+$/, "用户 ID 格式错误"),
  quotaValue: z.number().int().min(1).max(1000),
  deadlineAt: z.string().datetime({ offset: true }).nullable().optional(),
  note: z.string().max(200).nullable().optional(),
});

export const GuestCreateSchema = z.object({
  name: z.string().min(1).max(50),
  phone: PhoneSchema,
  relation: z.enum(["client", "friend", "family", "colleague", "other"]).nullable().optional(),
  status: SalonGuestStatusSchema.optional(),
  notes: z.string().max(500).nullable().optional(),
});

export const GuestUpdateSchema = z.object({
  name: z.string().min(1).max(50).optional(),
  relation: z.enum(["client", "friend", "family", "colleague", "other"]).nullable().optional(),
  status: SalonGuestStatusSchema.optional(),
  actualAttended: z.boolean().optional(),
  notes: z.string().max(500).nullable().optional(),
});

export const ActivityCreateSchema = z.object({
  content: z.string().min(1).max(2000),
  type: z.enum(["announcement", "question", "comment"]).optional(),
  visibility: SalonVisibilitySchema.optional(),
});

export const AttachmentCreateSchema = z.object({
  name: z.string().min(1).max(100),
  fileUrl: z.string().max(300),
  fileType: z.enum(["image", "file"]).optional(),
  visibility: SalonVisibilitySchema.optional(),
});

/**
 * 取消沙龙: reason 必填且 10-500 字 (主理人写给受邀者的详细说明)
 * 太短不严肃 (「不办了」); 太长像是写邮件, 应在沙龙内另外发公告
 */
export const SalonCancelSchema = z.object({
  reason: z.string().min(10).max(500),
});
