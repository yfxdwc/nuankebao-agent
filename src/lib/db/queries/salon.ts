// ============================================
// 沙龙 queries (v0.1.5 Phase 7)
// ============================================
// 边界 (主人 2026-09-18 拍):
//   1. 受邀者填「预计带约人数」, 主理人手动核对 (不做全链追踪)
//   2. 受邀者可为非 app 用户 (姓名 + 加密手机号)
//   3. 不建统一关系图谱; 沙龙内以 salon_invitation 树表达邀约关系
//   4. 会务 = invitation(role=staff); 手机号一律 *_encrypted + hash
//   5. 电话 / 留言 等敏感字段仅主理人 + 会务 + 本人可见
//
// 权限矩阵:
//   | 操作            | 主理人 | 会务 | 受邀者 |
//   |-----------------|-------|------|-------|
//   | 编辑沙龙         | ✅    | ❌   | ❌    |
//   | 取消/删除        | ✅    | ❌   | ❌    |
//   | 邀请他人         | ✅    | ✅   | ❌ (走 salon_guest) |
//   | 分配带约任务     | ✅    | ✅   | ❌    |
//   | 看受邀名单       | ✅    | ✅   | 按 visibility_settings.attendeeList |
//   | RSVP/填带约人数  | —     | —    | ✅    |
//   | 加二级客人       | ✅    | ✅   | ✅ (只能加自己的) |
//   | 发公告           | ✅    | ✅   | ❌    |
//   | 留言/提问        | ✅    | ✅   | ✅    |
// ============================================

import { db } from "@/lib/db";
import {
  salon,
  salonInvitation,
  salonGuest,
  salonQuota,
  salonActivity,
  salonAttachment,
  user,
  type Salon,
  type SalonAgendaItem,
  type SalonFormField,
  type SalonVisibilitySettings,
} from "@/lib/db/schema";
import {
  and,
  asc,
  desc,
  eq,
  inArray,
  isNull,
  ne,
  or,
  sql,
  type SQL,
} from "drizzle-orm";
import {
  encryptField,
  decryptField,
  hashForLookup,
} from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";

// ============================================
// 类型
// ============================================

export type SalonStatus =
  | "draft"
  | "published"
  | "registration_closed"
  | "ongoing"
  | "finished"
  | "cancelled";

export type SalonInvitationStatus =
  | "pending"
  | "accepted"
  | "tentative"
  | "declined"
  | "waitlist"
  | "attended"
  | "absent"
  | "cancelled";

export type SalonRole = "organizer" | "staff" | "attendee";

export type SalonGuestStatus =
  | "pending"
  | "accepted"
  | "declined"
  | "attended"
  | "absent"
  | "cancelled";

export interface SalonCounts {
  /** 有效邀请数 (不含已撤销) */
  invitedTotal: number;
  accepted: number;
  declined: number;
  tentative: number;
  pending: number;
  waitlist: number;
  attended: number;
  absent: number;
  /** 会务人数 (role=staff, 不含已撤销) */
  staffCount: number;
  /** 受邀者自报预计带约总人数 */
  expectedGuests: number;
  /** 已登记二级客人数 (不含已取消/已婉拒) */
  guestRegistered: number;
  /** 实到二级客人数 */
  guestAttended: number;
  /** 总名额 (null = 不限) */
  capacityTotal: number | null;
  /** 剩余名额 (capacityTotal - accepted - attended; null = 不限) */
  capacityRemaining: number | null;
}

export interface SalonViewerContext {
  isOrganizer: boolean;
  isStaff: boolean;
  /** 我的邀请状态 (我=主理人 时为 null) */
  myInvitationId: string | null;
  myStatus: SalonInvitationStatus | null;
  myRole: SalonRole | null;
  myExpectedGuestCount: number | null;
  /** 我的带约任务 (active) */
  myQuotaValue: number | null;
  myQuotaDeadlineAt: Date | null;
}

export interface SalonView {
  id: string;
  title: string;
  subtitle: string | null;
  description: string | null;
  coverUrl: string | null;
  themeTags: string[];
  organizerUserId: string;
  organizerName: string | null;
  organizerAvatar: string | null;
  status: SalonStatus;
  startAt: Date;
  endAt: Date | null;
  registrationDeadlineAt: Date | null;
  timezone: string;

  locationName: string | null;
  address: string | null;
  floorRoom: string | null;
  lat: string | null;
  lng: string | null;
  parkingInfo: string | null;

  transportPublic: string | null;
  transportDriving: string | null;
  transportPickup: string | null;

  cateringMealType: string | null;
  cateringCuisine: string | null;
  cateringDietary: string | null;
  cateringTime: string | null;
  cateringPayer: string | null;

  lodgingHotelName: string | null;
  lodgingRoomType: string | null;
  lodgingPriceCents: number | null;
  lodgingContactName: string | null;
  /** 订房联系人电话 (仅主理人/会务可见; 其余 null) */
  lodgingContactPhone: string | null;
  lodgingDeadlineAt: Date | null;
  lodgingNote: string | null;

  dressCode: string | null;
  feeType: string;
  feeAmountCents: number | null;
  feeNote: string | null;

  capacityTotal: number | null;
  capacityReserved: number;

  agenda: SalonAgendaItem[];
  registrationFormSchema: SalonFormField[];
  visibilitySettings: SalonVisibilitySettings;

  createdAt: Date;
  updatedAt: Date;

  viewer: SalonViewerContext;
  counts: SalonCounts;
}

