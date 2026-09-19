// ============================================
// 权益判定 + 发放 (DB 层, 服务端唯一安全边界)
// ============================================
// ADR-0012 §5. 调用方 (route / query 层) 用这里, 不要自己写 SQL 判会员 ———
// 判定口径只有一处: `member_until > now()` (缺省=非会员)
//
// 判权失败的约定:
//   requireFeature() 抛 BillingError(402, code=MEMBERSHIP_REQUIRED)
//   route 里 catch 后返回 JSON; 客户端见 402 → 弹"开通会员"引导
//   (客户端隐藏入口只是体验, 真正的门在这里)

import { and, eq, sql, gte, count } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  membership,
  entitlementGrant,
  referralCode,
  referralReward,
  user as userTable,
  type Membership,
} from "@/lib/db/schema";
import {
  addDays,
  checkReferralQuota,
  generateReferralCode,
  grantIdempotencyKey,
  isMemberUntil,
  isValidReferralCodeShape,
  normalizeReferralCode,
  REFERRAL_CLAIM_WINDOW_HOURS,
  REFERRAL_GRANT_DAYS,
  isWithinClaimWindow,
  type ReferralQuotaResult,
} from "@/lib/billing/referral";
import {
  ALL_FEATURES,
  FREE_FEATURES,
  isFeatureKey,
  type FeatureKey,
} from "@/lib/billing/features";

/** 会员来源: 付费/权益 vs 后台账号 (角色即规则) */
export type MembershipSource = "paid" | "admin" | "free";

/** 会员判定结果 (供 API 直接序列化给客户端) */
export interface MembershipView {
  isMember: boolean;
  memberUntil: string | null;
  /** free / member / admin (admin = 后台账号永久会员) */
  planCode: string | null;
  features: FeatureKey[];
  referralCode: string | null;
  /** 永久会员 (后台账号, 不参与计费, 不会到期) */
  permanent: boolean;
  membershipSource: MembershipSource;
}

export class BillingError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** 读会员状态 (没有行 = 免费用户) */
export async function getMembership(
  userId: bigint,
  now: Date = new Date()
): Promise<{ row: Membership | null; isMember: boolean; permanent: boolean }> {
  // 一次查询拿 (user.role + membership): 判权会被高频调用, 不加第二次往返
  const [row] = await db
    .select({
      userRole: userTable.role,
      memberUntil: membership.memberUntil,
      membershipId: membership.id,
    })
    .from(userTable)
    .leftJoin(membership, eq(membership.userId, userTable.id))
    .where(eq(userTable.id, userId))
    .limit(1);

  // ★ 角色即规则 (主人 2026-09-19): 系统管理员 = 永久会员
  //   为什么不给 admin 写一行"永久"权益: 写了要维护 (新管理员要补、过期要续、审计里一堆假流水),
  //   而 role 本来就是"这是后台账号"的唯一真相 → 直接按角色判定, 零数据、零维护。
  //   边界: 只有在 user 表里 role='admin' 才算 (不是客户端传的, 也不是 session 里能改的)
  if (row?.userRole === "admin") {
    return { row: null, isMember: true, permanent: true };
  }

  const memberRow = row?.membershipId != null
    ? ({ memberUntil: row.memberUntil } as Membership)
    : null;

  return {
    row: memberRow,
    isMember: isMemberUntil(row?.memberUntil, now),
    permanent: false,
  };
}

/** 给客户端看的会员视图 (含推荐码) */
export async function getMembershipView(
  userId: bigint
): Promise<MembershipView> {
  const { row, isMember, permanent } = await getMembership(userId);
  const [code] = await db
    .select({ code: referralCode.code })
    .from(referralCode)
    .where(eq(referralCode.userId, userId))
    .limit(1);

  const source: MembershipSource = permanent
    ? "admin"
    : isMember
      ? "paid"
      : "free";

  return {
    isMember,
    memberUntil: row?.memberUntil ? row.memberUntil.toISOString() : null,
    planCode: permanent ? "admin" : isMember ? "member" : "free",
    features: isMember ? ALL_FEATURES : FREE_FEATURES,
    referralCode: code?.code ?? null,
    permanent,
    membershipSource: source,
  };
}

