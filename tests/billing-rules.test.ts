// 会员/推荐规则单测 (纯函数, 无 DB)
// 关注点: ①功能清单不能漏 ②推荐码形状 ③封顶 ④顺延叠加 ⑤反作弊判定
import { describe, it, expect } from "vitest";
import {
  ALL_FEATURES,
  FEATURES,
  FREE_FEATURES,
  canUseFeature,
  featuresFor,
  isFeatureKey,
} from "@/lib/billing/features";
import {
  REFERRAL_ALPHABET,
  REFERRAL_CODE_LENGTH,
  REFERRAL_GRANT_DAYS,
  REFERRAL_MONTHLY_CAP,
  REFERRAL_TOTAL_CAP,
  addDays,
  checkReferralEligibility,
  checkReferralQuota,
  generateReferralCode,
  grantIdempotencyKey,
  isMemberUntil,
  isValidReferralCodeShape,
  normalizeReferralCode,
} from "@/lib/billing/referral";

describe("会员功能清单 (主人 2026-09-19 口述 9 项 → P5 合并后 7 项)", () => {
  it("正好 7 项, 且 key 不重复", () => {
    // P5 (主人 2026-09-23 拍「AI 4 卡合并成 1 次调用, 单个 ai.insight key」):
    //   ai.follow_up + ai.customer_profile + ai.effect_analysis (3 项)
    //     → ai.insight (1 项)
    //   能力没减 (三段内容仍全在), 只是从 3 个会员条目/3 次 AI 调用 变成 1 个/1 次。
    //   9 - 3 + 1 = 7
    expect(ALL_FEATURES.length).toBe(7);
    expect(new Set(ALL_FEATURES).size).toBe(7);
  });

  it("7 项都对应主人点名的功能", () => {
    expect(ALL_FEATURES).toEqual(
      expect.arrayContaining([
        "ai.assistant", // AI助手
        "ai.insight", // AI洞察 (跟进建议 + 客户画像 + 效果分析, P5 合并)
        "salon.create", // 沙龙发起
        "ai.repurchase", // 跟进推荐 (复购预测)
        "crm.interaction", // 互动记录
        "crm.birthday_reminder", // 生日提醒
        "media.upload", // 图片上传
      ])
    );
  });

  it("免费档: 7 项全部不可用; 会员档: 7 项全可用", () => {
    expect(FREE_FEATURES).toEqual([]);
    for (const key of ALL_FEATURES) {
      expect(canUseFeature(false, key)).toBe(false);
      expect(canUseFeature(true, key)).toBe(true);
    }
  });

  it("featuresFor: 免费空集 / 会员全集", () => {
    expect(featuresFor(false)).toEqual([]);
    expect(featuresFor(true)).toEqual(ALL_FEATURES);
  });

  it("写错的 key 一律拒绝 (不静默放行 → 免得白送功能)", () => {
    expect(isFeatureKey("ai.nope")).toBe(false);
    // @ts-expect-error 故意传非法 key
    expect(canUseFeature(true, "ai.nope")).toBe(false);
  });

  it("常量表与清单一致 (改 features.ts 不能漏改 FEATURES 对象)", () => {
    expect(Object.values(FEATURES).sort()).toEqual([...ALL_FEATURES].sort());
  });
});

describe("推荐码形状", () => {
  it("字符集去掉易混字符 0 O 1 I L", () => {
    for (const ch of ["0", "O", "1", "I", "L"]) {
      expect(REFERRAL_ALPHABET.includes(ch)).toBe(false);
    }
  });

  it("生成的码: 6 位 + 全在字符集内", () => {
    for (let i = 0; i < 200; i++) {
      const code = generateReferralCode();
      expect(code).toHaveLength(REFERRAL_CODE_LENGTH);
      expect(isValidReferralCodeShape(code)).toBe(true);
    }
  });

  it("归一化: 小写 / 空格 / 连字符 都能救回来", () => {
    expect(normalizeReferralCode(" ab-cd 23 ")).toBe("ABCD23");
    expect(normalizeReferralCode("abcdef")).toBe("ABCDEF");
    expect(normalizeReferralCode(null)).toBe("");
  });

  it("形状校验: 长度不对 / 含易混字符 / 空 → 拒", () => {
    expect(isValidReferralCodeShape("ABCDEF")).toBe(true);
    expect(isValidReferralCodeShape("ABCDE")).toBe(false);
    expect(isValidReferralCodeShape("ABCDEFG")).toBe(false);
    expect(isValidReferralCodeShape("ABCDE0")).toBe(false); // 0 不在字符集
    expect(isValidReferralCodeShape("")).toBe(false);
    expect(isValidReferralCodeShape(null)).toBe(false);
  });
});

