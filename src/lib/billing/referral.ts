// ============================================
// 推荐码 + 推荐奖励规则 (纯函数部分, 无 DB)
// ============================================
// ADR-0012 §6 + docs/membership-billing-draft.md §2.3
//
// 主人拍板 (2026-09-19 ask_user 0ecdc2ab):
//   - 每人固定 6 位推荐码; 注册时可选填; 双方各得 15 天会员权益
//   - 封顶: **月 30 次 + 累计 360 次** (D22)
//   - 发奖时机: **被推荐人成为加盟者后**发推荐人奖励 (D23);
//     被推荐人自己的 15 天在其"注册并验证手机号"后发 (REFEREE_GRANT_ON_VERIFY)
//
// ⚠️ 合规: 推荐奖励只能是**服务权益 (天数)** —— 不可提现/转让/折现;
//    只有一层 (无二级); 与加盟层级/等级/价格无关 (见 ADR-0012 §3 红线)
//
// 纯函数放这里, DB 操作在 entitlements.ts —— 规则可单测, 不依赖数据库

/** 推荐码字符集: 去掉 0/O/1/I/L 这些抄错就会错的字符 */
export const REFERRAL_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const REFERRAL_CODE_LENGTH = 6;

/** 双向各得的天数 */
export const REFERRAL_GRANT_DAYS = 15;

/**
 * 封顶 (主人 D22 定: 月 30 / 累计 360)
 * ⚠️ agent 保留意见: 封顶越宽, "以发展人员数量计酬"的外观越接近《禁止传销条例》关注点。
 *    守住"只送服务权益 + 仅一层 + 与层级无关"时风险可控, 但**律师复core这一条尤其要看**。
 *    做成常量 = 随时能收紧, 不用改逻辑。
 */
export const REFERRAL_MONTHLY_CAP = 30;
export const REFERRAL_TOTAL_CAP = 360;

/** 被推荐人侧发奖时机 (待主人确认口径; 先按"注册+验证"给新用户即时反馈) */
export const REFEREE_GRANT_ON_VERIFY = true;

/**
 * **推荐码只能在"注册时"填** (主人 2026-09-19):
 *   入口: 建号路径 (管理员用 scripts/import-users.ts 导入 / 未来的注册页)
 *   约束: 账号创建超过这个小时数就不收码了 —— 否则老用户事后随便补一个码,
 *         等于"人人可白拿 15 天", 也会让"只有注册时能填"这条规则形同虚设。
 */
export const REFERRAL_CLAIM_WINDOW_HOURS = 24;

/** 账号创建时间是否还在"可填推荐码"的窗口内 */
export function isWithinClaimWindow(
  createdAt: Date | null | undefined,
  now: Date = new Date()
): boolean {
  if (!createdAt) return false; // 拿不到创建时间 = 不敢放行 (宁严勿松)
  const ageHours = (now.getTime() - createdAt.getTime()) / 36e5;
  return ageHours >= 0 && ageHours <= REFERRAL_CLAIM_WINDOW_HOURS;
}

/** 归一化用户输入 (大小写不敏感, 去空格/连字符) */
export function normalizeReferralCode(raw: string | null | undefined): string {
  if (!raw) return "";
  return raw
    .toUpperCase()
    .replace(/[\s\-_]/g, "")
    .replace(/[^A-Z0-9]/g, "");
}

/** 码是否"形状合法" (不查库) */
export function isValidReferralCodeShape(raw: string | null | undefined): boolean {
  const c = normalizeReferralCode(raw);
  if (c.length !== REFERRAL_CODE_LENGTH) return false;
  for (const ch of c) {
    if (!REFERRAL_ALPHABET.includes(ch)) return false;
  }
  return true;
}

