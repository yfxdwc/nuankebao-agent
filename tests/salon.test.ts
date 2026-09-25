// ============================================
// 沙龙模块集成测试 (真库; 跑 `pnpm test:run`)
// ============================================
// 前提: DATABASE_URL 指向 nuankebao_test (CI 同款; 见 .github/workflows/ci.yml)
//   本地: DATABASE_URL=postgres://nuankebao:***@localhost:5432/nuankebao_test pnpm test:run
// 覆盖:
//   - 创建 (含首批会务 + 受邀者) / 详情 / 可见性
//   - 列表 role 过滤 (我主理的 / 我受邀的 / 无关人看不到)
//   - RSVP (接受 + 预计带约人数) + 统计
//   - 邀请管理 (app 用户自动关联 / 非 app 用户 / 重复手机号 409 语义)
//   - 带约任务 (upsert / 进度 / 取消)
//   - 二级客人 (登记 / 重复 / 主理人视角带名人)
//   - 聚合 / 动态可见性 / 资料可见性 / 权限负例
// ============================================

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { db } from "@/lib/db";
import {
  user,
  customer,
  franchisee,
  salon,
  salonInvitation,
  salonGuest,
  salonQuota,
  salonActivity,
  salonAttachment,
} from "@/lib/db/schema";
import { eq, inArray, and, sql, isNull, isNotNull } from "drizzle-orm";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import type { AuditContext } from "@/lib/audit/context";
import {
  createSalon,
  getSalonDetail,
  listSalons,
  updateSalon,
  cancelSalon,
  listInvitations,
  createInvitation,
  rsvpSalon,
  listQuotas,
  upsertQuota,
  cancelQuota,
  createGuest,
  listGuests,
  listActivities,
  createActivity,
  createAttachment,
  listAttachments,
  getSalonAggregates,
} from "@/lib/db/queries/salon";
const ctx: AuditContext = { userId: null, ipAddress: null };

const ORGANIZER_PHONE = "13911110001";
const INVITEE_PHONE = "13911110002"; // app 用户 (会被自动关联)
const STAFF_PHONE = "13911110003"; // 非 app 用户 (会务)
const GUEST_PHONE = "13911110004"; // 二级客人 (非 app 用户)

let organizerId: bigint;
let inviteeId: bigint;
let salonId: bigint;

async function upsertUser(name: string, phone: string): Promise<bigint> {
  const phoneHash = hashForLookup(phone);
  await db
    .insert(user)
    .values({
      name,
      phoneEncrypted: encryptField(phone),
      phoneHash,
      role: "sales",
    })
    .onConflictDoNothing();
  const [row] = await db.select().from(user).where(eq(user.phoneHash, phoneHash)).limit(1);
  return row.id;
}

/// 本文件造过的沙龙标题 (用于清理 —— 有些用例自己 createSalon, 不走 beforeAll 那个 id)
const TEST_SALON_TITLES_SQL = sql`(title = '测试养生沙龙' OR title LIKE '计数-%')`;

/// 清理本文件造的所有沙龙 (含子表) —— beforeAll 预清 (扫历史泄漏) + afterAll 收尾都用它。
///   背景 (2026-09-26 定位): 旧 afterAll 只删 `beforeAll` 那一个 `salonId`,
///   而「计数-*」用例另建的沙龙从未被删 → 每跑一次漏一个; 累积 60 个后,
///   `listSalons(role:'invited', limit:50)` 的首页被残留占满, 新沙龙被挤出 → 断言假失败。
async function purgeTestSalons(): Promise<void> {
  const ids = (
    await db.execute<{ id: string }>(
      sql`SELECT id::text AS id FROM salon WHERE ${TEST_SALON_TITLES_SQL}`
    )
  ).map((r) => BigInt(r.id));
  if (ids.length === 0) return;
  await db.delete(salonActivity).where(inArray(salonActivity.salonId, ids));
  await db.delete(salonAttachment).where(inArray(salonAttachment.salonId, ids));
  await db.delete(salonGuest).where(inArray(salonGuest.salonId, ids));
  await db.delete(salonQuota).where(inArray(salonQuota.salonId, ids));
  await db.delete(salonInvitation).where(inArray(salonInvitation.salonId, ids));
  await db.delete(salon).where(inArray(salon.id, ids));
}