/** 会员功能判定 (不是会员 → 抛 402) */
export async function requireFeature(
  userId: bigint,
  key: FeatureKey
): Promise<void> {
  if (!isFeatureKey(key)) {
    // 约定写错 = 代码 bug, 不能静默放行 (否则白送功能)
    throw new BillingError(500, "BAD_FEATURE_KEY", `未知会员功能: ${key}`);
  }
  const { isMember } = await getMembership(userId);
  if (!isMember) {
    throw new BillingError(
      402,
      "MEMBERSHIP_REQUIRED",
      "这个功能是会员功能, 开通会员后可用"
    );
  }
}

/** 生日提醒这类"读数据时降级"的场景: 非会员 → 把提醒设置读成 null */
export async function filterByMembership<T extends { birthdayRemindDays?: number | null }>(
  userId: bigint,
  customer: T
): Promise<T> {
  const { isMember } = await getMembership(userId);
  if (isMember) return customer;
  return { ...customer, birthdayRemindDays: null };
}

// ============================================
// 发放 (送天数)
// ============================================

export interface GrantResult {
  granted: boolean;
  reason: string;
  memberUntil: string | null;
}

/**
 * 送 N 天会员权益 (幂等)
 *
 * 幂等: idempotencyKey 唯一索引; 重复调用直接返回 granted=false (不报错)
 * 叠加: member_until = max(now, member_until) + days (顺延, 不吞已付时间)
 */
export async function grantDays(opts: {
  userId: bigint;
  days: number;
  reason:
    | "referral_referee"
    | "referral_referrer"
    | "gift"
    | "compensation"
    | "manual";
  idempotencyKey: string;
  grantedByUserId?: bigint | null;
  note?: string | null;
  now?: Date;
}): Promise<GrantResult> {
  const now = opts.now ?? new Date();
  if (opts.days <= 0) {
    return { granted: false, reason: "days<=0", memberUntil: null };
  }

  return await db.transaction(async (tx) => {
    // 1) 幂等占位 (唯一索引冲突 = 已经发过)
    const inserted = await tx
      .insert(entitlementGrant)
      .values({
        userId: opts.userId,
        days: opts.days,
        reason: opts.reason,
        idempotencyKey: opts.idempotencyKey,
        grantedByUserId: opts.grantedByUserId ?? null,
        note: opts.note ?? null,
      })
      .onConflictDoNothing({ target: entitlementGrant.idempotencyKey })
      .returning({ id: entitlementGrant.id });

    if (inserted.length === 0) {
      const { row } = await getMembership(opts.userId, now);
      return {
        granted: false,
        reason: "already_granted",
        memberUntil: row?.memberUntil?.toISOString() ?? null,
      };
    }

    // 2) 顺延权益
    const [current] = await tx
      .select({ memberUntil: membership.memberUntil })
      .from(membership)
      .where(eq(membership.userId, opts.userId))
      .limit(1);

    const next = addDays(current?.memberUntil ?? null, opts.days, now);

    if (!current) {
      await tx
        .insert(membership)
        .values({ userId: opts.userId, memberUntil: next, updatedAt: now })
        .onConflictDoNothing({ target: membership.userId });
    } else {
      await tx
        .update(membership)
        .set({ memberUntil: next, updatedAt: now })
        .where(eq(membership.userId, opts.userId));
    }

    return {
      granted: true,
      reason: "granted",
      memberUntil: next.toISOString(),
    };
  });
}

// ============================================
// 推荐码
// ============================================

/** 拿我的推荐码 (没有就生成一个, 冲突重试) */
export async function ensureReferralCode(userId: bigint): Promise<string> {
  const [existing] = await db
    .select({ code: referralCode.code })
    .from(referralCode)
    .where(eq(referralCode.userId, userId))
    .limit(1);
  if (existing) return existing.code;

  for (let attempt = 0; attempt < 8; attempt++) {
    const code = generateReferralCode();
    const inserted = await db
      .insert(referralCode)
      .values({ userId, code })
      .onConflictDoNothing()
      .returning({ code: referralCode.code });
    if (inserted.length > 0) return inserted[0].code;
    // 用户已存在 (并发) → 重读
    const [again] = await db
      .select({ code: referralCode.code })
      .from(referralCode)
      .where(eq(referralCode.userId, userId))
      .limit(1);
    if (again) return again.code;
  }
  throw new BillingError(500, "CODE_GEN_FAILED", "推荐码生成失败, 请重试");
}