export interface SalonInvitationView {
  id: string;
  salonId: string;
  inviteeUserId: string | null;
  inviteeName: string;
  /** 手机号 (仅主理人/会务/本人可见; 其余 null) */
  inviteePhone: string | null;
  roleInSalon: SalonRole;
  staffRole: string | null;
  invitedByUserId: string | null;
  status: SalonInvitationStatus;
  expectedGuestCount: number;
  actualGuestCount: number | null;
  respondedAt: Date | null;
  notes: string | null;
  registrationData: Record<string, unknown> | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface SalonGuestView {
  id: string;
  salonId: string;
  broughtByUserId: string;
  broughtByName: string | null;
  name: string;
  /** 手机号 (仅主理人/会务/带来的人本人可见) */
  phone: string | null;
  relation: string | null;
  status: SalonGuestStatus;
  actualAttended: boolean;
  notes: string | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface SalonQuotaView {
  id: string;
  salonId: string;
  assignedToUserId: string;
  assignedToName: string | null;
  quotaValue: number;
  deadlineAt: Date | null;
  note: string | null;
  isActive: boolean;
  createdByUserId: string;
  createdAt: Date;
  updatedAt: Date;
  /** 该人已自报的预计带约人数 (invitation.expected_guest_count) */
  expectedGuestCount: number;
  /** 该人已登记二级客人 (非取消/婉拒) */
  guestCount: number;
  /** 已完成数 = max(自报数, 已登记数), 供主理人粗看 (可能重叠, 不做精确去重) */
  progress: number;
}

export interface SalonActivityView {
  id: string;
  salonId: string;
  authorUserId: string;
  authorName: string | null;
  authorAvatar: string | null;
  type: "system" | "announcement" | "question" | "comment";
  content: string;
  metadata: Record<string, unknown> | null;
  visibility: "all" | "staff" | "organizer";
  createdAt: Date;
}

export interface SalonAttachmentView {
  id: string;
  salonId: string;
  name: string;
  fileUrl: string;
  fileType: string;
  visibility: "all" | "staff" | "organizer";
  uploadedByUserId: string | null;
  createdAt: Date;
}

export interface SalonAggregates extends SalonCounts {
  /** active 带约任务数 */
  quotaAssignees: number;
  /** active 带约任务要求的总人数 */
  quotaTotal: number;
  /** 有 active 任务的人自报预计总人数 */
  quotaExpectedTotal: number;
  /** 有 active 任务的人已登记二级客人总数 */
  quotaGuestTotal: number;
}

// ============================================
// 内部工具
// ============================================

function toBigIntOrNull(v: string | number | bigint | null | undefined): bigint | null {
  if (v == null) return null;
  return typeof v === "bigint" ? v : BigInt(v);
}

function emptyCounts(): SalonCounts {
  return {
    invitedTotal: 0,
    accepted: 0,
    declined: 0,
    tentative: 0,
    pending: 0,
    waitlist: 0,
    attended: 0,
    absent: 0,
    staffCount: 0,
    expectedGuests: 0,
    guestRegistered: 0,
    guestAttended: 0,
    capacityTotal: null,
    capacityRemaining: null,
  };
}

function finalizeCounts(counts: SalonCounts, capacityTotal: number | null): SalonCounts {
  counts.invitedTotal =
    counts.accepted +
    counts.declined +
    counts.tentative +
    counts.pending +
    counts.waitlist +
    counts.attended +
    counts.absent;
  counts.capacityTotal = capacityTotal;
  counts.capacityRemaining =
    capacityTotal == null
      ? null
      : Math.max(0, capacityTotal - counts.accepted - counts.attended);
  return counts;
}

/** 查 user 手机号 hash (无需解密; user.phone_hash 已存) */
async function getUserPhoneHash(userId: bigint): Promise<string | null> {
  const [u] = await db
    .select({ phoneHash: user.phoneHash })
    .from(user)
    .where(eq(user.id, userId))
    .limit(1);
  return u?.phoneHash ?? null;
}

/**
 * 找「我」在某沙龙的邀请:
 *   1. invitee_user_id = 我
 *   2. 兜底: 我的手机号 hash 匹配 (老邀请在建 app 账号前创建)
 * 命中兜底时顺手把 invitee_user_id 补上 (幂等)
 */
async function findMyInvitation(salonId: bigint, userId: bigint) {
  const [direct] = await db
    .select()
    .from(salonInvitation)
    .where(
      and(
        eq(salonInvitation.salonId, salonId),
        eq(salonInvitation.inviteeUserId, userId)
      )
    )
    .limit(1);
  if (direct) return direct;

  const phoneHash = await getUserPhoneHash(userId);
  if (!phoneHash) return null;

  const [byPhone] = await db
    .select()
    .from(salonInvitation)
    .where(
      and(
        eq(salonInvitation.salonId, salonId),
        eq(salonInvitation.inviteePhoneHash, phoneHash)
      )
    )
    .limit(1);
  if (!byPhone) return null;

  if (byPhone.inviteeUserId == null) {
    await db
      .update(salonInvitation)
      .set({ inviteeUserId: userId, updatedAt: new Date() })
      .where(eq(salonInvitation.id, byPhone.id));
  }
  return byPhone;
}

interface SalonAccess {
  salon: Salon;
  isOrganizer: boolean;
  isStaff: boolean;
  myInvitation: Awaited<ReturnType<typeof findMyInvitation>>;
  /** 可见性判断后: 是否能看这个沙龙 */
  canView: boolean;
}

/** 加载沙龙 + 我的权限 (不可见 / 不存在 → null) */
async function loadAccess(salonId: bigint, userId: bigint): Promise<SalonAccess | null> {
  const [row] = await db
    .select()
    .from(salon)
    .where(and(eq(salon.id, salonId), isNull(salon.deletedAt)))
    .limit(1);
  if (!row) return null;

  const isOrganizer = row.organizerUserId === userId;
  const myInvitation = isOrganizer ? null : await findMyInvitation(salonId, userId);
  const isStaff = myInvitation?.roleInSalon === "staff";

  // 草稿仅主理人可见
  const canView = isOrganizer || (myInvitation != null && row.status !== "draft");
  if (!canView) return null;

  return { salon: row, isOrganizer, isStaff, myInvitation, canView };
}

function toSalonView(
  row: Salon,
  opts: {
    organizerName?: string | null;
    organizerAvatar?: string | null;
    isOrganizer: boolean;
    isStaff: boolean;
    myInvitation?: {
      id: bigint;
      status: SalonInvitationStatus;
      roleInSalon: SalonRole;
      expectedGuestCount: number;
    } | null;
    myQuota?: { quotaValue: number; deadlineAt: Date | null } | null;
    counts: SalonCounts;
  }
): SalonView {
  const canSeeContact = opts.isOrganizer || opts.isStaff;
  return {
    id: row.id.toString(),
    title: row.title,
    subtitle: row.subtitle,
    description: row.description,
    coverUrl: row.coverUrl,
    themeTags: row.themeTags ?? [],
    organizerUserId: row.organizerUserId.toString(),
    organizerName: opts.organizerName ?? null,
    organizerAvatar: opts.organizerAvatar ?? null,
    status: row.status as SalonStatus,
    startAt: row.startAt,
    endAt: row.endAt,
    registrationDeadlineAt: row.registrationDeadlineAt,
    timezone: row.timezone,

    locationName: row.locationName,
    address: row.address,
    floorRoom: row.floorRoom,
    lat: row.lat,
    lng: row.lng,
    parkingInfo: row.parkingInfo,

    transportPublic: row.transportPublic,
    transportDriving: row.transportDriving,
    transportPickup: row.transportPickup,

    cateringMealType: row.cateringMealType,
    cateringCuisine: row.cateringCuisine,
    cateringDietary: row.cateringDietary,
    cateringTime: row.cateringTime,
    cateringPayer: row.cateringPayer,

    lodgingHotelName: row.lodgingHotelName,
    lodgingRoomType: row.lodgingRoomType,
    lodgingPriceCents: row.lodgingPriceCents,
    lodgingContactName: row.lodgingContactName,
    lodgingContactPhone:
      canSeeContact && row.lodgingContactPhoneEncrypted
        ? decryptField(row.lodgingContactPhoneEncrypted)
        : null,
    lodgingDeadlineAt: row.lodgingDeadlineAt,
    lodgingNote: row.lodgingNote,

    dressCode: row.dressCode,
    feeType: row.feeType,
    feeAmountCents: row.feeAmountCents,
    feeNote: row.feeNote,

    capacityTotal: row.capacityTotal,
    capacityReserved: row.capacityReserved,

    agenda: row.agenda ?? [],
    registrationFormSchema: row.registrationFormSchema ?? [],
    visibilitySettings:
      row.visibilitySettings ?? { attendeeList: "all", staffContact: "all" },

    createdAt: row.createdAt,
    updatedAt: row.updatedAt,

    viewer: {
      isOrganizer: opts.isOrganizer,
      isStaff: opts.isStaff,
      myInvitationId: opts.myInvitation ? opts.myInvitation.id.toString() : null,
      myStatus: opts.myInvitation?.status ?? null,
      myRole: opts.myInvitation?.roleInSalon ?? (opts.isOrganizer ? "organizer" : null),
      myExpectedGuestCount: opts.myInvitation?.expectedGuestCount ?? null,
      myQuotaValue: opts.myQuota?.quotaValue ?? null,
      myQuotaDeadlineAt: opts.myQuota?.deadlineAt ?? null,
    },
    counts: opts.counts,
  };
}

function toInvitationView(
  row: typeof salonInvitation.$inferSelect,
  opts: { includePhone: boolean; includePrivate?: boolean }
): SalonInvitationView {
  const includePrivate = opts.includePrivate ?? true;
  return {
    id: row.id.toString(),
    salonId: row.salonId.toString(),
    inviteeUserId: row.inviteeUserId?.toString() ?? null,
    inviteeName: row.inviteeName,
    inviteePhone: opts.includePhone ? decryptField(row.inviteePhoneEncrypted) : null,
    roleInSalon: row.roleInSalon as SalonRole,
    staffRole: row.staffRole,
    invitedByUserId: row.invitedByUserId?.toString() ?? null,
    status: row.status as SalonInvitationStatus,
    expectedGuestCount: row.expectedGuestCount,
    actualGuestCount: row.actualGuestCount,
    respondedAt: row.respondedAt,
    notes: includePrivate && row.notesEncrypted ? decryptField(row.notesEncrypted) : null,
    registrationData: includePrivate ? (row.registrationData ?? null) : null,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

function toGuestView(
  row: typeof salonGuest.$inferSelect,
  opts: { includePhone: boolean; broughtByName?: string | null }
): SalonGuestView {
  return {
    id: row.id.toString(),
    salonId: row.salonId.toString(),
    broughtByUserId: row.broughtByUserId.toString(),
    broughtByName: opts.broughtByName ?? null,
    name: row.name,
    phone: opts.includePhone ? decryptField(row.phoneEncrypted) : null,
    relation: row.relation,
    status: row.status as SalonGuestStatus,
    actualAttended: row.actualAttended,
    notes: row.notesEncrypted ? decryptField(row.notesEncrypted) : null,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

// ============================================
// 统计 (批量, 列表/详情共用)
// ============================================

async function countsForSalons(salonIds: bigint[]): Promise<Map<string, SalonCounts>> {
  const map = new Map<string, SalonCounts>();
  if (salonIds.length === 0) return map;
  for (const id of salonIds) map.set(id.toString(), emptyCounts());

  // 邀请 (按状态 + 角色分组)
  const invRows = await db
    .select({
      salonId: salonInvitation.salonId,
      status: salonInvitation.status,
      role: salonInvitation.roleInSalon,
      cnt: sql<number>`count(*)::int`,
      expected: sql<number>`coalesce(sum(${salonInvitation.expectedGuestCount}), 0)::int`,
    })
    .from(salonInvitation)
    .where(inArray(salonInvitation.salonId, salonIds))
    .groupBy(salonInvitation.salonId, salonInvitation.status, salonInvitation.roleInSalon);

  for (const r of invRows) {
    const c = map.get(r.salonId.toString());
    if (!c) continue;
    if (r.role === "staff") {
      if (r.status !== "cancelled") c.staffCount += r.cnt;
      continue;
    }
    switch (r.status) {
      case "accepted":
        c.accepted += r.cnt;
        break;
      case "declined":
        c.declined += r.cnt;
        break;
      case "tentative":
        c.tentative += r.cnt;
        break;
      case "pending":
        c.pending += r.cnt;
        break;
      case "waitlist":
        c.waitlist += r.cnt;
        break;
      case "attended":
        c.attended += r.cnt;
        break;
      case "absent":
        c.absent += r.cnt;
        break;
      case "cancelled":
        break;
    }
    c.expectedGuests += r.expected;
  }

  // 二级客人
  const guestRows = await db
    .select({
      salonId: salonGuest.salonId,
      status: salonGuest.status,
      cnt: sql<number>`count(*)::int`,
    })
    .from(salonGuest)
    .where(inArray(salonGuest.salonId, salonIds))
    .groupBy(salonGuest.salonId, salonGuest.status);

  for (const r of guestRows) {
    const c = map.get(r.salonId.toString());
    if (!c) continue;
    if (r.status === "cancelled" || r.status === "declined") continue;
    c.guestRegistered += r.cnt;
    if (r.status === "attended") c.guestAttended += r.cnt;
  }

  return map;
}

async function organizerInfoFor(
  rows: { organizerUserId: bigint }[]
): Promise<Map<string, { name: string | null; avatar: string | null }>> {
  const ids = Array.from(new Set(rows.map((r) => r.organizerUserId.toString())));
  if (ids.length === 0) return new Map();
  const users = await db
    .select({ id: user.id, name: user.name, avatarUrl: user.avatarUrl })
    .from(user)
    .where(inArray(user.id, ids.map((i) => BigInt(i))));
  const m = new Map<string, { name: string | null; avatar: string | null }>();
  for (const u of users) {
    m.set(u.id.toString(), { name: u.name, avatar: u.avatarUrl });
  }
  return m;
}

/** 我的 active 带约任务 (批量: 只在详情用, 列表不做) */
async function myQuotaFor(salonId: bigint, userId: bigint) {
  const [q] = await db
    .select()
    .from(salonQuota)
    .where(
      and(
        eq(salonQuota.salonId, salonId),
        eq(salonQuota.assignedToUserId, userId),
        eq(salonQuota.isActive, true)
      )
    )
    .limit(1);
  return q ?? null;
}

// ============================================
// 创建 / 编辑 / 列表 / 详情
// ============================================

export interface SalonWritableFields {
  title?: string;
  subtitle?: string | null;
  description?: string | null;
  coverUrl?: string | null;
  themeTags?: string[];
  status?: SalonStatus;
  startAt?: string; // ISO
  endAt?: string | null;
  registrationDeadlineAt?: string | null;
  timezone?: string;
  locationName?: string | null;
  address?: string | null;
  floorRoom?: string | null;
  lat?: string | null;
  lng?: string | null;
  parkingInfo?: string | null;
  transportPublic?: string | null;
  transportDriving?: string | null;
  transportPickup?: string | null;
  cateringMealType?: string | null;
  cateringCuisine?: string | null;
  cateringDietary?: string | null;
  cateringTime?: string | null;
  cateringPayer?: string | null;
  lodgingHotelName?: string | null;
  lodgingRoomType?: string | null;
  lodgingPriceCents?: number | null;
  lodgingContactName?: string | null;
  lodgingContactPhone?: string | null;
  lodgingDeadlineAt?: string | null;
  lodgingNote?: string | null;
  dressCode?: string | null;
  feeType?: string;
  feeAmountCents?: number | null;
  feeNote?: string | null;
  capacityTotal?: number | null;
  capacityReserved?: number;
  agenda?: SalonAgendaItem[];
  registrationFormSchema?: SalonFormField[];
  visibilitySettings?: SalonVisibilitySettings;
}

export interface SalonCreateExtras {
  /** 会务人员 (role=staff) */
  staff?: { name: string; phone: string; staffRole?: string | null }[];
  /** 直接邀请的受邀者 */
  invitees?: { name: string; phone: string; expectedGuestCount?: number }[];
}

function buildSalonColumnValues(input: SalonWritableFields): Partial<typeof salon.$inferInsert> {
  const v: Partial<typeof salon.$inferInsert> = {};
  if (input.title !== undefined) v.title = input.title;
  if (input.subtitle !== undefined) v.subtitle = input.subtitle;
  if (input.description !== undefined) v.description = input.description;
  if (input.coverUrl !== undefined) v.coverUrl = input.coverUrl;
  if (input.themeTags !== undefined) v.themeTags = input.themeTags;
  if (input.status !== undefined) v.status = input.status;
  if (input.startAt !== undefined) v.startAt = new Date(input.startAt);
  if (input.endAt !== undefined) v.endAt = input.endAt ? new Date(input.endAt) : null;
  if (input.registrationDeadlineAt !== undefined) {
    v.registrationDeadlineAt = input.registrationDeadlineAt
      ? new Date(input.registrationDeadlineAt)
      : null;
  }
  if (input.timezone !== undefined) v.timezone = input.timezone;
  if (input.locationName !== undefined) v.locationName = input.locationName;
  if (input.address !== undefined) v.address = input.address;
  if (input.floorRoom !== undefined) v.floorRoom = input.floorRoom;
  if (input.lat !== undefined) v.lat = input.lat;
  if (input.lng !== undefined) v.lng = input.lng;
  if (input.parkingInfo !== undefined) v.parkingInfo = input.parkingInfo;
  if (input.transportPublic !== undefined) v.transportPublic = input.transportPublic;
  if (input.transportDriving !== undefined) v.transportDriving = input.transportDriving;
  if (input.transportPickup !== undefined) v.transportPickup = input.transportPickup;
  if (input.cateringMealType !== undefined) v.cateringMealType = input.cateringMealType;
  if (input.cateringCuisine !== undefined) v.cateringCuisine = input.cateringCuisine;
  if (input.cateringDietary !== undefined) v.cateringDietary = input.cateringDietary;
  if (input.cateringTime !== undefined) v.cateringTime = input.cateringTime;
  if (input.cateringPayer !== undefined) v.cateringPayer = input.cateringPayer;
  if (input.lodgingHotelName !== undefined) v.lodgingHotelName = input.lodgingHotelName;
  if (input.lodgingRoomType !== undefined) v.lodgingRoomType = input.lodgingRoomType;
  if (input.lodgingPriceCents !== undefined) v.lodgingPriceCents = input.lodgingPriceCents;
  if (input.lodgingContactName !== undefined) v.lodgingContactName = input.lodgingContactName;
  if (input.lodgingContactPhone !== undefined) {
    v.lodgingContactPhoneEncrypted = input.lodgingContactPhone
      ? encryptField(input.lodgingContactPhone)
      : null;
  }
  if (input.lodgingDeadlineAt !== undefined) {
    v.lodgingDeadlineAt = input.lodgingDeadlineAt ? new Date(input.lodgingDeadlineAt) : null;
  }
  if (input.lodgingNote !== undefined) v.lodgingNote = input.lodgingNote;
  if (input.dressCode !== undefined) v.dressCode = input.dressCode;
  if (input.feeType !== undefined) v.feeType = input.feeType;
  if (input.feeAmountCents !== undefined) v.feeAmountCents = input.feeAmountCents;
  if (input.feeNote !== undefined) v.feeNote = input.feeNote;
  if (input.capacityTotal !== undefined) v.capacityTotal = input.capacityTotal;
  if (input.capacityReserved !== undefined) v.capacityReserved = input.capacityReserved;
  if (input.agenda !== undefined) v.agenda = input.agenda;
  if (input.registrationFormSchema !== undefined) {
    v.registrationFormSchema = input.registrationFormSchema;
  }
  if (input.visibilitySettings !== undefined) {
    v.visibilitySettings = input.visibilitySettings;
  }
  return v;
}

/** 解析手机号 → app 用户 id (无则 null); 用于邀请非 app 用户
 *  ⚠ 事务内务必传 tx: 连接池 dev 下 max=1, 事务中再用全局 db 会死锁 */
async function resolveUserIdByPhone(
  phone: string,
  tx: typeof db = db
): Promise<bigint | null> {
  const phoneHash = hashForLookup(phone);
  const [u] = await tx
    .select({ id: user.id })
    .from(user)
    .where(and(eq(user.phoneHash, phoneHash), eq(user.isActive, true)))
    .limit(1);
  return u?.id ?? null;
}

export async function createSalon(
  input: SalonWritableFields & { title: string; startAt: string },
  extras: SalonCreateExtras,
  ctx: AuditContext,
  userId: bigint
): Promise<SalonView> {
  const values: typeof salon.$inferInsert = {
    ...(buildSalonColumnValues(input) as typeof salon.$inferInsert),
    title: input.title,
    startAt: new Date(input.startAt),
    organizerUserId: userId,
    createdBy: userId,
  };

  const created = await withAuditContext(ctx, async (tx) => {
    const [row] = await tx.insert(salon).values(values).returning();

    // 会务人员
    for (const s of extras.staff ?? []) {
      const phoneHash = hashForLookup(s.phone);
      const inviteeUserId = await resolveUserIdByPhone(s.phone, tx);
      await tx
        .insert(salonInvitation)
        .values({
          salonId: row.id,
          inviteeUserId,
          inviteeName: s.name,
          inviteePhoneEncrypted: encryptField(s.phone),
          inviteePhoneHash: phoneHash,
          roleInSalon: "staff",
          staffRole: s.staffRole ?? null,
          invitedByUserId: userId,
          status: "pending",
        })
        .onConflictDoNothing();
    }

    // 受邀者
    for (const i of extras.invitees ?? []) {
      const phoneHash = hashForLookup(i.phone);
      const inviteeUserId = await resolveUserIdByPhone(i.phone, tx);
      await tx
        .insert(salonInvitation)
        .values({
          salonId: row.id,
          inviteeUserId,
          inviteeName: i.name,
          inviteePhoneEncrypted: encryptField(i.phone),
          inviteePhoneHash: phoneHash,
          roleInSalon: "attendee",
          invitedByUserId: userId,
          status: "pending",
          expectedGuestCount: i.expectedGuestCount ?? 0,
        })
        .onConflictDoNothing();
    }

    await tx.insert(salonActivity).values({
      salonId: row.id,
      authorUserId: userId,
      type: "system",
      content: "沙龙已创建",
      visibility: "all",
      metadata: { event: "salon_created" },
    });

    return row;
  });

  return (await getSalonDetail(created.id, userId))!;
}

/**
 * Tab 计数: 我主理的 / 我受邀的 各有多少「进行中」(未结束 / 未取消) 的沙龙
 *
 * 口径与 listSalons(includeFinished=false) 一致: status NOT IN ('finished','cancelled')
 *  - 受邀侧: 沿用 listSalons 的「invitee_user_id 命中 OR 手机号 hash 命中」判定
 *  - 主理侧: salon.organizer_user_id = userId
 *
 * 用途: GET /api/salons/counts → tab 角标
 */
export async function getSalonActiveCounts(
  userId: bigint
): Promise<{ organizing: number; invited: number }> {
  const myPhoneHash = await getUserPhoneHash(userId);
  const invitedExists = myPhoneHash
    ? sql`EXISTS (
        SELECT 1 FROM salon_invitation si
        WHERE si.salon_id = ${salon.id}
          AND si.status <> 'cancelled'
          AND (si.invitee_user_id = ${userId} OR si.invitee_phone_hash = ${myPhoneHash})
      )`
    : sql`EXISTS (
        SELECT 1 FROM salon_invitation si
        WHERE si.salon_id = ${salon.id}
          AND si.status <> 'cancelled'
          AND si.invitee_user_id = ${userId}
      )`;
  const activeFilter = sql`${salon.status} NOT IN ('finished', 'cancelled')`;

  const [[organizingRow], [invitedRow]] = await Promise.all([
    db
      .select({ count: sql<number>`count(*)::int` })
      .from(salon)
      .where(
        and(
          isNull(salon.deletedAt),
          eq(salon.organizerUserId, userId),
          activeFilter,
        )
      ),
    db
      .select({ count: sql<number>`count(*)::int` })
      .from(salon)
      .where(and(isNull(salon.deletedAt), invitedExists, activeFilter)),
  ]);
  return { organizing: organizingRow.count, invited: invitedRow.count };
}

export interface ListSalonsOptions {
  userId: bigint;
  /** organizing = 我主理的; invited = 我受邀的; all = 两者并集 */
  role?: "organizing" | "invited" | "all";
  status?: SalonStatus;
  /** 含已结束/已取消 (默认 true 由调用方给) */
  includeFinished?: boolean;
  limit?: number;
  offset?: number;
}

export async function listSalons(
  options: ListSalonsOptions
): Promise<{ items: SalonView[]; total: number }> {
  const {
    userId,
    role = "all",
    status,
    includeFinished = true,
    limit = 50,
    offset = 0,
  } = options;

  const conds: SQL[] = [isNull(salon.deletedAt)];

  if (!includeFinished) {
    conds.push(sql`${salon.status} NOT IN ('finished', 'cancelled')`);
  }
  if (status) {
    conds.push(eq(salon.status, status));
  }

  // 受邀判定: invitee_user_id 命中, 或 (老邀请未绑账号时) 手机号 hash 命中
  const myPhoneHash = await getUserPhoneHash(userId);
  const invitedExists = myPhoneHash
    ? sql`EXISTS (
        SELECT 1 FROM salon_invitation si
        WHERE si.salon_id = ${salon.id}
          AND si.status <> 'cancelled'
          AND (si.invitee_user_id = ${userId} OR si.invitee_phone_hash = ${myPhoneHash})
      )`
    : sql`EXISTS (
        SELECT 1 FROM salon_invitation si
        WHERE si.salon_id = ${salon.id}
          AND si.status <> 'cancelled'
          AND si.invitee_user_id = ${userId}
      )`;

  if (role === "organizing") {
    conds.push(eq(salon.organizerUserId, userId));
  } else if (role === "invited") {
    conds.push(invitedExists);
  } else {
    // all: 主理 OR 受邀
    conds.push(sql`(${salon.organizerUserId} = ${userId} OR ${invitedExists})`);
  }

  const whereClause = and(...conds);

  const [rows, [{ count }]] = await Promise.all([
    db
      .select()
      .from(salon)
      .where(whereClause)
      .orderBy(desc(salon.startAt))
      .limit(limit)
      .offset(offset),
    db.select({ count: sql<number>`count(*)::int` }).from(salon).where(whereClause),
  ]);

  const salonIds = rows.map((r) => r.id);
  const [countsMap, organizerMap] = await Promise.all([
    countsForSalons(salonIds),
    organizerInfoFor(rows),
  ]);

  // 批量取「我的邀请」+「我的带约任务」, 避免列表 N+1
  const myInvMap = new Map<
    string,
    { id: bigint; status: SalonInvitationStatus; roleInSalon: SalonRole; expectedGuestCount: number }
  >();
  const myQuotaMap = new Map<string, { quotaValue: number; deadlineAt: Date | null }>();

  if (salonIds.length > 0) {
    const invRows = await db
      .select()
      .from(salonInvitation)
      .where(
        and(
          inArray(salonInvitation.salonId, salonIds),
          or(
            eq(salonInvitation.inviteeUserId, userId),
            myPhoneHash ? eq(salonInvitation.inviteePhoneHash, myPhoneHash) : sql`false`
          ),
          ne(salonInvitation.status, "cancelled")
        )
      );
    for (const inv of invRows) {
      myInvMap.set(inv.salonId.toString(), {
        id: inv.id,
        status: inv.status as SalonInvitationStatus,
        roleInSalon: inv.roleInSalon as SalonRole,
        expectedGuestCount: inv.expectedGuestCount,
      });
    }

    const quotaRows = await db
      .select()
      .from(salonQuota)
      .where(
        and(
          inArray(salonQuota.salonId, salonIds),
          eq(salonQuota.assignedToUserId, userId),
          eq(salonQuota.isActive, true)
        )
      );
    for (const q of quotaRows) {
      myQuotaMap.set(q.salonId.toString(), {
        quotaValue: q.quotaValue,
        deadlineAt: q.deadlineAt,
      });
    }
  }

  const items: SalonView[] = [];
  for (const row of rows) {
    const isOrganizer = row.organizerUserId === userId;
    const myInv = isOrganizer ? null : (myInvMap.get(row.id.toString()) ?? null);
    const myQuota = isOrganizer ? null : (myQuotaMap.get(row.id.toString()) ?? null);

    const orgInfo = organizerMap.get(row.organizerUserId.toString());
    items.push(
      toSalonView(row, {
        organizerName: orgInfo?.name ?? null,
        organizerAvatar: orgInfo?.avatar ?? null,
        isOrganizer,
        isStaff: myInv?.roleInSalon === "staff",
        myInvitation: myInv,
        myQuota,
        counts: finalizeCounts(
          countsMap.get(row.id.toString()) ?? emptyCounts(),
          row.capacityTotal
        ),
      })
    );
  }

  return { items, total: count };
}

export async function getSalonDetail(
  salonId: bigint,
  userId: bigint
): Promise<SalonView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;
  const { salon: row, isOrganizer, isStaff, myInvitation } = access;

  const [countsMap, orgInfo] = await Promise.all([
    countsForSalons([row.id]),
    organizerInfoFor([row]),
  ]);

  const myQuota = isOrganizer ? null : await myQuotaFor(row.id, userId);

  return toSalonView(row, {
    organizerName: orgInfo.get(row.organizerUserId.toString())?.name ?? null,
    organizerAvatar: orgInfo.get(row.organizerUserId.toString())?.avatar ?? null,
    isOrganizer,
    isStaff,
    myInvitation: myInvitation
      ? {
          id: myInvitation.id,
          status: myInvitation.status as SalonInvitationStatus,
          roleInSalon: myInvitation.roleInSalon as SalonRole,
          expectedGuestCount: myInvitation.expectedGuestCount,
        }
      : null,
    myQuota: myQuota ? { quotaValue: myQuota.quotaValue, deadlineAt: myQuota.deadlineAt } : null,
    counts: finalizeCounts(countsMap.get(row.id.toString()) ?? emptyCounts(), row.capacityTotal),
  });
}

export async function updateSalon(
  salonId: bigint,
  input: SalonWritableFields,
  ctx: AuditContext,
  userId: bigint
): Promise<SalonView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access || !access.isOrganizer) return null;

  const values = buildSalonColumnValues(input);
  values.updatedAt = new Date();

  await withAuditContext(ctx, async (tx) => {
    await tx.update(salon).set(values).where(eq(salon.id, salonId));
  });

  return getSalonDetail(salonId, userId);
}

/**
 * 取消沙龙 (status=cancelled + 系统动态; 不删数据)
 *
 * - 主理人才可取消
 * - reason: 详细说明 (必填, 10-500 字), 写到 salon_activity.content (受邀者可见)
 *   同时塞进 metadata.reason 方便前端结构化渲染 banner
 * - 已 cancelled 的沙龙再调: 幂等返回现状
 */
export async function cancelSalon(
  salonId: bigint,
  ctx: AuditContext,
  userId: bigint,
  reason: string
): Promise<SalonView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access || !access.isOrganizer) return null;

  await withAuditContext(ctx, async (tx) => {
    // 幂等: 已取消的沙龙不重复写动态
    const [cur] = await tx
      .select({ status: salon.status })
      .from(salon)
      .where(eq(salon.id, salonId))
      .limit(1);
    if (!cur) return;
    if (cur.status === "cancelled") return;

    await tx
      .update(salon)
      .set({ status: "cancelled", updatedAt: new Date() })
      .where(eq(salon.id, salonId));
    // 主理人取消 + 详细理由 → 落到 system 动态 (visibility=all, 受邀者都能看到)
    // content 既给活动流展示, 也便于未来全文检索
    await tx.insert(salonActivity).values({
      salonId,
      authorUserId: userId,
      type: "system",
      content: `沙龙已取消 — ${reason}`,
      visibility: "all",
      metadata: { event: "salon_cancelled", reason },
    });
  });

  return getSalonDetail(salonId, userId);
}

/** 软删除 (仅草稿可删) */
export async function softDeleteSalon(
  salonId: bigint,
  ctx: AuditContext,
  userId: bigint
): Promise<boolean> {
  const access = await loadAccess(salonId, userId);
  if (!access || !access.isOrganizer) return false;

  await withAuditContext(ctx, async (tx) => {
    await tx
      .update(salon)
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where(eq(salon.id, salonId));
  });
  return true;
}

// ============================================
// 邀请管理
// ============================================

export interface InvitationInput {
  name: string;
  phone: string;
  roleInSalon?: "attendee" | "staff";
  staffRole?: string | null;
  expectedGuestCount?: number;
}

export async function listInvitations(
  salonId: bigint,
  userId: bigint,
  opts: { includeCancelled?: boolean } = {}
): Promise<SalonInvitationView[] | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;

