// ============================================
// 建号 = 建账号 + 建客户档案 (强制) + 推荐码必填 (admin/根 可空)
// ============================================
// 主人 2026-09-19 拍:
//   「建号即强制建档 + 推荐码必填，推荐码作为用户账户最强身份识别码（admin/根可空）」
//
// 三条不变量 (本模块是唯一入口, 所有建号路径都必须走这里):
//   ① 每个 user 必有一条 customer 档案 (同手机号; 已存在则复用不新建)
//   ② 非 admin/根账号, 建号时**必须**给推荐码 (谁把我带进来的)
//   ③ 建号即分配自己的推荐码 (不可改) —— 推荐码是账号的稳定身份标识
//
// ⚠ 与客户图谱的关系 (主人同日拍: no_link):
//   - 推荐码**不写** customer.referrer_id (会员/账号层的推荐关系 ≠ 客户图谱的老带新)
//   - 客户图谱的推荐人仍由业务动作决定 (落位/导入), 两条线各自独立
//
// ⚠ 用户 ↔ 客户 的关联方式: 手机号 hash (项目既有约定, 无 FK 列)。
//   本模块保证"建号即建档", 所以约定在新数据上永远成立。

import { and, eq, isNull } from "drizzle-orm";

import { db } from "@/lib/db";
import { customer, user } from "@/lib/db/schema";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import { hashPassword, isValidPassword } from "@/lib/auth/password";
import { claimReferralCode, ensureReferralCode } from "@/lib/billing/entitlements";
import { adoptOrphanNodeForNewAccount } from "@/lib/db/queries/franchisee-account";
import { referralCode as referralCodeTable } from "@/lib/db/schema";
import { normalizeReferralCode } from "@/lib/billing/referral";

export type AccountRole = "admin" | "manager" | "sales";

export interface CreateAccountInput {
  name: string;
  phone: string;
  role?: AccountRole;
  /** 初始密码 (可空 = 不设密码, 只能短信验证码登录) */
  password?: string;
  /** 登录用户名 (默认 = 手机号) */
  username?: string;
  /**
   * 推荐人 6 位推荐码 —— 非 admin/根账号**必填** (主人 2026-09-19 拍)
   *   「推荐码作为用户账户最强身份识别码」
   */
  referralCode?: string;
  /** 豁免"必须有推荐码" (只给 admin / 根账号用; 调用方要显式传) */
  allowNoReferral?: boolean;
  /**
   * 客户档案的建档人 = **本人** (自助注册场景; ADR-0015 Q12)
   *   false/缺省 = 建档人 = `actorUserId` (管理员/脚本代建)
   */
  customerCreatedBySelf?: boolean;
  /**
   * 推荐码生效方式 (透传给 claimReferralCode):
   *   immediate (缺省) = 管理员建号, 新人立刻拿 15 天
   *   pending_confirmation = 自助注册, 等推荐人确认才发
   */
  referralMode?: "immediate" | "pending_confirmation";
  ipAddress?: string;
  /** 操作人 (审计) */
  actorUserId: bigint;
}

export interface CreateAccountResult {
  userId: bigint;
  /**
   * 客户档案 id —— **admin 豁免建档** (ADR-0015 Q5, 主人 2026-09-22 拍) → null
   */
  customerId: bigint | null;
  /**
   * 建号时自动认领的"无账号加盟节点" id (主人 2026-09-21 拍: 消除无账号节点)
   *   - 她本来就是树里的人 (老 seed / 老数据留下的孤儿节点), 一注册就补上账号
   *   - null = 没有待认领的节点 (常规情况)
   */
  adoptedFranchiseeId: bigint | null;
  /** 新建客户档案? false = 复用同手机号的既有档案 */
  customerCreated: boolean;
  /** 新账号自己的推荐码 (注册即分配) */
  ownReferralCode: string;
  /** 推荐人 user id (没填码 = null) */
  referrerUserId: bigint | null;
  /** 推荐码是否已受理 (填了但被拒 = false, 原因见 referralRejectedReason) */
  referralAccepted: boolean;
  referralRejectedReason: string | null;
}

export class RegistrationError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = "RegistrationError";
  }
}

/**
 * 建号 (唯一入口): 建账号 + 建客户档案 + 领推荐码 + 分配自己的推荐码
 *
 * 幂等性: 手机号已存在 → 直接报错 (调用方应先查; 批量导入场景跳过即可)
 */