describe("推荐奖励封顶 (主人 D22: 月 30 / 累计 360)", () => {
  it("常量与主人拍板一致", () => {
    expect(REFERRAL_MONTHLY_CAP).toBe(30);
    expect(REFERRAL_TOTAL_CAP).toBe(360);
    expect(REFERRAL_GRANT_DAYS).toBe(15);
  });

  it("没到上限 → 放行 + 返回剩余名额", () => {
    const r = checkReferralQuota({ usedThisMonth: 0, usedTotal: 0 });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.remainingThisMonth).toBe(30);
      expect(r.remainingTotal).toBe(360);
    }
  });

  it("本月打满 → 拒 (提示下个月继续)", () => {
    const r = checkReferralQuota({ usedThisMonth: 30, usedTotal: 30 });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toContain("本月");
  });

  it("累计打满 → 拒 (优先于月度判断)", () => {
    const r = checkReferralQuota({ usedThisMonth: 0, usedTotal: 360 });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toContain("累计");
  });
});

describe("反作弊判定", () => {
  it("不能推荐自己", () => {
    const r = checkReferralEligibility({
      referrerUserId: "7",
      refereeUserId: "7",
    });
    expect(r.ok).toBe(false);
  });

  it("同一手机号 hash (自己的另一个号) → 拒", () => {
    const r = checkReferralEligibility({
      referrerUserId: "7",
      refereeUserId: "8",
      referrerPhoneHash: "hashA",
      refereePhoneHash: "hashA",
    });
    expect(r.ok).toBe(false);
  });

  it("同一 IP → 不当场拒, 但标记待人工审", () => {
    const r = checkReferralEligibility({
      referrerUserId: "7",
      refereeUserId: "8",
      referrerIp: "1.2.3.4",
      refereeIp: "1.2.3.4",
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toContain("人工");
  });

  it("正常推荐 → 放行", () => {
    expect(
      checkReferralEligibility({
        referrerUserId: "7",
        refereeUserId: "8",
        referrerPhoneHash: "hashA",
        refereePhoneHash: "hashB",
        referrerIp: "1.1.1.1",
        refereeIp: "2.2.2.2",
      }).ok
    ).toBe(true);
  });
});

describe("权益叠加与判定", () => {
  const now = new Date("2026-09-19T00:00:00Z");

  it("从来没有会员 → 从今天起算 N 天", () => {
    const until = addDays(null, 15, now);
    expect(until.toISOString()).toBe("2026-10-04T00:00:00.000Z");
  });

  it("还有会员 → 顺延 (不吞掉已付时间)", () => {
    const current = new Date("2026-10-01T00:00:00Z");
    const until = addDays(current, 15, now);
    expect(until.toISOString()).toBe("2026-10-16T00:00:00.000Z");
  });

  it("已过期 → 从今天重新算 (不补回两段时间的重叠)", () => {
    const expired = new Date("2026-09-01T00:00:00Z");
    const until = addDays(expired, 15, now);
    expect(until.toISOString()).toBe("2026-10-04T00:00:00.000Z");
  });

  it("isMemberUntil: 未来=会员 / 过去=不是 / null=不是", () => {
    expect(isMemberUntil(new Date("2026-10-01T00:00:00Z"), now)).toBe(true);
    expect(isMemberUntil(new Date("2026-09-01T00:00:00Z"), now)).toBe(false);
    expect(isMemberUntil(null, now)).toBe(false);
    expect(isMemberUntil(undefined, now)).toBe(false);
  });

  it("幂等键: 同一对推荐人/被推荐人生成同一个键", () => {
    expect(grantIdempotencyKey("referral_referrer", 7, 8)).toBe(
      grantIdempotencyKey("referral_referrer", 7, 8)
    );
    expect(grantIdempotencyKey("referral_referrer", 7, 8)).not.toBe(
      grantIdempotencyKey("referral_referee", 7, 8)
    );
  });
});