  const { isOrganizer, isStaff, myInvitation } = access;
  const canSeePhones = isOrganizer || isStaff;

  // 可见性: 名单可见性设置
  const vis = access.salon.visibilitySettings ?? {
    attendeeList: "all" as const,
    staffContact: "all" as const,
  };
  const listVisible =
    isOrganizer ||
    isStaff ||
    vis.attendeeList === "all" ||
    (vis.attendeeList === "staff" && myInvitation?.roleInSalon === "staff");
  if (!listVisible) return [];

  const conds: SQL[] = [eq(salonInvitation.salonId, salonId)];
  if (!opts.includeCancelled) {
    conds.push(ne(salonInvitation.status, "cancelled"));
  }

  const rows = await db
    .select()
    .from(salonInvitation)
    .where(and(...conds))
    .orderBy(asc(salonInvitation.roleInSalon), asc(salonInvitation.createdAt));

  return rows.map((r) => {
    const isSelf = myInvitation != null && myInvitation.id === r.id;
    return toInvitationView(r, {
      // 会务手机号: staffContact='staff' 时受邀者看不到
      includePhone:
        canSeePhones || isSelf || (r.roleInSalon === "staff" && vis.staffContact === "all"),
      // 留言/报名数据: 仅主理人/会务/本人
      includePrivate: canSeePhones || isSelf,
    });
  });
}

