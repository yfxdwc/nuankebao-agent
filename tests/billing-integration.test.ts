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
import { and, eq, inArray, sql } from "drizzle-orm";
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
  BillingError,
  claimReferralCode,
  requireFeature,
  ensureReferralCode,
  getMembershipView,
  rewardReferrerOnFranchisee,
} from "@/lib/billing/entitlements";
import { createFranchisee } from "@/lib/db/queries/franchisee";
import {
  confirmReferral,
  registerWithReferral,
  rejectReferral,
} from "@/lib/billing/signup";
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
  // 上次跑失败可能留了测试号 (自助注册用的 3xxx 号段) → 先清干净
  const strayHashes = ["13900003010", "13900003011", "13900003012", "13900003013", "13900003014"].map(
    (p) => hashForLookup(p)
  );
  const stray = await db
    .select({ id: user.id })
    .from(user)
    .where(inArray(user.phoneHash, strayHashes));
  if (stray.length > 0) {
    const ids = stray.map((r) => r.id);
    await db.delete(entitlementGrant).where(inArray(entitlementGrant.userId, ids));
    await db.delete(membership).where(inArray(membership.userId, ids));
    await db.delete(referralReward).where(inArray(referralReward.refereeUserId, ids));
    await db.delete(user).where(inArray(user.id, ids));
  }

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

  it("驳回不给天数 (会员到期时间一点没变)", async () => {
    // ⚠ userB 在推荐用例里已经拿到过 15 天 (被推荐人), 所以这里不能断言"不是会员",
    //   要断言"驳回没有给他加时间"
    const before = (await getMembershipView(userB)).memberUntil;
    const req = await submitManualPayment({ userId: userB, planCode: "monthly" });
    await decideManualPayment({
      requestId: req.id,
      actorUserId: userA,
      decision: "reject",
      rejectReason: "没查到这笔到账",
    });
    const after = (await getMembershipView(userB)).memberUntil;
    expect(after).toBe(before);
  });
});

describe("系统管理员 = 永久会员 (角色即规则, 主人 2026-09-19)", () => {
  it("admin 角色: isMember=true + permanent=true + 9 项功能, 且不写任何权益行", async () => {
    const [admin] = await db
      .insert(user)
      .values({
        name: `${TAG}-管理员`,
        phoneEncrypted: encryptField("13900002009"),
        phoneHash: hashForLookup("13900002009"),
        role: "admin",
      })
      .returning({ id: user.id });

    const view = await getMembershipView(admin.id);
    expect(view.isMember).toBe(true);
    expect(view.permanent).toBe(true);
    expect(view.membershipSource).toBe("admin");
    expect(view.planCode).toBe("admin");
    expect(view.features.length).toBe(9);
    expect(view.memberUntil).toBe(null); // 没有到期日 = 永久

    // 关键: 判定是规则, 不落库 → 没有 membership 行 / 没有 grant 行
    const [m] = await db
      .select()
      .from(membership)
      .where(eq(membership.userId, admin.id));
    expect(m).toBeUndefined();
    const grants = await db
      .select()
      .from(entitlementGrant)
      .where(eq(entitlementGrant.userId, admin.id));
    expect(grants.length).toBe(0);

    // 会员功能直接放行 (不抛 402)
    await expect(
      requireFeature(admin.id, "ai.follow_up")
    ).resolves.toBeUndefined();

    // 清理
    await db.delete(user).where(eq(user.id, admin.id));
  });

  it("升成 admin 后立刻是会员; 降回 sales 就按真实权益算 (不需要补数据)", async () => {
    const [u] = await db
      .insert(user)
      .values({
        name: `${TAG}-临时管理员`,
        phoneEncrypted: encryptField("13900002010"),
        phoneHash: hashForLookup("13900002010"),
        role: "sales",
      })
      .returning({ id: user.id });

    expect((await getMembershipView(u.id)).isMember).toBe(false);

    await db.update(user).set({ role: "admin" }).where(eq(user.id, u.id));
    expect((await getMembershipView(u.id)).isMember).toBe(true);

    await db.update(user).set({ role: "sales" }).where(eq(user.id, u.id));
    expect((await getMembershipView(u.id)).isMember).toBe(false);

    await db.delete(user).where(eq(user.id, u.id));
  });
});