/** 生成一个随机码 (调用方负责查重: 唯一索引兜底 + 失败重试) */
export function generateReferralCode(rand: () => number = Math.random): string {
  let out = "";
  for (let i = 0; i < REFERRAL_CODE_LENGTH; i++) {
    out += REFERRAL_ALPHABET[Math.floor(rand() * REFERRAL_ALPHABET.length)];
  }
  return out;
}

/** 本月已用 + 累计已用 → 还能不能再发 */
export interface ReferralQuotaInput {
  /** 本自然月已成功发出的推荐奖励次数 */
  usedThisMonth: number;
  /** 累计已成功发出的推荐奖励次数 */
  usedTotal: number;
}

export type ReferralQuotaResult =
  | { ok: true; remainingThisMonth: number; remainingTotal: number }
  | { ok: false; reason: string };

export function checkReferralQuota(input: ReferralQuotaInput): ReferralQuotaResult {
  const { usedThisMonth, usedTotal } = input;
  if (usedTotal >= REFERRAL_TOTAL_CAP) {
    return {
      ok: false,
      reason: `累计推荐奖励已达上限 (${REFERRAL_TOTAL_CAP} 次)`,
    };
  }
  if (usedThisMonth >= REFERRAL_MONTHLY_CAP) {
    return {
      ok: false,
      reason: `本月推荐奖励已达上限 (${REFERRAL_MONTHLY_CAP} 次), 下个月继续`,
    };
  }
  return {
    ok: true,
    remainingThisMonth: REFERRAL_MONTHLY_CAP - usedThisMonth,
    remainingTotal: REFERRAL_TOTAL_CAP - usedTotal,
  };
}

/** 能不能把 A 推荐给 B (反作弊的第一道, 纯规则部分) */
export interface ReferralEligibilityInput {
  referrerUserId: string | null;
  refereeUserId: string;
  /** 被推荐人手机号 hash (查重: 不能是推荐人自己的号) */
  refereePhoneHash?: string | null;
  referrerPhoneHash?: string | null;
  /** 被推荐人注册 IP / 推荐人最近登录 IP (相同 = 疑似自己刷) */
  refereeIp?: string | null;
  referrerIp?: string | null;
}

export type ReferralEligibility =
  | { ok: true }
  | { ok: false; reason: string };

export function checkReferralEligibility(
  input: ReferralEligibilityInput
): ReferralEligibility {
  const {
    referrerUserId,
    refereeUserId,
    refereePhoneHash,
    referrerPhoneHash,
    refereeIp,
    referrerIp,
  } = input;

  if (!referrerUserId) return { ok: false, reason: "推荐码不存在" };
  if (referrerUserId === refereeUserId) {
    return { ok: false, reason: "不能推荐自己" };
  }
  if (
    refereePhoneHash &&
    referrerPhoneHash &&
    refereePhoneHash === referrerPhoneHash
  ) {
    return { ok: false, reason: "不能用自己的另一个账号刷推荐" };
  }
  if (refereeIp && referrerIp && refereeIp === referrerIp) {
    // 同一个出口 IP: 家庭/公司同网很常见 → 不当场拒, 标记待人工审
    return {
      ok: false,
      reason: "与推荐人同一网络环境, 奖励待人工审核",
    };
  }
  return { ok: true };
}

/** 权益叠加: 顺延, 不吞掉已付时间 */
export function addDays(
  base: Date | null | undefined,
  days: number,
  now: Date = new Date()
): Date {
  const from = base && base.getTime() > now.getTime() ? base : now;
  return new Date(from.getTime() + days * 24 * 60 * 60 * 1000);
}

/** 会员判定 (唯一真相: member_until > now) */
export function isMemberUntil(
  memberUntil: Date | null | undefined,
  now: Date = new Date()
): boolean {
  return !!memberUntil && memberUntil.getTime() > now.getTime();
}

/** 幂等键 (同一次推荐/同一笔手工操作只发一次) */
export function grantIdempotencyKey(
  kind: string,
  ...parts: (string | number)[]
): string {
  return [kind, ...parts].join(":");
}