export async function createInvitation(
  salonId: bigint,
  input: InvitationInput,
  ctx: AuditContext,
  userId: bigint
): Promise<SalonInvitationView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access || (!access.isOrganizer && !access.isStaff)) return null;
  if (access.salon.status === "cancelled" || access.salon.status === "finished") return null;

  const phoneHash = hashForLookup(input.phone);
  const inviteeUserId = await resolveUserIdByPhone(input.phone);
  const role = input.roleInSalon ?? "attendee";

  const inserted = await withAuditContext(ctx, async (tx) => {
    const [row] = await tx
      .insert(salonInvitation)
      .values({
        salonId,
        inviteeUserId,
        inviteeName: input.name,
        inviteePhoneEncrypted: encryptField(input.phone),
        inviteePhoneHash: phoneHash,
        roleInSalon: role,
        staffRole: role === "staff" ? (input.staffRole ?? null) : null,
        invitedByUserId: userId,
        status: "pending",
        expectedGuestCount: input.expectedGuestCount ?? 0,
      })
      .onConflictDoNothing()
      .returning();

    if (row) {
      await tx.insert(salonActivity).values({
        salonId,
        authorUserId: userId,
        type: "system",
        content: role === "staff" ? `已添加会务: ${input.name}` : `已邀请: ${input.name}`,
        visibility: "staff",
        metadata: { event: "invitation_created", name: input.name, role },
      });
    }
    return row;
  });

  if (!inserted) return null; // 重复手机号 (onConflictDoNothing)
  return toInvitationView(inserted, { includePhone: true });
}