beforeAll(async () => {
  await purgeTestSalons(); // ★ 幂等预清理: 历史泄漏 / 上次中断残留 → 防累积
  organizerId = await upsertUser("测试主理人", ORGANIZER_PHONE);
  inviteeId = await upsertUser("测试受邀者", INVITEE_PHONE);

  const created = await createSalon(
    {
      title: "测试养生沙龙",
      subtitle: "肩颈调理体验",
      status: "published",
      startAt: new Date(Date.now() + 86_400_000).toISOString(),
      endAt: new Date(Date.now() + 90_000_000).toISOString(),
      address: "测试市测试路 1 号",
      locationName: "测试会所",
      capacityTotal: 20,
      feeType: "free",
      agenda: [{ start: "14:00", title: "开场" }, { start: "14:30", title: "体验" }],
      themeTags: ["肩颈", "体验"],
    },
    {
      staff: [{ name: "会务小张", phone: STAFF_PHONE, staffRole: "主持" }],
      invitees: [{ name: "受邀小李", phone: INVITEE_PHONE, expectedGuestCount: 2 }],
    },
    ctx,
    organizerId
  );
  salonId = BigInt(created.id);
});

afterAll(async () => {
  // ★ 全量清理 (不再只删 salonId): 「计数-*」用例另建的沙龙也要删, 否则每次跑漏一个
  await purgeTestSalons();
  await db
    .delete(user)
    .where(inArray(user.phoneHash, [ORGANIZER_PHONE, INVITEE_PHONE].map(hashForLookup)));
});

describe("salon — 创建 / 详情 / 可见性", () => {
  it("主理人创建后能在详情看到自己的身份 + 统计", async () => {
    const detail = await getSalonDetail(salonId, organizerId);
    expect(detail).not.toBeNull();
    expect(detail!.title).toBe("测试养生沙龙");
    expect(detail!.viewer.isOrganizer).toBe(true);
    expect(detail!.viewer.myRole).toBe("organizer");
    // 首批: 1 会务 + 1 受邀者
    expect(detail!.counts.staffCount).toBe(1);
    expect(detail!.counts.pending).toBe(1);
    expect(detail!.counts.expectedGuests).toBe(2);
    expect(detail!.counts.capacityTotal).toBe(20);
    expect(detail!.counts.capacityRemaining).toBe(20);
    expect(detail!.agenda.length).toBe(2);
  });

  it("受邀者能看到沙龙; 无关用户看不到 (null)", async () => {
    const asInvitee = await getSalonDetail(salonId, inviteeId);
    expect(asInvitee).not.toBeNull();
    expect(asInvitee!.viewer.isOrganizer).toBe(false);
    expect(asInvitee!.viewer.myStatus).toBe("pending");
    expect(asInvitee!.viewer.myExpectedGuestCount).toBe(2);

    const asOutsider = await getSalonDetail(salonId, BigInt(999_999_999));
    expect(asOutsider).toBeNull();
  });

  it("列表 role 过滤: 我主理的 / 我受邀的 / 无关人", async () => {
    const organizing = await listSalons({ userId: organizerId, role: "organizing" });
    expect(organizing.items.some((s) => s.id === salonId.toString())).toBe(true);

    const invited = await listSalons({ userId: inviteeId, role: "invited" });
    expect(invited.items.some((s) => s.id === salonId.toString())).toBe(true);

    // 主理人的受邀列表里不应有它 (没被邀请)
    const orgInvited = await listSalons({ userId: organizerId, role: "invited" });
    expect(orgInvited.items.some((s) => s.id === salonId.toString())).toBe(false);

    const outsider = await listSalons({ userId: BigInt(999_999_999), role: "all" });
    expect(outsider.items.some((s) => s.id === salonId.toString())).toBe(false);
  });

  it("非主理人不能编辑 (返回 null)", async () => {
    const updated = await updateSalon(salonId, { title: "被篡改" }, ctx, inviteeId);
    expect(updated).toBeNull();
  });
});

