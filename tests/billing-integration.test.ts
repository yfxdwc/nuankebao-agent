// 会员/推荐 集成测试 (真 DB, 自带清理 —— 不 TRUNCATE 别人的数据)
//
// 覆盖 S0 的核心闭环:
//   1. 新用户填推荐码 → 被推荐人立刻得 15 天会员
//   2. 被推荐人成为加盟者 → 推荐人得 15 天 (D23: 只在成为加盟者后发)
//   3. 幂等: 重复触发不重复送天数
//   4. 反作弊: 自己推荐自己 / 同一手机号 被拒
//   5. 管理员手工开通 (S0 收款后入口)
//
// ⚠ 本文件会往真 DB 写测试数据 (前缀 billing-test-), 结束时按 id 精确删除

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { and, eq, inArray } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  billingConfig,
  customer,
  entitlementGrant,
  franchisee,
  manualPaymentRequest,
  membership,
  referralCode,
  referralReward,
  user,
} from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import {
  adminGrant,
  claimReferralCode,
  ensureReferralCode,
  getMembershipView,
  rewardReferrerOnFranchisee,
} from "@/lib/billing/entitlements";
import { createFranchisee } from "@/lib/db/queries/franchisee";
import {
  decideManualPayment,
  getManualPayInfo,
  listManualPaymentsForAdmin,
  setManualPayConfig,
  submitManualPayment,
} from "@/lib/billing/manual-pay";

const TAG = `billing-test-${Date.now()}`;
const phoneA = "13900002001"; // 推荐人
const phoneB = "13900002002"; // 被推荐人
const phoneC = "13900002003"; // 手工开通对象

let userA: bigint;
let userB: bigint;
let userC: bigint;
let codeA: string;

async function mkUser(name: string, phone: string): Promise<bigint> {
  const [row] = await db
    .insert(user)
    .values({
      name,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      role: "sales",
    })
    .returning({ id: user.id });
  return row.id;
}

beforeAll(async () => {
  userA = await mkUser(`${TAG}-推荐人`, phoneA);
  userB = await mkUser(`${TAG}-被推荐人`, phoneB);
  userC = await mkUser(`${TAG}-手工开通`, phoneC);
  codeA = await ensureReferralCode(userA);
});

afterAll(async () => {
  // 精确清理 (只删本测试造的数据)
  const uids = [userA, userB, userC].filter((v) => typeof v === "bigint");
  if (uids.length) {
    await db.delete(entitlementGrant).where(inArray(entitlementGrant.userId, uids));
    await db.delete(membership).where(inArray(membership.userId, uids));
    await db
      .delete(referralReward)
      .where(
        and(
          inArray(referralReward.referrerUserId, uids),
          inArray(referralReward.refereeUserId, uids)
        )
      );
    await db.delete(referralCode).where(inArray(referralCode.userId, uids));
    await db
      .delete(manualPaymentRequest)
      .where(inArray(manualPaymentRequest.userId, uids));
    await db
      .delete(billingConfig)
      .where(inArray(billingConfig.key, ["manual_wechat_qr_url", "manual_payee_name"]));
    // 加盟商/客户 (本测试造的, 按手机号 hash 删)
    const hashes = [phoneA, phoneB, phoneC].map((p) => hashForLookup(p));
    await db.delete(franchisee).where(inArray(franchisee.phoneHash, hashes));
    await db.delete(customer).where(inArray(customer.phoneHash, hashes));
    await db.delete(user).where(inArray(user.id, uids));
  }
});