export async function updateInvitation(
  salonId: bigint,
  invitationId: bigint,
  input: {
    name?: string;
    status?: SalonInvitationStatus;
    staffRole?: string | null;
    actualGuestCount?: number | null;
    roleInSalon?: "attendee" | "staff";
  },
  ctx: AuditContext,
  userId: bigint
): Promise<SalonInvitationView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access || (!access.isOrganizer && !access.isStaff)) return null;

  const values: Partial<typeof salonInvitation.$inferInsert> = { updatedAt: new Date() };
  if (input.name !== undefined) values.inviteeName = input.name;
  if (input.status !== undefined) {
    values.status = input.status;
    values.respondedAt = new Date();
  }
  if (input.staffRole !== undefined) values.staffRole = input.staffRole;
  if (input.actualGuestCount !== undefined) values.actualGuestCount = input.actualGuestCount;
  if (input.roleInSalon !== undefined) values.roleInSalon = input.roleInSalon;

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(salonInvitation)
      .set(values)
      .where(and(eq(salonInvitation.id, invitationId), eq(salonInvitation.salonId, salonId)))
      .returning();
  });

  return row ? toInvitationView(row, { includePhone: true }) : null;
}

/** 移除邀请 (status=cancelled, 保留审计痕迹) */
export async function removeInvitation(
  salonId: bigint,
  invitationId: bigint,
  ctx: AuditContext,
  userId: bigint
): Promise<boolean> {
  const access = await loadAccess(salonId, userId);
  if (!access || (!access.isOrganizer && !access.isStaff)) return false;

  const result = await withAuditContext(ctx, async (tx) => {
    const rows = await tx
      .update(salonInvitation)
      .set({ status: "cancelled", updatedAt: new Date() })
      .where(and(eq(salonInvitation.id, invitationId), eq(salonInvitation.salonId, salonId)))
      .returning();
    return rows.length > 0;
  });
  return result;
}