/** 推荐人本月 / 累计已发出的奖励次数 */
export async function referralUsage(
  referrerUserId: bigint,
  now: Date = new Date()
): Promise<{ usedThisMonth: number; usedTotal: number }> {
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

  const [thisMonth] = await db
    .select({ n: count() })
    .from(referralReward)
    .where(
      and(
        eq(referralReward.referrerUserId, referrerUserId),
        eq(referralReward.status, "rewarded"),
        gte(referralReward.rewardedAt, monthStart)
      )
    );

  const [total] = await db
    .select({ n: count() })
    .from(referralReward)
    .where(
      and(
        eq(referralReward.referrerUserId, referrerUserId),
        eq(referralReward.status, "rewarded")
      )
    );

  return {
    usedThisMonth: Number(thisMonth?.n ?? 0),
    usedTotal: Number(total?.n ?? 0),
  };
}

export interface ClaimReferralResult {
  accepted: boolean;
  reason: string;
  /** 被推荐人自己是否已经拿到 15 天 (REFEREE_GRANT_ON_VERIFY=true 时立即发) */
  refereeGranted: boolean;
  referrerPending: boolean;
}

/**
 * 新用户填推荐码
 *
 * 规则 (ADR-0012 §6):
 *   - 注册时可填, 注册后不可补填 (调用方只在注册流程里调)
 *   - 被推荐人: 立即得 15 天 (REFEREE_GRANT_ON_VERIFY)
 *   - 推荐人: 建 pending 记录; **被推荐人成为加盟者后**才真发 (D23)
 *   - 反作弊: 不能推自己 / 同 IP 待审 / (referrer, referee) 唯一
 */
export async function claimReferralCode(opts: {
  refereeUserId: bigint;
  rawCode: string;
  refereePhoneHash?: string | null;
  refereeIp?: string | null;
  now?: Date;
}): Promise<ClaimReferralResult> {
  const now = opts.now ?? new Date();
  const code = normalizeReferralCode(opts.rawCode);
  if (!isValidReferralCodeShape(code)) {
    return {
      accepted: false,
      reason: "推荐码格式不对 (6 位字母数字)",
      refereeGranted: false,
      referrerPending: false,
    };
  }

  // ★ 只有"注册时"能填 (主人 2026-09-19): 账号太老就不收码
  //   入口本来就只有建号路径 (import-users / 未来注册页), 这里是服务端兜底 ——
  //   防止有人直接打 API 给老账号补码
  const [referee] = await db
    .select({ createdAt: userTable.createdAt })
    .from(userTable)
    .where(eq(userTable.id, opts.refereeUserId))
    .limit(1);
  if (!isWithinClaimWindow(referee?.createdAt, now)) {
    return {
      accepted: false,
      reason: `推荐码只能在注册时填 (账号创建后 ${REFERRAL_CLAIM_WINDOW_HOURS} 小时内)`,
      refereeGranted: false,
      referrerPending: false,
    };
  }

  const [owner] = await db
    .select({ userId: referralCode.userId })
    .from(referralCode)
    .where(eq(referralCode.code, code))
    .limit(1);

  if (!owner) {
    return {
      accepted: false,
      reason: "推荐码不存在",
      refereeGranted: false,
      referrerPending: false,
    };
  }
  if (owner.userId === opts.refereeUserId) {
    return {
      accepted: false,
      reason: "不能推荐自己",
      refereeGranted: false,
      referrerPending: false,
    };
  }

  const quota: ReferralQuotaResult = checkReferralQuota(
    await referralUsage(owner.userId, now)
  );
  if (!quota.ok) {
    return {
      accepted: false,
      reason: quota.reason,
      refereeGranted: false,
      referrerPending: false,
    };
  }

  // 建推荐关系 (唯一索引保证一生一次)
  const inserted = await db
    .insert(referralReward)
    .values({
      referrerUserId: owner.userId,
      refereeUserId: opts.refereeUserId,
      code,
      status: "pending",
      refereePhoneHash: opts.refereePhoneHash ?? null,
      refereeSignupIp: opts.refereeIp ?? null,
      createdAt: now,
    })
    .onConflictDoNothing({
      target: [referralReward.referrerUserId, referralReward.refereeUserId],
    })
    .returning({ id: referralReward.id });

  if (inserted.length === 0) {
    return {
      accepted: false,
      reason: "这个账号已经用推荐码领过了",
      refereeGranted: false,
      referrerPending: false,
    };
  }

  const grant = await grantDays({
    userId: opts.refereeUserId,
    days: REFERRAL_GRANT_DAYS,
    reason: "referral_referee",
    idempotencyKey: grantIdempotencyKey(
      "referral_referee",
      owner.userId.toString(),
      opts.refereeUserId.toString()
    ),
    note: `填推荐码 ${code}`,
    now,
  });

  return {
    accepted: true,
    reason: "推荐码已生效",
    refereeGranted: grant.granted,
    referrerPending: true, // D23: 等被推荐人成为加盟者
  };
}