describe("会员/推荐 S0 闭环", () => {
  it("新用户注册: 还没有会员", async () => {
    const view = await getMembershipView(userB);
    expect(view.isMember).toBe(false);
    expect(view.memberUntil).toBe(null);
    expect(view.planCode).toBe("free");
    expect(view.features).toEqual([]);
  });

  it("填推荐码: 被推荐人立刻得 15 天, 推荐人先 pending (等他成为加盟者)", async () => {
    const r = await claimReferralCode({
      refereeUserId: userB,
      rawCode: codeA,
    });
    expect(r.accepted).toBe(true);
    expect(r.refereeGranted).toBe(true);
    expect(r.referrerPending).toBe(true);

    const refereeView = await getMembershipView(userB);
    expect(refereeView.isMember).toBe(true);
    expect(refereeView.features.length).toBe(9);

    // 推荐人还没拿到
    const referrerView = await getMembershipView(userA);
    expect(referrerView.isMember).toBe(false);
    expect(referrerView.referralCode).toBe(codeA);
  });

  it("反作弊: 推荐码格式不对 / 不存在 / 自己推荐自己 → 都拒", async () => {
    const bad = await claimReferralCode({ refereeUserId: userC, rawCode: "ABC" });
    expect(bad.accepted).toBe(false);

    const missing = await claimReferralCode({
      refereeUserId: userC,
      rawCode: "ZZZZZZ",
    });
    expect(missing.accepted).toBe(false);

    const self = await claimReferralCode({ refereeUserId: userA, rawCode: codeA });
    expect(self.accepted).toBe(false);
    expect(self.reason).toContain("自己");
  });

  it("一人只能被推荐一次 (第二次填别的码 → 拒)", async () => {
    const again = await claimReferralCode({
      refereeUserId: userB,
      rawCode: codeA,
    });
    expect(again.accepted).toBe(false);
  });

  it("被推荐人成为加盟者 → 推荐人拿到 15 天 (D23)", async () => {
    await createFranchisee(
      { name: `${TAG}-加盟`, phone: phoneB },
      { userId: userA },
      userA
    );

    const referrerView = await getMembershipView(userA);
    expect(referrerView.isMember).toBe(true);

    const [reward] = await db
      .select()
      .from(referralReward)
      .where(
        and(
          eq(referralReward.referrerUserId, userA),
          eq(referralReward.refereeUserId, userB)
        )
      );
    expect(reward.status).toBe("rewarded");
    expect(reward.rewardedAt).not.toBe(null);
  });

  it("幂等: 同一个加盟商事件再触发一次, 不再发天数", async () => {
    const before = (await getMembershipView(userA)).memberUntil;
    const again = await rewardReferrerOnFranchisee({
      newFranchiseePhoneHash: hashForLookup(phoneB),
    });
    const after = (await getMembershipView(userA)).memberUntil;
    expect(after).toBe(before);
    expect(again.rewarded).toBe(0);
  });

  it("管理员手工开通 (S0 收款后入口): 免费用户 → 会员", async () => {
    const before = await getMembershipView(userC);
    expect(before.isMember).toBe(false);

    const r = await adminGrant({
      targetUserId: userC,
      days: 30,
      actorUserId: userA,
      note: "测试: 个体户收款核销",
    });
    expect(r.granted).toBe(true);

    const after = await getMembershipView(userC);
    expect(after.isMember).toBe(true);
    expect(after.planCode).toBe("member");
    expect(after.features.length).toBe(9);
  });
});

describe("人工收款 (内测: 个人微信收款码 + 管理员核销)", () => {
  it("收款信息有默认值, 且商品是 ¥69/月 (30 天)", async () => {
    const info = await getManualPayInfo();
    expect(info.enabled).toBe(true);
    expect(info.qrUrl).toContain("/payment/"); // 还没上传 → 静态兜底
    expect(info.isFallbackQr).toBe(true);
    const monthly = info.products.find((p) => p.planCode === "monthly")!;
    expect(monthly.amountCents).toBe(6900);
    expect(monthly.days).toBe(30);
  });

  it("管理员设置收款码 → 用户看到的就是上传的那张 (不再是兜底)", async () => {
    await setManualPayConfig({
      actorUserId: userA,
      qrUrl: "/uploads/fake-qr.png",
      payeeName: "测试收款人",
    });
    const info = await getManualPayInfo();
    expect(info.qrUrl).toBe("/uploads/fake-qr.png");
    expect(info.isFallbackQr).toBe(false);
    expect(info.payeeName).toBe("测试收款人");
  });

  it("用户提交「我已支付」→ 进待审列表 → 管理员通过 → 会员立刻生效", async () => {
    const req = await submitManualPayment({
      userId: userC,
      planCode: "monthly",
      payerNote: "微信昵称: 小C",
    });
    expect(req.status).toBe("pending");
    expect(req.amountCents).toBe(6900);

    const pending = await listManualPaymentsForAdmin({ status: "pending" });
    expect(pending.some((r) => r.id === req.id)).toBe(true);

    const before = await getMembershipView(userC);
    const startUntil = new Date(before.memberUntil ?? Date.now());

    const decided = await decideManualPayment({
      requestId: req.id,
      actorUserId: userA,
      decision: "approve",
    });
    expect(decided.status).toBe("approved");
    expect(decided.grantedDays).toBe(30);

    const after = await getMembershipView(userC);
    expect(after.isMember).toBe(true);
    // 30 天 (允许几秒误差)
    const diffDays = Math.round(
      (new Date(after.memberUntil!).getTime() - startUntil.getTime()) / 86400000
    );
    expect(diffDays).toBe(30);
  });

  it("重复提交被拒 (已经有 pending) / 重复核销被拒 (已经处理过)", async () => {
    // 上面那条已经 approved → 再提一条新的 pending
    const req2 = await submitManualPayment({ userId: userB, planCode: "monthly" });
    await expect(
      submitManualPayment({ userId: userB, planCode: "monthly" })
    ).rejects.toThrow();

    await decideManualPayment({
      requestId: req2.id,
      actorUserId: userA,
      decision: "reject",
      rejectReason: "没查到这笔到账",
    });
    await expect(
      decideManualPayment({
        requestId: req2.id,
        actorUserId: userA,
        decision: "approve",
      })
    ).rejects.toThrow();
  });

  it("驳回不给天数 (被推荐人之外的人也不会白拿会员)", async () => {
    const view = await getMembershipView(userB);
    expect(view.isMember).toBe(false); // userB 只被驳回, 没有会员
  });
});
