// ============================================
// B1 自助注册 (凭推荐码) + 推荐人确认
// ============================================
// 主人 2026-09-20 拍板: B1 —— 新用户填推荐码自助注册, **推荐人点"这是我朋友"才生效**
//
// 为什么不是开放注册:
//   邀请制是产品定位 (只让认识的人进来)。推荐码 = 注册凭证 → 没码注册不了,
//   等于每个新人都有人背书 —— 这比"完全开放 + 事后清理"便宜得多。
//
// 为什么还要"推荐人确认"这一关:
//   推荐码是**长期固定的 6 位码**, 一旦被转发到群里, 陌生人也能拿去注册。
//   有确认这一关 → 刷号的人拿不到任何权益; 推荐人要为自己的码负责。
//
// 主人 2026-09-20 补充要求: 「账号/用户名提醒用户填真实姓名，真实手机号」
//   → 前端字段带明确提示; **服务端也强校验** (姓名 2-20 字且不是纯数字/符号; 手机号 11 位真实格式)
//   → 手机号 = 登录账号 = 唯一 (phone_hash 唯一索引兜底)
//   理由: 后台要靠真实姓名+手机号核对"这个人是谁", 假名会让人工审核形同虚设

import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { user, referralReward, referralCode } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import { hashPassword, isValidPassword, PASSWORD_POLICY_MESSAGE } from "@/lib/auth/password";
import { BillingError, grantDays } from "@/lib/billing/entitlements";
import {
  checkReferralQuota,
  grantIdempotencyKey,
  isValidReferralCodeShape,
  normalizeReferralCode,
  REFERRAL_CLAIM_WINDOW_HOURS,
  REFERRAL_GRANT_DAYS,
} from "@/lib/billing/referral";
import { referralUsage } from "@/lib/billing/entitlements";

/** 姓名规则: 2-20 字符, 至少含一个中文或字母, 不能是纯数字/符号 */
export const NAME_RULE_HINT = "请填真实姓名 (2-20 个字, 至少有中文或字母)";

export function validateRealName(raw: string): { ok: true; name: string } | { ok: false; reason: string } {
  const name = raw.trim().replace(/\s+/g, "");
  if (name.length < 2 || name.length > 20) {
    return { ok: false, reason: "姓名请填 2-20 个字 (要填真名, 管理员要用它核对身份)" };
  }
  if (!/[\u4e00-\u9fa5A-Za-z]/.test(name)) {
    return { ok: false, reason: "姓名里要有中文或字母 (别只填数字/符号)" };
  }
  if (/^[\d\s\-+()]+$/.test(name)) {
    return { ok: false, reason: "姓名不能是纯数字" };
  }
  return { ok: true, name };
}

/** 手机号规则 (与全仓一致: 1[3-9] 开头 11 位) */
export const PHONE_RULE_HINT = "请填真实手机号 (11 位, 就是你的登录账号)";

export function validateRealPhone(raw: string): { ok: true; phone: string } | { ok: false; reason: string } {
  const phone = raw.replace(/\D/g, "");
  if (!/^1[3-9]\d{9}$/.test(phone)) {
    return { ok: false, reason: "手机号格式不对 (请填真实手机号, 11 位)" };
  }
  return { ok: true, phone };
}

export interface SignupResult {
  userId: bigint;
  /** 登录账号 (= 手机号) */
  username: string;
  /** 需要推荐人去确认才发 15 天 */
  needsReferrerConfirmation: true;
  message: string;
}

/**
 * 凭推荐码自助注册
 *
 * 流程: 校验(码/姓名/手机号/密码/唯一) → 建 user → 建 referral_reward(pending)
 *       → **不发权益** (等推荐人确认) → 客户端拿手机号+密码走正常登录
 *
 * 返回给客户端的话术要明确"等推荐人确认", 否则新人会以为没生效。
 */
export async function registerWithReferral(opts: {
  rawCode: string;
  rawName: string;
  rawPhone: string;
  password: string;
  ip?: string | null;
}): Promise<SignupResult> {
  const code = normalizeReferralCode(opts.rawCode);
  if (!isValidReferralCodeShape(code)) {
    throw new BillingError(400, "BAD_CODE", "推荐码格式不对 (6 位字母数字, 找朋友核对一下)");
  }

  const nameCheck = validateRealName(opts.rawName);
  if (!nameCheck.ok) throw new BillingError(400, "BAD_NAME", nameCheck.reason);

  const phoneCheck = validateRealPhone(opts.rawPhone);
  if (!phoneCheck.ok) throw new BillingError(400, "BAD_PHONE", phoneCheck.reason);

  if (!isValidPassword(opts.password)) {
    throw new BillingError(400, "BAD_PASSWORD", PASSWORD_POLICY_MESSAGE);
  }

  const phone = phoneCheck.phone;
  const phoneHash = hashForLookup(phone);

  // 手机号唯一 (一人一号; 也是登录账号)
  const [dup] = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.phoneHash, phoneHash))
    .limit(1);
  if (dup) {
    throw new BillingError(409, "PHONE_TAKEN", "这个手机号已经注册过了, 直接用手机号登录即可");
  }

  // 推荐人 (码的主人)
  const [owner] = await db
    .select({ userId: referralCode.userId })
    .from(referralCode)
    .where(eq(referralCode.code, code))
    .limit(1);
  if (!owner) {
    throw new BillingError(400, "CODE_NOT_FOUND", "这个推荐码不存在, 找推荐人重新核对");
  }

  // 封顶: 待确认也算 (否则一个码被批量刷→几百个 pending 挂在推荐人那里)
  const usage = await referralUsage(owner.userId);
  const quota = checkReferralQuota(usage);
  if (!quota.ok) {
    throw new BillingError(429, "QUOTA_EXCEEDED", quota.reason);
  }

  const [created] = await db
    .insert(user)
    .values({
      name: nameCheck.name,
      role: "sales",
      isActive: true,
      phoneEncrypted: encryptField(phone),
      phoneHash,
      username: phone, // 登录账号 = 手机号 (跟 import-users 一致)
      passwordHash: hashPassword(opts.password),
    })
    .returning({ id: user.id, username: user.username });

  await db.insert(referralReward).values({
    referrerUserId: owner.userId,
    refereeUserId: created.id,
    code,
    status: "pending",
    refereePhoneHash: phoneHash,
    refereeSignupIp: opts.ip ?? null,
  });

  return {
    userId: created.id,
    username: created.username ?? phone,
    needsReferrerConfirmation: true,
    message: `注册成功! 请让推荐人 (${code}) 在 App 里点「这是我朋友」确认, 确认后你会得到 ${REFERRAL_GRANT_DAYS} 天会员`,
  };
}