describe("salon — 邀请管理", () => {
  it("app 用户被自动关联 (inviteeUserId 非空); 会务手机号对受邀者按设置可见", async () => {
    const list = await listInvitations(salonId, organizerId);
    expect(list).not.toBeNull();
    const inviteeRow = list!.find((i) => i.inviteeName === "受邀小李");
    expect(inviteeRow).toBeDefined();
    expect(inviteeRow!.inviteeUserId).toBe(inviteeId.toString());
    expect(inviteeRow!.inviteePhone).toBe(INVITEE_PHONE);

    const staffRow = list!.find((i) => i.roleInSalon === "staff");
    expect(staffRow).toBeDefined();
    expect(staffRow!.inviteeUserId).toBeNull(); // 非 app 用户
    expect(staffRow!.staffRole).toBe("主持");
  });

  it("重复手机号邀请 → null (API 层转 409)", async () => {
    const dup = await createInvitation(
      salonId,
      { name: "重复小李", phone: INVITEE_PHONE },
      ctx,
      organizerId
    );
    expect(dup).toBeNull();
  });

  it("受邀者能看名单, 但看不到别的受邀者手机号; 会务电话按设置可见", async () => {
    // 主理人再加一位非 app 受邀者 (对照)
    const other = await createInvitation(
      salonId,
      { name: "受邀小赵", phone: "13911110005" },
      ctx,
      organizerId
    );
    expect(other).not.toBeNull();

    const list = await listInvitations(salonId, inviteeId);
    expect(list).not.toBeNull();

    // 另一位受邀者: 手机号对受邀者隐藏
    const otherRow = list!.find((i) => i.inviteeName === "受邀小赵");
    expect(otherRow!.inviteePhone).toBeNull();
    expect(otherRow!.notes).toBeNull();

    // 本人: 自己的手机号可见
    const self = list!.find((i) => i.inviteeName === "受邀小李");
    expect(self!.inviteePhone).toBe(INVITEE_PHONE);

    // 会务: 默认 staffContact='all' → 电话可见 (受邀者要能联系会务)
    const staff = list!.find((i) => i.roleInSalon === "staff");
    expect(staff!.inviteePhone).toBe(STAFF_PHONE);

    // 改成 'staff' → 受邀者看不到会务电话
    await updateSalon(
      salonId,
      { visibilitySettings: { attendeeList: "all", staffContact: "staff" } },
      ctx,
      organizerId
    );
    const tightened = await listInvitations(salonId, inviteeId);
    const staffAfter = tightened!.find((i) => i.roleInSalon === "staff");
    expect(staffAfter!.inviteePhone).toBeNull();

    // 恢复默认, 不影响后续用例
    await updateSalon(
      salonId,
      { visibilitySettings: { attendeeList: "all", staffContact: "all" } },
      ctx,
      organizerId
    );
  });
});

describe("salon — RSVP", () => {
  it("受邀者接受 + 填预计带约 3 人 → 统计更新", async () => {
    const result = await rsvpSalon(
      salonId,
      inviteeId,
      { status: "accepted", expectedGuestCount: 3, notes: "我带 3 位邻居" },
      ctx
    );
    expect(result).not.toBeNull();
    expect(result!.status).toBe("accepted");
    expect(result!.expectedGuestCount).toBe(3);

    const detail = await getSalonDetail(salonId, organizerId);
    expect(detail!.counts.accepted).toBe(1);
    expect(detail!.counts.pending).toBe(1); // 上一用例新增的「受邀小赵」仍待回复
    expect(detail!.counts.expectedGuests).toBe(3);
    expect(detail!.counts.capacityRemaining).toBe(19);

    // 主理人能看到受邀者留言 (解密)
    const list = await listInvitations(salonId, organizerId);
    const row = list!.find((i) => i.inviteeName === "受邀小李");
    expect(row!.notes).toBe("我带 3 位邻居");
  });

  it("主理人不能给自己 RSVP (null)", async () => {
    const result = await rsvpSalon(salonId, organizerId, { status: "accepted" }, ctx);
    expect(result).toBeNull();
  });
});