// ============================================
// RSVP (受邀者回复)
// ============================================

export interface RsvpInput {
  status: "accepted" | "declined" | "tentative";
  expectedGuestCount?: number;
  notes?: string | null;
  registrationData?: Record<string, unknown> | null;
}

export async function rsvpSalon(
  salonId: bigint,
  userId: bigint,
  input: RsvpInput,
  ctx: AuditContext
): Promise<SalonInvitationView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;
  if (access.isOrganizer) return null; // 主理人无需 RSVP
  const inv = access.myInvitation;
  if (!inv) return null;
  if (inv.status === "cancelled") return null;

  const values: Partial<typeof salonInvitation.$inferInsert> = {
    status: input.status,
    respondedAt: new Date(),
    updatedAt: new Date(),
  };
  if (input.expectedGuestCount !== undefined) {
    values.expectedGuestCount = Math.max(0, input.expectedGuestCount);
  }
  if (input.notes !== undefined) {
    values.notesEncrypted = input.notes ? encryptField(input.notes) : null;
  }
  if (input.registrationData !== undefined) {
    values.registrationData = input.registrationData;
  }

  const [row] = await withAuditContext(ctx, async (tx) => {
    const updated = await tx
      .update(salonInvitation)
      .set(values)
      .where(eq(salonInvitation.id, inv.id))
      .returning();

    await tx.insert(salonActivity).values({
      salonId,
      authorUserId: userId,
      type: "system",
      content:
        input.status === "accepted"
          ? `${inv.inviteeName} 已接受邀请`
          : input.status === "declined"
            ? `${inv.inviteeName} 婉拒了邀请`
            : `${inv.inviteeName} 回复待定`,
      visibility: "all",
      metadata: { event: "rsvp", status: input.status, name: inv.inviteeName },
    });

    return updated;
  });

  return row ? toInvitationView(row, { includePhone: false }) : null;
}

// ============================================
// 带约任务
// ============================================