describe("推荐码只能在注册时填 (主人 2026-09-19)", () => {
  it("建号 24h 内可以填; 超过窗口就拒 (防老账号事后补码)", async () => {
    // 新号 (刚建) → 可以填
    const [fresh] = await db
      .insert(user)
      .values({
        name: `${TAG}-新号`,
        phoneEncrypted: encryptField("13900002011"),
        phoneHash: hashForLookup("13900002011"),
        role: "sales",
      })
      .returning({ id: user.id });

    const ok = await claimReferralCode({
      refereeUserId: fresh.id,
      rawCode: codeA,
    });
    expect(ok.accepted).toBe(true);
    expect(ok.refereeGranted).toBe(true);

    // 老号 (把 created_at 往前挪 3 天) → 拒
    const [old] = await db
      .insert(user)
      .values({
        name: `${TAG}-老号`,
        phoneEncrypted: encryptField("13900002012"),
        phoneHash: hashForLookup("13900002012"),
        role: "sales",
      })
      .returning({ id: user.id });
    await db.execute(
      sql`UPDATE "user" SET created_at = NOW() - INTERVAL '3 days' WHERE id = ${old.id}`
    );

    const late = await claimReferralCode({
      refereeUserId: old.id,
      rawCode: codeA,
    });
    expect(late.accepted).toBe(false);
    expect(late.reason).toContain("注册时");

    // 清理
    await db.delete(entitlementGrant).where(inArray(entitlementGrant.userId, [fresh.id, old.id]));
    await db.delete(membership).where(inArray(membership.userId, [fresh.id, old.id]));
    await db
      .delete(referralReward)
      .where(inArray(referralReward.refereeUserId, [fresh.id, old.id]));
    await db.delete(user).where(inArray(user.id, [fresh.id, old.id]));
  });
});