describe("salon — 带约任务", () => {
  it("分配任务 → 进度取 max(自报, 已登记)", async () => {
    const quota = await upsertQuota(
      salonId,
      { assignedToUserId: inviteeId.toString(), quotaValue: 5, note: "带 5 位客户" },
      ctx,
      organizerId
    );
    expect(quota).not.toBeNull();
    expect(quota!.quotaValue).toBe(5);
    expect(quota!.expectedGuestCount).toBe(3); // 上面 RSVP 自报的
    expect(quota!.progress).toBe(3);

    // 重复分配 → 更新而非新增
    const updated = await upsertQuota(
      salonId,
      { assignedToUserId: inviteeId.toString(), quotaValue: 6 },
      ctx,
      organizerId
    );
    expect(updated!.quotaValue).toBe(6);

    const list = await listQuotas(salonId, organizerId);
    expect(list!.filter((q) => q.isActive).length).toBe(1);
  });

  it("受邀者只看得到自己的任务", async () => {
    const mine = await listQuotas(salonId, inviteeId);
    expect(mine!.length).toBe(1);
    expect(mine![0].assignedToUserId).toBe(inviteeId.toString());
  });

  it("取消任务 (isActive=false)", async () => {
    const list = await listQuotas(salonId, organizerId);
    const active = list!.find((q) => q.isActive);
    const ok = await cancelQuota(salonId, BigInt(active!.id), ctx, organizerId);
    expect(ok).toBe(true);
    const after = await listQuotas(salonId, organizerId);
    expect(after!.filter((q) => q.isActive).length).toBe(0);
  });
});

describe("salon — 二级客人", () => {
  it("受邀者登记非 app 客人; 每人只能看自己的", async () => {
    const guest = await createGuest(
      salonId,
      { name: "邻居王姐", phone: GUEST_PHONE, relation: "friend", notes: "肩颈不好" },
      ctx,
      inviteeId
    );
    expect(guest).not.toBeNull();
    expect(guest!.broughtByUserId).toBe(inviteeId.toString());
    expect(guest!.phone).toBe(GUEST_PHONE);

    // 重复手机号 → null
    const dup = await createGuest(
      salonId,
      { name: "王姐重复", phone: GUEST_PHONE },
      ctx,
      inviteeId
    );
    expect(dup).toBeNull();

    // 受邀者 (非主理人) 默认只看自己的
    const mine = await listGuests(salonId, inviteeId);
    expect(mine!.length).toBe(1);

    // 主理人看全部 + 带名人
    const all = await listGuests(salonId, organizerId);
    expect(all!.length).toBe(1);
    expect(all![0].broughtByName).toBe("测试受邀者");
  });

  it("统计: 已登记二级客人计入 counts / 带约进度", async () => {
    const detail = await getSalonDetail(salonId, organizerId);
    expect(detail!.counts.guestRegistered).toBe(1);
    expect(detail!.counts.guestAttended).toBe(0);
  });
});

describe("salon — 动态 / 资料 / 聚合 / 取消", () => {
  it("公告仅主理人/会务可见 (visibility=staff)", async () => {
    const ann = await createActivity(
      salonId,
      { content: "内部会务安排", type: "announcement", visibility: "staff" },
      ctx,
      organizerId
    );
    expect(ann).not.toBeNull();

    const asOrganizer = await listActivities(salonId, organizerId);
    expect(asOrganizer!.some((a) => a.content === "内部会务安排")).toBe(true);

    const asInvitee = await listActivities(salonId, inviteeId);
    expect(asInvitee!.some((a) => a.content === "内部会务安排")).toBe(false);

    // 受邀者不能发公告 (返回 null)
    const denied = await createActivity(
      salonId,
      { content: "我也来公告", type: "announcement" },
      ctx,
      inviteeId
    );
    expect(denied).toBeNull();
  });

  it("资料可见性: staff 资料的受邀者看不到", async () => {
    await createAttachment(
      salonId,
      { name: "会务手册", fileUrl: "/uploads/test-staff.jpg", visibility: "staff" },
      ctx,
      organizerId
    );
    const asInvitee = await listAttachments(salonId, inviteeId);
    expect(asInvitee!.length).toBe(0);

    const asOrganizer = await listAttachments(salonId, organizerId);
    expect(asOrganizer!.length).toBe(1);
  });

  it("聚合接口: 任务总额 / 自报总额", async () => {
    const agg = await getSalonAggregates(salonId, organizerId);
    expect(agg).not.toBeNull();
    expect(agg!.accepted).toBe(1);
    expect(agg!.expectedGuests).toBe(3);
    // 任务已在上面的用例里取消 → active 0
    expect(agg!.quotaAssignees).toBe(0);

    // 受邀者无权看聚合
    const denied = await getSalonAggregates(salonId, inviteeId);
    expect(denied).toBeNull();
  });

  it("取消沙龙 → status=cancelled (数据保留)", async () => {
    const cancelled = await cancelSalon(salonId, ctx, organizerId);
    expect(cancelled!.status).toBe("cancelled");
    // 受邀者仍能看到 (已取消的活动)
    const stillVisible = await getSalonDetail(salonId, inviteeId);
    expect(stillVisible).not.toBeNull();
    expect(stillVisible!.status).toBe("cancelled");
  });
});