export async function listQuotas(
  salonId: bigint,
  userId: bigint
): Promise<SalonQuotaView[] | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;

  // 受邀者只看到自己的任务
  const conds: SQL[] = [eq(salonQuota.salonId, salonId)];
  if (!access.isOrganizer && !access.isStaff) {
    conds.push(eq(salonQuota.assignedToUserId, userId));
  }

  const rows = await db
    .select()
    .from(salonQuota)
    .where(and(...conds))
    .orderBy(desc(salonQuota.isActive), asc(salonQuota.createdAt));

  if (rows.length === 0) return [];

  const userIds = Array.from(new Set(rows.map((r) => r.assignedToUserId.toString())));
  const users = await db
    .select({ id: user.id, name: user.name })
    .from(user)
    .where(inArray(user.id, userIds.map((i) => BigInt(i))));
  const nameMap = new Map(users.map((u) => [u.id.toString(), u.name]));

  // 每个 assignee 的预计数 + 已登记数
  const invRows = await db
    .select({
      inviteeUserId: salonInvitation.inviteeUserId,
      expected: sql<number>`coalesce(${salonInvitation.expectedGuestCount}, 0)::int`,
    })
    .from(salonInvitation)
    .where(
      and(
        eq(salonInvitation.salonId, salonId),
        inArray(
          salonInvitation.inviteeUserId,
          userIds.map((i) => BigInt(i))
        )
      )
    );
  const expectedMap = new Map<string, number>();
  for (const r of invRows) {
    if (r.inviteeUserId == null) continue;
    const k = r.inviteeUserId.toString();
    expectedMap.set(k, (expectedMap.get(k) ?? 0) + r.expected);
  }

  const guestRows = await db
    .select({
      broughtByUserId: salonGuest.broughtByUserId,
      cnt: sql<number>`count(*)::int`,
    })
    .from(salonGuest)
    .where(
      and(
        eq(salonGuest.salonId, salonId),
        inArray(
          salonGuest.broughtByUserId,
          userIds.map((i) => BigInt(i))
        ),
        sql`${salonGuest.status} NOT IN ('cancelled', 'declined')`
      )
    )
    .groupBy(salonGuest.broughtByUserId);
  const guestMap = new Map<string, number>();
  for (const r of guestRows) {
    guestMap.set(r.broughtByUserId.toString(), r.cnt);
  }

  return rows.map((r) => {
    const k = r.assignedToUserId.toString();
    const expectedGuestCount = expectedMap.get(k) ?? 0;
    const guestCount = guestMap.get(k) ?? 0;
    return {
      id: r.id.toString(),
      salonId: r.salonId.toString(),
      assignedToUserId: k,
      assignedToName: nameMap.get(k) ?? null,
      quotaValue: r.quotaValue,
      deadlineAt: r.deadlineAt,
      note: r.note,
      isActive: r.isActive,
      createdByUserId: r.createdByUserId.toString(),
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      expectedGuestCount,
      guestCount,
      // 粗进度: max(自报, 已登记) — 两者可能重叠, 不做精确去重 (主人 2026-09-18 拍简单版)
      progress: Math.max(expectedGuestCount, guestCount),
    };
  });
}

/** 分配/调整带约任务 (同人同沙龙 active 任务唯一: 已存在则更新) */
export async function upsertQuota(
  salonId: bigint,
  input: {
    assignedToUserId: string;
    quotaValue: number;
    deadlineAt?: string | null;
    note?: string | null;
  },
  ctx: AuditContext,
  userId: bigint
): Promise<SalonQuotaView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access || (!access.isOrganizer && !access.isStaff)) return null;

  const assignedTo = BigInt(input.assignedToUserId);
  const values = {
    salonId,
    assignedToUserId: assignedTo,
    quotaValue: input.quotaValue,
    deadlineAt: input.deadlineAt ? new Date(input.deadlineAt) : null,
    note: input.note ?? null,
    isActive: true,
    createdByUserId: userId,
    updatedAt: new Date(),
  };

  await withAuditContext(ctx, async (tx) => {
    const [existing] = await tx
      .select()
      .from(salonQuota)
      .where(
        and(
          eq(salonQuota.salonId, salonId),
          eq(salonQuota.assignedToUserId, assignedTo),
          eq(salonQuota.isActive, true)
        )
      )
      .limit(1);

    if (existing) {
      await tx.update(salonQuota).set(values).where(eq(salonQuota.id, existing.id));
    } else {
      await tx.insert(salonQuota).values(values);
    }
  });

  const list = await listQuotas(salonId, userId);
  return list?.find((q) => q.assignedToUserId === input.assignedToUserId && q.isActive) ?? null;
}

/** 取消带约任务 */
export async function cancelQuota(
  salonId: bigint,
  quotaId: bigint,
  ctx: AuditContext,
  userId: bigint
): Promise<boolean> {
  const access = await loadAccess(salonId, userId);
  if (!access || (!access.isOrganizer && !access.isStaff)) return false;

  const result = await withAuditContext(ctx, async (tx) => {
    const rows = await tx
      .update(salonQuota)
      .set({ isActive: false, updatedAt: new Date() })
      .where(and(eq(salonQuota.id, quotaId), eq(salonQuota.salonId, salonId)))
      .returning();
    return rows.length > 0;
  });
  return result;
}

// ============================================
// 二级客人 (非 app 用户)
// ============================================

export interface GuestInput {
  name: string;
  phone: string;
  relation?: string | null;
  status?: SalonGuestStatus;
  notes?: string | null;
}

export async function listGuests(
  salonId: bigint,
  userId: bigint,
  opts: { mine?: boolean } = {}
): Promise<SalonGuestView[] | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;

  const canSeeAll = access.isOrganizer || access.isStaff;
  // 受邀者只能看自己带来的 (隐私); 主理人/会务看全部
  if (!canSeeAll && !opts.mine) {
    opts = { ...opts, mine: true };
  }

  const conds: SQL[] = [eq(salonGuest.salonId, salonId)];
  if (opts.mine || !canSeeAll) {
    conds.push(eq(salonGuest.broughtByUserId, userId));
  }

  const rows = await db
    .select()
    .from(salonGuest)
    .where(and(...conds))
    .orderBy(desc(salonGuest.createdAt));

  const bringerIds = Array.from(new Set(rows.map((r) => r.broughtByUserId.toString())));
  const names = bringerIds.length
    ? await db
        .select({ id: user.id, name: user.name })
        .from(user)
        .where(inArray(user.id, bringerIds.map((i) => BigInt(i))))
    : [];
  const nameMap = new Map(names.map((u) => [u.id.toString(), u.name]));

  return rows.map((r) =>
    toGuestView(r, {
      includePhone:
        canSeeAll || r.broughtByUserId === userId,
      broughtByName: nameMap.get(r.broughtByUserId.toString()) ?? null,
    })
  );
}

export async function createGuest(
  salonId: bigint,
  input: GuestInput,
  ctx: AuditContext,
  userId: bigint
): Promise<SalonGuestView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;
  if (access.salon.status === "cancelled") return null;

  const phoneHash = hashForLookup(input.phone);
  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .insert(salonGuest)
      .values({
        salonId,
        broughtByUserId: userId,
        name: input.name,
        phoneEncrypted: encryptField(input.phone),
        phoneHash,
        relation: input.relation ?? null,
        status: input.status ?? "pending",
        notesEncrypted: input.notes ? encryptField(input.notes) : null,
        createdBy: userId,
      })
      .onConflictDoNothing()
      .returning();
  });

  if (!row) return null; // 重复手机号
  const [me] = await db.select({ name: user.name }).from(user).where(eq(user.id, userId)).limit(1);
  return toGuestView(row, { includePhone: true, broughtByName: me?.name ?? null });
}

export async function updateGuest(
  salonId: bigint,
  guestId: bigint,
  input: {
    name?: string;
    relation?: string | null;
    status?: SalonGuestStatus;
    actualAttended?: boolean;
    notes?: string | null;
  },
  ctx: AuditContext,
  userId: bigint
): Promise<SalonGuestView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;

  const [target] = await db
    .select()
    .from(salonGuest)
    .where(and(eq(salonGuest.id, guestId), eq(salonGuest.salonId, salonId)))
    .limit(1);
  if (!target) return null;

  const canEdit =
    access.isOrganizer || access.isStaff || target.broughtByUserId === userId;
  if (!canEdit) return null;

  const values: Partial<typeof salonGuest.$inferInsert> = { updatedAt: new Date() };
  if (input.name !== undefined) values.name = input.name;
  if (input.relation !== undefined) values.relation = input.relation;
  if (input.status !== undefined) values.status = input.status;
  if (input.actualAttended !== undefined) values.actualAttended = input.actualAttended;
  if (input.notes !== undefined) {
    values.notesEncrypted = input.notes ? encryptField(input.notes) : null;
  }

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .update(salonGuest)
      .set(values)
      .where(eq(salonGuest.id, guestId))
      .returning();
  });

  return row ? toGuestView(row, { includePhone: true }) : null;
}