export async function createAccountWithProfile(
  input: CreateAccountInput
): Promise<CreateAccountResult> {
  const name = input.name?.trim();
  const phone = input.phone?.trim();
  const role: AccountRole = input.role ?? "sales";

  if (!name) throw new RegistrationError(400, "姓名必填");
  if (!phone || !/^1[3-9]\d{9}$/.test(phone)) {
    throw new RegistrationError(400, "手机号格式不对");
  }
  if (input.password && !isValidPassword(input.password)) {
    throw new RegistrationError(400, "初始密码不合格");
  }

  // ② 推荐码必填 (admin/根 可空)
  const isAdminLike = role === "admin";
  const code = input.referralCode?.trim() ?? "";
  if (!isAdminLike && !input.allowNoReferral && !code) {
    throw new RegistrationError(
      400,
      "建号必须填推荐码 (谁把我带进来的); 只有 admin / 根账号可以留空"
    );
  }

  const phoneHash = hashForLookup(phone);
  const username = input.username?.trim() || phone;
  const passwordHash = input.password ? hashPassword(input.password) : null;

  // ---- 事务: 账号 + 客户档案 (审计由 withAuditContext 兜住) ----
  const { userId, customerId, customerCreated, adoptedFranchiseeId } =
    await withAuditContext(
    { userId: input.actorUserId, ipAddress: input.ipAddress } satisfies AuditContext,
    async (tx) => {
      const [dupe] = await tx
        .select({ id: user.id })
        .from(user)
        .where(eq(user.phoneHash, phoneHash))
        .limit(1);
      if (dupe) {
        throw new RegistrationError(409, `该手机号已有账号 (id=${dupe.id})`);
      }

      const [created] = await tx
        .insert(user)
        .values({
          name,
          role,
          isActive: true,
          phoneEncrypted: encryptField(phone),
          phoneHash,
          username,
          passwordHash,
        })
        .returning({ id: user.id });

      // ⓪ 节点 ⇒ 账号 不变量 (主人 2026-09-21 拍): 同手机号若已有一个**没账号**的加盟节点
      //    (老 seed / 老数据留下的孤儿节点) → 这次注册直接把账号绑上去 = 自愈
      const adopted = await adoptOrphanNodeForNewAccount(tx, {
        userId: created.id,
        phoneHash,
      });

      // ⓪ admin 豁免建档 (ADR-0015 Q5, 主人 2026-09-22 拍):
      //   管理员「不是任何人的下线」, 不参与客户维护 → 不建客户档案
      //   (prod 现状 admin 无档案 = 合法; 推荐码照发, 它是身份识别码)
      if (role === "admin") {
        return {
          userId: created.id,
          customerId: null,
          customerCreated: false,
          adoptedFranchiseeId: adopted?.adoptedFid ?? null,
        };
      }

      // ① 客户档案: 同手机号已有 (例如他早就是客户/加盟商) → 复用, 不重复建
      const [existingCustomer] = await tx
        .select({ id: customer.id })
        .from(customer)
        .where(and(eq(customer.phoneHash, phoneHash), isNull(customer.deletedAt)))
        .limit(1);

      let customerId: bigint;
      let customerCreated = false;
      if (existingCustomer) {
        customerId = existingCustomer.id;
      } else {
        const [newCustomer] = await tx
          .insert(customer)
          .values({
            name,
            phoneEncrypted: encryptField(phone),
            phoneHash,
            isSeed: false,
            // 归属 = NULL (ADR-0015 Q12, 2026-09-22 拍): 建号只建档, **不自动**归属推荐人
            //   → 推荐人在「我推荐的人」页**显式添加** (先到先得, Q15)
            ownerId: null,
            // 建档人: 自助注册 = 本人 (Q12); 管理员/脚本建号 = actor (审计看得见谁建的)
            createdBy: input.customerCreatedBySelf ? created.id : input.actorUserId,
            // ❌ 不写 customer.referrer_id (ADR-0015 Q4: 客户图谱老带新死链路已废);
            //   「谁带来谁」唯一真相源 = referral_reward (本函数上方就写它)
          })
          .returning({ id: customer.id });
        customerId = newCustomer.id;
        customerCreated = true;
      }

      // ★ 列连接 (ADR-0015 Q7, migration 0021): user.customer_id = 她对应的客户档案
      //   从此改手机号 / 查"我的档案"不用再靠 phone_hash 相等现猜
      await tx
        .update(user)
        .set({ customerId })
        .where(eq(user.id, created.id));

      return {
        userId: created.id,
        customerId,
        customerCreated,
        adoptedFranchiseeId: adopted?.adoptedFid ?? null,
      };
    }
  );

  // ---- 事务外 (claim/ensure 内部自己用 db, 放进事务会撞连接池) ----
  // ③ 自己的推荐码: 注册即分配
  const ownReferralCode = await ensureReferralCode(userId);

  // 推荐人: 填了码才处理 (奖励规则见 ADR-0012 §6)
  let referrerUserId: bigint | null = null;
  let referralAccepted = false;
  let referralRejectedReason: string | null = null;
  if (code) {
    const res = await claimReferralCode({
      refereeUserId: userId,
      rawCode: code,
      refereePhoneHash: phoneHash,
      refereeIp: input.ipAddress ?? null,
      mode: input.referralMode ?? "immediate",
    });
    referralAccepted = res.accepted;
    referralRejectedReason = res.accepted ? null : (res.reason ?? "推荐码未被受理");
    if (res.accepted) {
      // 推荐人 = 码的主人 (claim 只返回是否受理, 归属这里查)
      const [owner] = await db
        .select({ userId: referralCodeTable.userId })
        .from(referralCodeTable)
        .where(eq(referralCodeTable.code, normalizeReferralCode(code)))
        .limit(1);
      referrerUserId = owner?.userId ?? null;
    }
  }

  return {
    userId,
    adoptedFranchiseeId,
    customerId,
    customerCreated,
    ownReferralCode,
    referrerUserId,
    referralAccepted,
    referralRejectedReason,
  };
}