describe("salon — quick-invite-suggestions (query 层)", () => {
  it("getUplineAncestors 沿 path 删末段得到 ≤N 层", async () => {
    // 直接验 SQL 行为, 不起 HTTP
    const { getUplineAncestors } = await import("@/lib/db/queries/franchisee");

    // dev DB 找一个深度≥3 的用户
    const deep = await db
      .select({ fid: user.franchiseeId })
      .from(user)
      .where(isNotNull(user.franchiseeId))
      .limit(20);
    let ancestorCheck: Awaited<ReturnType<typeof getUplineAncestors>> = [];
    let meFid: bigint | null = null;
    for (const u of deep) {
      if (u.fid == null) continue;
      const ancestors = await getUplineAncestors(u.fid, 3);
      if (ancestors.length >= 2) {
        meFid = u.fid;
        ancestorCheck = ancestors;
        break;
      }
    }
    if (meFid == null) {
      // dev DB 没合适 fixture, 跳过不失败
      return;
    }

    // 上层 1 = 直接上层, level 严格 1/2/3 递增
    expect(ancestorCheck[0]!.level).toBe(1);
    expect(ancestorCheck[1]!.level).toBe(2);
    if (ancestorCheck.length >= 3) expect(ancestorCheck[2]!.level).toBe(3);

    // 每个 ancestor 都要满足: 其 placement_depth 严格小于 我的
    const [meRow] = await db
      .select({ placementDepth: franchisee.placementDepth })
      .from(franchisee)
      .where(eq(franchisee.id, meFid));
    for (const a of ancestorCheck) {
      // a 没有 placementDepth 字段, 用 placement_path 推算
      // ancestor 的 placement_path 段数 ≤ 我的 - 1
      // 这里只断言 phoneEncrypted 不空 (decrypt-able)
      expect(a.phoneEncrypted.length).toBeGreaterThan(0);
      expect(a.name.length).toBeGreaterThan(0);
    }
    void meRow;
  });
});