export async function deleteGuest(
  salonId: bigint,
  guestId: bigint,
  ctx: AuditContext,
  userId: bigint
): Promise<boolean> {
  const access = await loadAccess(salonId, userId);
  if (!access) return false;

  const [target] = await db
    .select()
    .from(salonGuest)
    .where(and(eq(salonGuest.id, guestId), eq(salonGuest.salonId, salonId)))
    .limit(1);
  if (!target) return false;

  const canDelete =
    access.isOrganizer || access.isStaff || target.broughtByUserId === userId;
  if (!canDelete) return false;

  await withAuditContext(ctx, async (tx) => {
    await tx.delete(salonGuest).where(eq(salonGuest.id, guestId));
  });
  return true;
}

// ============================================
// 动态 (公告 / 留言 / 提问 / 系统消息)
// ============================================

export async function listActivities(
  salonId: bigint,
  userId: bigint,
  limit = 100
): Promise<SalonActivityView[] | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;

  const canSeeStaffOnly = access.isOrganizer || access.isStaff;
  const conds: SQL[] = [eq(salonActivity.salonId, salonId)];
  if (!canSeeStaffOnly) {
    conds.push(eq(salonActivity.visibility, "all"));
  }

  const rows = await db
    .select()
    .from(salonActivity)
    .where(and(...conds))
    .orderBy(desc(salonActivity.createdAt))
    .limit(limit);

  const authorIds = Array.from(new Set(rows.map((r) => r.authorUserId.toString())));
  const authors = authorIds.length
    ? await db
        .select({ id: user.id, name: user.name, avatarUrl: user.avatarUrl })
        .from(user)
        .where(inArray(user.id, authorIds.map((i) => BigInt(i))))
    : [];
  const authorMap = new Map(authors.map((u) => [u.id.toString(), u]));

  return rows.map((r) => ({
    id: r.id.toString(),
    salonId: r.salonId.toString(),
    authorUserId: r.authorUserId.toString(),
    authorName: authorMap.get(r.authorUserId.toString())?.name ?? null,
    authorAvatar: authorMap.get(r.authorUserId.toString())?.avatarUrl ?? null,
    type: r.type as SalonActivityView["type"],
    content: r.content,
    metadata: r.metadata ?? null,
    visibility: r.visibility as SalonActivityView["visibility"],
    createdAt: r.createdAt,
  }));
}

export async function createActivity(
  salonId: bigint,
  input: {
    content: string;
    type?: "announcement" | "question" | "comment";
    visibility?: "all" | "staff" | "organizer";
  },
  ctx: AuditContext,
  userId: bigint
): Promise<SalonActivityView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;

  const type = input.type ?? "comment";
  // 公告仅主理人/会务可发
  if (type === "announcement" && !access.isOrganizer && !access.isStaff) return null;
  // 受邀者只能发 all 可见留言
  const visibility =
    access.isOrganizer || access.isStaff ? (input.visibility ?? "all") : "all";

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .insert(salonActivity)
      .values({
        salonId,
        authorUserId: userId,
        type,
        content: input.content,
        visibility,
      })
      .returning();
  });

  const [author] = await db
    .select({ name: user.name, avatarUrl: user.avatarUrl })
    .from(user)
    .where(eq(user.id, userId))
    .limit(1);

  return {
    id: row.id.toString(),
    salonId: row.salonId.toString(),
    authorUserId: row.authorUserId.toString(),
    authorName: author?.name ?? null,
    authorAvatar: author?.avatarUrl ?? null,
    type: row.type as SalonActivityView["type"],
    content: row.content,
    metadata: row.metadata ?? null,
    visibility: row.visibility as SalonActivityView["visibility"],
    createdAt: row.createdAt,
  };
}

// ============================================
// 资料 (附件)
// ============================================

export async function listAttachments(
  salonId: bigint,
  userId: bigint
): Promise<SalonAttachmentView[] | null> {
  const access = await loadAccess(salonId, userId);
  if (!access) return null;

  const canSeeStaffOnly = access.isOrganizer || access.isStaff;
  const conds: SQL[] = [eq(salonAttachment.salonId, salonId)];
  if (!canSeeStaffOnly) {
    conds.push(eq(salonAttachment.visibility, "all"));
  }

  const rows = await db
    .select()
    .from(salonAttachment)
    .where(and(...conds))
    .orderBy(desc(salonAttachment.createdAt));

  return rows.map((r) => ({
    id: r.id.toString(),
    salonId: r.salonId.toString(),
    name: r.name,
    fileUrl: r.fileUrl,
    fileType: r.fileType,
    visibility: r.visibility as SalonAttachmentView["visibility"],
    uploadedByUserId: r.uploadedByUserId?.toString() ?? null,
    createdAt: r.createdAt,
  }));
}

export async function createAttachment(
  salonId: bigint,
  input: { name: string; fileUrl: string; fileType?: string; visibility?: "all" | "staff" | "organizer" },
  ctx: AuditContext,
  userId: bigint
): Promise<SalonAttachmentView | null> {
  const access = await loadAccess(salonId, userId);
  if (!access || (!access.isOrganizer && !access.isStaff)) return null;

  const [row] = await withAuditContext(ctx, async (tx) => {
    return await tx
      .insert(salonAttachment)
      .values({
        salonId,
        name: input.name,
        fileUrl: input.fileUrl,
        fileType: input.fileType ?? "image",
        visibility: input.visibility ?? "all",
        uploadedByUserId: userId,
      })
      .returning();
  });

  return {
    id: row.id.toString(),
    salonId: row.salonId.toString(),
    name: row.name,
    fileUrl: row.fileUrl,
    fileType: row.fileType,
    visibility: row.visibility as SalonAttachmentView["visibility"],
    uploadedByUserId: row.uploadedByUserId?.toString() ?? null,
    createdAt: row.createdAt,
  };
}

export async function deleteAttachment(
  salonId: bigint,
  attachmentId: bigint,
  ctx: AuditContext,
  userId: bigint
): Promise<boolean> {
  const access = await loadAccess(salonId, userId);
  if (!access || (!access.isOrganizer && !access.isStaff)) return false;

  const rows = await withAuditContext(ctx, async (tx) => {
    return await tx
      .delete(salonAttachment)
      .where(
        and(eq(salonAttachment.id, attachmentId), eq(salonAttachment.salonId, salonId))
      )
      .returning();
  });
  return rows.length > 0;
}

// ============================================
// 聚合 (主理人视角)
// ============================================

export async function getSalonAggregates(
  salonId: bigint,
  userId: bigint
): Promise<SalonAggregates | null> {
  const access = await loadAccess(salonId, userId);
  if (!access || (!access.isOrganizer && !access.isStaff)) return null;

  const [countsMap, quotaRows] = await Promise.all([
    countsForSalons([salonId]),
    db
      .select()
      .from(salonQuota)
      .where(and(eq(salonQuota.salonId, salonId), eq(salonQuota.isActive, true))),
  ]);

  const base = finalizeCounts(
    countsMap.get(salonId.toString()) ?? emptyCounts(),
    access.salon.capacityTotal
  );

  const quotaRows2 = quotaRows.length
    ? await listQuotas(salonId, userId)
    : [];
  const activeQuotas = (quotaRows2 ?? []).filter((q) => q.isActive);

  return {
    ...base,
    quotaAssignees: activeQuotas.length,
    quotaTotal: activeQuotas.reduce((s, q) => s + q.quotaValue, 0),
    quotaExpectedTotal: activeQuotas.reduce((s, q) => s + q.expectedGuestCount, 0),
    quotaGuestTotal: activeQuotas.reduce((s, q) => s + q.guestCount, 0),
  };
}

// ============================================
// 测试/工具导出
// ============================================

export const __salonInternals = {
  hashForLookup,
  toBigIntOrNull,
};