/**
 * 被推荐人成为加盟者 → 发推荐人奖励 (D23)
 *
 * 触发点: 加盟商创建/落位成功时调用 (src/lib/db/queries/franchisee*.ts 的创建路径)
 * 幂等: (referrer, referee) 唯一 + grant idempotencyKey
 *
 * 返回: 发了几个 (0 = 没有待发的推荐关系)
 */
export async function rewardReferrerOnFranchisee(opts: {
  newFranchiseePhoneHash: string;
  now?: Date;
}): Promise<{ rewarded: number }> {
  const now = opts.now ?? new Date();

  // 找到"手机号 = 这个新加盟商"的用户 → 他们若是被推荐人 → 给推荐人发奖
  const { user } = await import("@/lib/db/schema");
  const referees = await db
    .select({ userId: user.id })
    .from(user)
    .where(eq(user.phoneHash, opts.newFranchiseePhoneHash));

  let rewarded = 0;
  for (const r of referees) {
    const pending = await db
      .select()
      .from(referralReward)
      .where(
        and(
          eq(referralReward.refereeUserId, r.userId),
          eq(referralReward.status, "pending")
        )
      );

    for (const p of pending) {
      const quota = checkReferralQuota(
        await referralUsage(p.referrerUserId, now)
      );
      if (!quota.ok) {
        await db
          .update(referralReward)
          .set({ status: "rejected", rejectReason: quota.reason })
          .where(eq(referralReward.id, p.id));
        continue;
      }

      const grant = await grantDays({
        userId: p.referrerUserId,
        days: REFERRAL_GRANT_DAYS,
        reason: "referral_referrer",
        idempotencyKey: grantIdempotencyKey(
          "referral_referrer",
          p.referrerUserId.toString(),
          p.refereeUserId.toString()
        ),
        note: `被推荐人已成为加盟商 (推荐码 ${p.code})`,
        now,
      });

      await db
        .update(referralReward)
        .set({
          status: "rewarded",
          rewardedAt: now,
          rejectReason: grant.granted ? null : "already_granted",
        })
        .where(eq(referralReward.id, p.id));

      if (grant.granted) rewarded += 1;
    }
  }

  return { rewarded };
}

/**
 * 别名: "如果这个手机号对应的用户是被推荐人, 就发推荐人奖励"
 * (名字直白版, 给加盟商创建路径调用; 实现就是 rewardReferrerOnFranchisee)
 */
export const exitRewardIfReferral = rewardReferrerOnFranchisee;

/** 手工开通/延期 (S0 唯一入口; admin only) */
export async function adminGrant(opts: {
  targetUserId: bigint;
  days: number;
  actorUserId: bigint;
  note?: string;
}): Promise<GrantResult> {
  const now = new Date();
  return await grantDays({
    userId: opts.targetUserId,
    days: opts.days,
    reason: "manual",
    idempotencyKey: grantIdempotencyKey(
      "manual",
      opts.actorUserId.toString(),
      opts.targetUserId.toString(),
      now.toISOString()
    ),
    grantedByUserId: opts.actorUserId,
    note: opts.note ?? null,
    now,
  });
}

/** 兼容旧调用: 给路由用的 402 响应体 */
export function billingErrorBody(err: BillingError) {
  return { error: err.message, code: err.code };
}

export { sql };