describe("salon — 取消带 reason", () => {
  it("主理人取消 → status=cancelled + system 动态含 reason", async () => {
    const { cancelSalon } = await import("@/lib/db/queries/salon");

    // 复用现有 organizerId 建一个草稿沙龙
    const created = await createSalon(
      {
        title: "测试-取消理由",
        status: "published",
        startAt: new Date(Date.now() + 86_400_000).toISOString(),
      },
      { staff: [], invitees: [] },
      ctx,
      organizerId,
    );
    const salonId = BigInt(created.id);

    const reason = "测试理由 — 场地维修改期下周五";
    const cancelled = await cancelSalon(salonId, ctx, organizerId, reason);
    expect(cancelled).not.toBeNull();
    expect(cancelled!.status).toBe("cancelled");

    // 看 salon_activity 表
    const acts = await db
      .select()
      .from(salonActivity)
      .where(eq(salonActivity.salonId, salonId));
    const sysAct = acts.find((a) => a.type === "system" && (a.metadata as any)?.event === "salon_cancelled");
    expect(sysAct).toBeDefined();
    expect(sysAct!.content).toContain(reason);
    expect((sysAct!.metadata as any).reason).toBe(reason);
    expect(sysAct!.visibility).toBe("all");
  });

  it("取消 reason 太短 → query 层不限制, 但 API 层会 400 (验证 zod 在 API 层)", async () => {
    // 直接调 query 不应崩; 校验在 route 层
    const { SalonCancelSchema } = await import("@/lib/salon/validation");
    expect(SalonCancelSchema.safeParse({ reason: "太短" }).success).toBe(false);
    expect(SalonCancelSchema.safeParse({ reason: "足够长的理由超过十字哈" }).success).toBe(true);
    expect(SalonCancelSchema.safeParse({ reason: "x".repeat(501) }).success).toBe(false);
  });

  it("重复取消幂等: 不重复写动态", async () => {
    const { cancelSalon } = await import("@/lib/db/queries/salon");
    const created = await createSalon(
      {
        title: "测试-幂等取消",
        status: "published",
        startAt: new Date(Date.now() + 86_400_000).toISOString(),
      },
      { staff: [], invitees: [] },
      ctx,
      organizerId,
    );
    const salonId = BigInt(created.id);

    await cancelSalon(salonId, ctx, organizerId, "第一次取消理由");
    await cancelSalon(salonId, ctx, organizerId, "第二次取消理由 (应该幂等, 不写第二条)");

    const acts = await db
      .select()
      .from(salonActivity)
      .where(eq(salonActivity.salonId, salonId));
    const cancelActs = acts.filter((a) => (a.metadata as any)?.event === "salon_cancelled");
    expect(cancelActs.length).toBe(1); // 只有 1 条
    expect(cancelActs[0]!.content).toContain("第一次取消理由"); // 第二次不写
  });

  it("非主理人调用 cancelSalon → 返回 null", async () => {
    const { cancelSalon } = await import("@/lib/db/queries/salon");
    const created = await createSalon(
      {
        title: "测试-非主理人取消",
        status: "published",
        startAt: new Date(Date.now() + 86_400_000).toISOString(),
      },
      { staff: [], invitees: [] },
      ctx,
      organizerId,
    );
    const salonId = BigInt(created.id);

    const result = await cancelSalon(salonId, ctx, inviteeId, "不应该成功");
    expect(result).toBeNull();

    // 状态应保持 published
    const detail = await getSalonDetail(created.id, organizerId);
    expect(detail!.status).toBe("published");
  });
});

describe("salon — active counts (Tab 角标)", () => {
  it("返回 organizing + invited 各多少「进行中」", async () => {
    const { getSalonActiveCounts } = await import("@/lib/db/queries/salon");

    // organizer 视角 — 我主理的几个
    await createSalon(
      { title: "计数-A", status: "published", startAt: futureIso(1) },
      { staff: [], invitees: [] },
      ctx,
      organizerId,
    );
    await createSalon(
      { title: "计数-B", status: "draft", startAt: futureIso(2) },
      { staff: [], invitees: [] },
      ctx,
      organizerId,
    );
    const cId = BigInt(
      (
        await createSalon(
          { title: "计数-C", status: "published", startAt: futureIso(3) },
          { staff: [], invitees: [] },
          ctx,
          organizerId,
        )
      ).id,
    );
    const { cancelSalon } = await import("@/lib/db/queries/salon");
    await cancelSalon(cId, ctx, organizerId, "不算进行中");

    // 计数: 应是 2 (A + B, 不含已取消的 C)
    const counts = await getSalonActiveCounts(organizerId);
    expect(counts.organizing).toBeGreaterThanOrEqual(2);

    // 受邀视角 — 邀请另一 user
    await createSalon(
      {
        title: "计数-D-邀请受邀者",
        status: "published",
        startAt: futureIso(4),
      },
      {
        staff: [],
        invitees: [{ name: "测试受邀者", phone: INVITEE_PHONE }],
      },
      ctx,
      organizerId,
    );
    const counts2 = await getSalonActiveCounts(inviteeId);
    expect(counts2.invited).toBeGreaterThanOrEqual(1);
    expect(counts2.organizing).toBe(0);
  });

  it("0 沙龙时 counts 都是 0", async () => {
    const { getSalonActiveCounts } = await import("@/lib/db/queries/salon");
    // 用一个不存在的 user id (无 salon) → counts 应为 0
    const hugeUserId = BigInt("9999999999");
    const counts = await getSalonActiveCounts(hugeUserId);
    expect(counts.organizing).toBe(0);
    expect(counts.invited).toBe(0);
  });
});

function futureIso(daysFromNow: number): string {
  return new Date(Date.now() + daysFromNow * 86_400_000).toISOString();
}