describe("B1 自助注册 (凭推荐码) + 推荐人确认 (主人 2026-09-20)", () => {
  let signupUserId: bigint | null = null;

  afterAll(async () => {
    if (signupUserId) {
      await db.delete(entitlementGrant).where(eq(entitlementGrant.userId, signupUserId));
      await db.delete(membership).where(eq(membership.userId, signupUserId));
      await db
        .delete(referralReward)
        .where(eq(referralReward.refereeUserId, signupUserId));
      await db.delete(user).where(eq(user.id, signupUserId));
    }
  });

  it("姓名/手机号强校验: 纯数字名、假号、短名 都被拒 (主人要求填真实姓名手机号)", async () => {
    const badName = await registerWithReferral({
      rawCode: codeA,
      rawName: "12345678",
      rawPhone: "13900003010",
      password: "Abcd1234",
    }).catch((e) => e);
    expect(badName).toBeInstanceOf(BillingError);
    expect((badName as BillingError).code).toBe("BAD_NAME");

    const badPhone = await registerWithReferral({
      rawCode: codeA,
      rawName: "王秀英",
      rawPhone: "12345",
      password: "Abcd1234",
    }).catch((e) => e);
    expect((badPhone as BillingError).code).toBe("BAD_PHONE");

    const badPwd = await registerWithReferral({
      rawCode: codeA,
      rawName: "王秀英",
      rawPhone: "13900003011",
      password: "123",
    }).catch((e) => e);
    expect((badPwd as BillingError).code).toBe("BAD_PASSWORD");

    const badCode = await registerWithReferral({
      rawCode: "ZZZ",
      rawName: "王秀英",
      rawPhone: "13900003012",
      password: "Abcd1234",
    }).catch((e) => e);
    expect((badCode as BillingError).code).toBe("BAD_CODE");
  });

  it("注册成功: 建号 + 推荐关系 pending, **但还不发权益** (等推荐人确认)", async () => {
    const r = await registerWithReferral({
      rawCode: codeA,
      rawName: "李秀兰",
      rawPhone: "13900003013",
      password: "Abcd1234",
    });
    signupUserId = r.userId;
    expect(r.needsReferrerConfirmation).toBe(true);
    expect(r.username).toBe("13900003013"); // 登录账号 = 手机号

    // 新用户还没有会员 (等确认)
    const view = await getMembershipView(r.userId);
    expect(view.isMember).toBe(false);

    // 推荐关系在, 状态 pending
    const [row] = await db
      .select()
      .from(referralReward)
      .where(eq(referralReward.refereeUserId, r.userId));
    expect(row.status).toBe("pending");
    expect(row.confirmedAt).toBe(null);
    expect(row.source).toBe("self_signup"); // 自助注册 → 等推荐人确认
  });

  it("管理员建号路径 (claimReferralCode) 的来源是 admin, 且新人立刻拿到 15 天", async () => {
    const [u] = await db
      .insert(user)
      .values({
        name: `${TAG}-管理员代建`,
        phoneEncrypted: encryptField("13900003015"),
        phoneHash: hashForLookup("13900003015"),
        role: "sales",
      })
      .returning({ id: user.id });

    const r = await claimReferralCode({ refereeUserId: u.id, rawCode: codeA });
    expect(r.accepted).toBe(true);
    expect(r.refereeGranted).toBe(true); // 管理员背书 → 立刻发

    const [row] = await db
      .select()
      .from(referralReward)
      .where(eq(referralReward.refereeUserId, u.id));
    expect(row.source).toBe("admin");

    // 清理
    await db.delete(entitlementGrant).where(eq(entitlementGrant.userId, u.id));
    await db.delete(membership).where(eq(membership.userId, u.id));
    await db.delete(referralReward).where(eq(referralReward.refereeUserId, u.id));
    await db.delete(user).where(eq(user.id, u.id));
  });

  it("同一手机号不能注册第二次", async () => {
    const dup = await registerWithReferral({
      rawCode: codeA,
      rawName: "李秀兰",
      rawPhone: "13900003013",
      password: "Abcd1234",
    }).catch((e) => e);
    expect((dup as BillingError).code).toBe("PHONE_TAKEN");
  });

  it("推荐人确认 → 新用户拿到 15 天; 重复确认不再重复发", async () => {
    const [row] = await db
      .select()
      .from(referralReward)
      .where(eq(referralReward.refereeUserId, signupUserId!));

    const r1 = await confirmReferral({ referrerUserId: userA, rewardId: row.id });
    expect(r1.ok).toBe(true);
    expect(r1.grantedDays).toBe(15);

    const view = await getMembershipView(signupUserId!);
    expect(view.isMember).toBe(true);
    expect(view.features.length).toBe(9);

    const r2 = await confirmReferral({ referrerUserId: userA, rewardId: row.id });
    expect(r2.grantedDays).toBe(0); // 幂等
    const [after] = await db
      .select()
      .from(referralReward)
      .where(eq(referralReward.id, row.id));
    expect(after.status).toBe("confirmed");
    expect(after.confirmedAt).not.toBe(null);
  });

  it("别人不能确认我的推荐 (越权被拒)", async () => {
    // 造一条新推荐: 新用户用 userA 的码注册, 但让 userB 去确认
    const r = await registerWithReferral({
      rawCode: codeA,
      rawName: "赵小兰",
      rawPhone: "13900003014",
      password: "Abcd1234",
    });
    const [row] = await db
      .select()
      .from(referralReward)
      .where(eq(referralReward.refereeUserId, r.userId));

    const denied = await confirmReferral({
      referrerUserId: userB, // 不是这条推荐的推荐人
      rewardId: row.id,
    }).catch((e) => e);
    expect((denied as BillingError).code).toBe("NOT_MINE");

    // 驳回: 不发权益
    await rejectReferral({
      referrerUserId: userA,
      rewardId: row.id,
      reason: "测试: 不认识",
    });
    const view = await getMembershipView(r.userId);
    expect(view.isMember).toBe(false);

    // 清理这条
    await db.delete(entitlementGrant).where(eq(entitlementGrant.userId, r.userId));
    await db.delete(membership).where(eq(membership.userId, r.userId));
    await db.delete(referralReward).where(eq(referralReward.refereeUserId, r.userId));
    await db.delete(user).where(eq(user.id, r.userId));
  });
});