// ============================================
// 推荐人确认 / 驳回
// ============================================

/** 推荐人待确认 / 已确认列表 (「我的」页"好友"入口用) */
export async function listMyReferrals(
  referrerUserId: bigint
): Promise<Array<{
  id: string;
  name: string;
  phoneMasked: string;
  status: string;
  createdAt: string;
}>> {
  const rows = await db
    .select({
      id: referralReward.id,
      status: referralReward.status,
      createdAt: referralReward.createdAt,
      name: user.name,
      phoneEncrypted: user.phoneEncrypted,
    })
    .from(referralReward)
    .innerJoin(user, eq(user.id, referralReward.refereeUserId))
    .where(eq(referralReward.referrerUserId, referrerUserId))
    .orderBy(referralReward.createdAt);

  const { decryptField } = await import("@/lib/crypto/field");
  const { maskPhone } = await import("@/lib/utils");

  return rows.map((r) => ({
    id: r.id.toString(),
    name: r.name,
    phoneMasked: maskPhone(decryptField(r.phoneEncrypted)),
    status: r.status,
    createdAt: r.createdAt.toISOString(),
  }));
}

/**
 * 推荐人确认「这是我朋友」
 *
 * 确认后才给**新用户**发 15 天 (幂等); **推荐人自己**的 15 天仍等被推荐人成为加盟者 (D23)
 */
export async function confirmReferral(opts: {
  referrerUserId: bigint;
  rewardId: bigint;
  now?: Date;
}): Promise<{ ok: boolean; reason: string; grantedDays: number }> {
  const now = opts.now ?? new Date();
  const [row] = await db
    .select()
    .from(referralReward)
    .where(eq(referralReward.id, opts.rewardId))
    .limit(1);

  if (!row) throw new BillingError(404, "NOT_FOUND", "这条推荐不存在");
  if (row.referrerUserId !== opts.referrerUserId) {
    throw new BillingError(403, "NOT_MINE", "这条推荐不是你的");
  }
  if (row.status === "confirmed" || row.status === "rewarded") {
    return { ok: true, reason: "之前已经确认过了", grantedDays: 0 };
  }
  if (row.status !== "pending") {
    throw new BillingError(409, "BAD_STATUS", `这条推荐状态是 ${row.status}, 不能再确认`);
  }

  const grant = await grantDays({
    userId: row.refereeUserId,
    days: REFERRAL_GRANT_DAYS,
    reason: "referral_referee",
    idempotencyKey: grantIdempotencyKey(
      "referral_referee",
      row.referrerUserId.toString(),
      row.refereeUserId.toString()
    ),
    note: `推荐人确认 (码 ${row.code})`,
    now,
  });

  await db
    .update(referralReward)
    .set({ status: "confirmed", confirmedAt: now })
    .where(eq(referralReward.id, opts.rewardId));

  return {
    ok: true,
    reason: grant.granted ? "已确认, 对方拿到 15 天会员" : "之前已经发过了",
    grantedDays: grant.granted ? REFERRAL_GRANT_DAYS : 0,
  };
}

/** 推荐人否认 (不是我的朋友 / 不认识) → 不发任何权益 */
export async function rejectReferral(opts: {
  referrerUserId: bigint;
  rewardId: bigint;
  reason?: string | null;
  now?: Date;
}): Promise<{ ok: boolean }> {
  const now = opts.now ?? new Date();
  const [row] = await db
    .select()
    .from(referralReward)
    .where(eq(referralReward.id, opts.rewardId))
    .limit(1);

  if (!row) throw new BillingError(404, "NOT_FOUND", "这条推荐不存在");
  if (row.referrerUserId !== opts.referrerUserId) {
    throw new BillingError(403, "NOT_MINE", "这条推荐不是你的");
  }
  if (row.status !== "pending") {
    throw new BillingError(409, "BAD_STATUS", "只有待确认的推荐能驳回");
  }

  await db
    .update(referralReward)
    .set({
      status: "rejected",
      rejectedAt: now,
      rejectReason: opts.reason?.slice(0, 200) ?? "推荐人否认",
    })
    .where(eq(referralReward.id, opts.rewardId));

  return { ok: true };
}

/** 老入口 (管理员建号时填码) 的语义保持: 那批直接发 (管理员是可信的) */
export const SIGNUP_WINDOW_HOURS_NOTE = `推荐码自助注册不受 ${REFERRAL_CLAIM_WINDOW_HOURS}h 窗口限制 (注册即填)`;