/**
 * 保证一个**已存在**账号也有客户档案 + 自己的推荐码
 *   (存量账号补齐 / admin 建号后的兜底; 幂等)
 */
export async function ensureAccountProfile(
  userId: bigint,
  actorUserId: bigint
): Promise<{
  customerId: bigint | null;
  customerCreated: boolean;
  referralCode: string;
}> {
  const [u] = await db
    .select({
      id: user.id,
      name: user.name,
      role: user.role,
      phoneEncrypted: user.phoneEncrypted,
      phoneHash: user.phoneHash,
    })
    .from(user)
    .where(eq(user.id, userId))
    .limit(1);
  if (!u) throw new RegistrationError(404, `账号不存在 (id=${userId})`);

  // admin 豁免建档 (ADR-0015 Q5): 管理员「不是任何人的下线」, 不参与客户维护
  //   → 不建客户档案 (推荐码照发: 身份识别用); prod admin 现状 = 无档案, 合法
  if (u.role === "admin") {
    return {
      customerId: null,
      customerCreated: false,
      referralCode: await ensureReferralCode(userId),
    };
  }

  const { customerId, customerCreated } = await withAuditContext(
    { userId: actorUserId },
    async (tx) => {
      const [existing] = await tx
        .select({ id: customer.id })
        .from(customer)
        .where(and(eq(customer.phoneHash, u.phoneHash), isNull(customer.deletedAt)))
        .limit(1);
      if (existing) {
        // ★ 列连接 (ADR-0015 Q7): 补上 user.customer_id (存量行 / 之前漏写)
        await tx
          .update(user)
          .set({ customerId: existing.id })
          .where(eq(user.id, userId));
        return { customerId: existing.id, customerCreated: false };
      }

      const [created] = await tx
        .insert(customer)
        .values({
          name: u.name,
          phoneEncrypted: u.phoneEncrypted,
          phoneHash: u.phoneHash,
          isSeed: false,
          // 归属 = NULL (ADR-0015 Q12): 补档不自动归属建档人, 等显式添加
          ownerId: null,
          createdBy: actorUserId,
        })
        .returning({ id: customer.id });
      await tx
        .update(user)
        .set({ customerId: created.id })
        .where(eq(user.id, userId));
      return { customerId: created.id, customerCreated: true };
    }
  );

  const referralCode = await ensureReferralCode(userId);
  return { customerId, customerCreated, referralCode };
}
