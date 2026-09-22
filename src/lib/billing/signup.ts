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

import { and, eq, isNull } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  user as userTable,
  customer,
  referralReward,
  referralCode,
} from "@/lib/db/schema";
import { withAuditContext } from "@/lib/audit/context";
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
 * 流程: 校验(码/姓名/手机号/密码/唯一) → 建 user + **建客户档案** → 建 referral_reward(pending)
 *       → **不发权益** (等推荐人确认) → 客户端拿手机号+密码走正常登录
 *
 * 客户档案 (主人 2026-09-19/20 拍):
 *   - 「建号即强制建档」: 新用户的客户档案同事务建好 (is_seed=false → 列表里就是**普通客户**)
 *   - 「提供推荐码的用户, 其客户列表自动多出一个普通客户」:
 *     customer.referrer_id = **推荐人的客户档案** (有则挂; 推荐人还没档案就先空着, 不阻塞注册)
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
    .select({ id: userTable.id })
    .from(userTable)
    .where(eq(userTable.phoneHash, phoneHash))
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

  // 账号 + 客户档案 同一事务 (主人 2026-09-19 拍「建号即强制建档」)
  const created = await withAuditContext(
    { userId: owner.userId, ipAddress: opts.ip ?? null },
    async (tx) => {
      const [u] = await tx
        .insert(userTable)
        .values({
          name: nameCheck.name,
          role: "sales",
          isActive: true,
          phoneEncrypted: encryptField(phone),
          phoneHash,
          username: phone, // 登录账号 = 手机号 (跟 import-users 一致)
          passwordHash: hashPassword(opts.password),
        })
        .returning({ id: userTable.id, username: userTable.username });

      // 客户档案: 同手机号已有 (例如他早就是客户) → 复用不重复建
      const [existingCustomer] = await tx
        .select({ id: customer.id })
        .from(customer)
        .where(and(eq(customer.phoneHash, phoneHash), isNull(customer.deletedAt)))
        .limit(1);
      if (!existingCustomer) {
        await tx.insert(customer).values({
          name: nameCheck.name,
          phoneEncrypted: encryptField(phone),
          phoneHash,
          isSeed: false,
          // 建档人 = 本人 (自助注册: 档案随她的账号一起产生) —— 审计用
          createdBy: u.id,
          // 归属 = NULL (ADR-0015 Q12, 2026-09-22 拍): 建号**不自动**归属推荐人。
          //   推荐码 = 身份识别 + 奖励凭证, 不表达关系;
          //   推荐人在「我推荐的人」页**显式**加为我的客户 (先到先得, Q15)。
          ownerId: null,
          // ⛔ 不再写 customer.referrer_id (ADR-0015 Q4: 客户图谱"老带新"死链路,
          //   零调用方; "谁带她进来" 的唯一真相源 = referral_reward)
        });
      }
      return u;
    }
  );

  await db.insert(referralReward).values({
    referrerUserId: owner.userId,
    refereeUserId: created.id,
    code,
    status: "pending",
    // 自助注册 = **等推荐人确认**才发权益 (防码被转发后陌生人白嫖)
    source: "self_signup",
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

/** 「我推荐的人」行的归属状态 (ADR-0015 Q11/Q12/Q15, 主人 2026-09-22 拍) */
export type ReferralClaimState =
  | "claimable" // 无归属 → 可加为我的客户
  | "mine" // 已经是我的客户
  | "others" // 已归属别人 (先到先得, 不能抢)
  | "no_profile"; // 对方无客户档案 (admin 豁免建档 Q5)

/** 推荐人待确认 / 已确认列表 (「我的」页"好友"入口用) */
export async function listMyReferrals(
  referrerUserId: bigint
): Promise<Array<{
  id: string;
  name: string;
  phoneMasked: string;
  status: string;
  /** 'admin' | 'self_signup' (见 schema 注释: pending 的两种含义靠它区分) */
  source: string;
  createdAt: string;
  /** 被推荐人的客户档案 id (建号即建档 §6.6; admin 豁免 = null) */
  customerId: string | null;
  /** 能否「加为我的客户」→ Flutter 按钮渲染依据 */
  claimState: ReferralClaimState;
}>> {
  const rows = await db
    .select({
      id: referralReward.id,
      status: referralReward.status,
      source: referralReward.source,
      createdAt: referralReward.createdAt,
      name: userTable.name,
      phoneEncrypted: userTable.phoneEncrypted,
      // 客户档案 (左连接: admin 豁免建档 → customerId = null, 行仍要出现)
      customerId: customer.id,
      ownerId: customer.ownerId,
    })
    .from(referralReward)
    .innerJoin(userTable, eq(userTable.id, referralReward.refereeUserId))
    .leftJoin(
      customer,
      and(
        eq(customer.phoneHash, userTable.phoneHash),
        isNull(customer.deletedAt)
      )
    )
    .where(eq(referralReward.referrerUserId, referrerUserId))
    .orderBy(referralReward.createdAt);

  const { decryptField } = await import("@/lib/crypto/field");
  const { maskPhone } = await import("@/lib/utils");

  return rows.map((r) => ({
    id: r.id.toString(),
    name: r.name,
    phoneMasked: maskPhone(decryptField(r.phoneEncrypted)),
    status: r.status,
    // 'admin' = 管理员代建(已生效, 无需推荐人操作) / 'self_signup' = 等推荐人确认
    source: r.source,
    createdAt: r.createdAt.toISOString(),
    customerId: r.customerId?.toString() ?? null,
    claimState:
      r.customerId == null
        ? "no_profile"
        : r.ownerId == null
          ? "claimable"
          : r.ownerId === referrerUserId
            ? "mine"
            : "others",
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
