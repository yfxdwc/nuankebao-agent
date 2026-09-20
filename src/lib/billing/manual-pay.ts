// ============================================
// 人工收款通道 (内测: 个人微信收款码 + 管理员核销)
// ============================================
// 主人 2026-09-19: 「当前内测阶段，暂时用我个人的微信收款码实现」
//
// 闭环:
//   1. 用户点「开通会员」→ App 显示收款码 (billing_config.manual_wechat_qr_url) + 金额 + 备注提示
//   2. 用户微信扫码付款 → 回 App 点「我已支付」→ 提交 manual_payment_request (pending)
//   3. 管理员 (role=admin) 在 App「管理员工具」里看到待审 → 对账 → 通过
//      → 同一事务外调用 grantDays(member_until += days) + 标记 approved
//   4. 用户「我的」页看到会员生效
//
// 边界:
//   - **只有管理员能核销** (role=admin, 服务端查库判定, 不信客户端)
//   - 一个用户同时只能有一条 pending 申请 (防重复提交刷屏)
//   - 核销写的天数记在申请单上 (grantedDays) + entitlement_grant 流水 → 可追溯
//   - 金额只是"用户申报", 不当作已收钱: **以管理员对账为准** (人工通道的本质)
//   - 审计: manual_payment_request / billing_config / membership / entitlement_grant 全挂触发器

import { promises as fs } from "node:fs";
import path from "node:path";
import { and, desc, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  billingConfig,
  manualPaymentRequest,
  type ManualPaymentRequest,
} from "@/lib/db/schema";
import { BillingError, grantDays } from "@/lib/billing/entitlements";
import { grantIdempotencyKey } from "@/lib/billing/referral";

/** 计费配置的 key (别散落在代码各处) */
export const CONFIG_KEYS = {
  /** 个人微信收款码图片 URL (本站上传产物 /uploads/xxx.png 或静态 /payment/wechat-qr.png) */
  WECHAT_QR_URL: "manual_wechat_qr_url",
  /** 收款人显示名 (让用户核对"是不是转给这个人") */
  PAYEE_NAME: "manual_payee_name",
  /** 备注提示 (默认引导写手机号后 4 位, 方便对账) */
  NOTE_HINT: "manual_note_hint",
  /** 人工通道开关 ('off' = 关闭, 例如以后接了在线支付想让用户走自动) */
  ENABLED: "manual_enabled",
} as const;

/** 静态兜底路径: 管理员把收款码图片放到 public/payment/wechat-qr.png 就能用 */
export const STATIC_QR_PATH = "/payment/wechat-qr.png";

/** 静态兜底收款码在不在 (public/payment/wechat-qr.png) */
async function staticQrExists(): Promise<boolean> {
  try {
    const abs = path.join(
      process.cwd(),
      "public",
      STATIC_QR_PATH.replace(/^\//, "")
    );
    await fs.access(abs);
    return true;
  } catch {
    return false;
  }
}

export interface ManualPayInfo {
  enabled: boolean;
  qrUrl: string | null;
  /** qrUrl 是不是"兜底路径"(没在后台配置过) —— 仅作信息, 不再用来判断"有没有码" */
  isFallbackQr: boolean;
  /** 这张码**现在真的能取到吗** (配置了 URL 或静态文件存在) —— 客户端据此提示 */
  qrAvailable: boolean;
  payeeName: string;
  noteHint: string;
  /** 可选的购买项 (内测只有单月; 将来加季/年) */
  products: { planCode: string; label: string; amountCents: number; days: number }[];
}

/** 内测商品表 (价格以主人 2026-09-19 定: ¥69/月; ¥49 是自动续费价, 人工通道给不了自动续费) */
export const MANUAL_PRODUCTS = [
  { planCode: "monthly", label: "1 个月", amountCents: 6900, days: 30 },
  { planCode: "quarterly", label: "3 个月 (¥189)", amountCents: 18900, days: 90 },
] as const;

async function readConfig(key: string): Promise<string | null> {
  const [row] = await db
    .select({ value: billingConfig.value })
    .from(billingConfig)
    .where(eq(billingConfig.key, key))
    .limit(1);
  const v = row?.value?.v;
  return typeof v === "string" && v.length > 0 ? v : null;
}

/** 读收款信息 (给 App 展示) */
export async function getManualPayInfo(): Promise<ManualPayInfo> {
  const [qr, payee, hint, enabled] = await Promise.all([
    readConfig(CONFIG_KEYS.WECHAT_QR_URL),
    readConfig(CONFIG_KEYS.PAYEE_NAME),
    readConfig(CONFIG_KEYS.NOTE_HINT),
    readConfig(CONFIG_KEYS.ENABLED),
  ]);

  // 兜底路径也要确认文件真的存在, 否则客户端会显示"还没设置收款码"空框
  const qrAvailable = qr != null ? true : await staticQrExists();

  return {
    enabled: enabled !== "off",
    qrUrl: qr ?? STATIC_QR_PATH,
    isFallbackQr: qr == null,
    qrAvailable,
    payeeName: payee ?? "管理员",
    noteHint: hint ?? "付款备注请填写你的手机号后 4 位, 方便对账",
    products: MANUAL_PRODUCTS.map((p) => ({ ...p })),
  };
}

/** 管理员设置收款信息 */
export async function setManualPayConfig(opts: {
  actorUserId: bigint;
  qrUrl?: string | null;
  payeeName?: string | null;
  noteHint?: string | null;
  enabled?: boolean;
}): Promise<void> {
  const writes: { key: string; value: Record<string, unknown> }[] = [];
  if (opts.qrUrl !== undefined) {
    writes.push({ key: CONFIG_KEYS.WECHAT_QR_URL, value: { v: opts.qrUrl ?? "" } });
  }
  if (opts.payeeName !== undefined) {
    writes.push({ key: CONFIG_KEYS.PAYEE_NAME, value: { v: opts.payeeName ?? "" } });
  }
  if (opts.noteHint !== undefined) {
    writes.push({ key: CONFIG_KEYS.NOTE_HINT, value: { v: opts.noteHint ?? "" } });
  }
  if (opts.enabled !== undefined) {
    writes.push({
      key: CONFIG_KEYS.ENABLED,
      value: { v: opts.enabled ? "on" : "off" },
    });
  }

  for (const w of writes) {
    await db
      .insert(billingConfig)
      .values({ key: w.key, value: w.value, updatedByUserId: opts.actorUserId })
      .onConflictDoUpdate({
        target: billingConfig.key,
        set: {
          value: w.value,
          updatedByUserId: opts.actorUserId,
          updatedAt: new Date(),
        },
      });
  }
}

/** 用户提交"我已支付" */
export async function submitManualPayment(opts: {
  userId: bigint;
  planCode: string;
  payerNote?: string | null;
  proofUrl?: string | null;
}): Promise<ManualPaymentRequest> {
  const product = MANUAL_PRODUCTS.find((p) => p.planCode === opts.planCode);
  if (!product) {
    throw new BillingError(400, "BAD_PLAN", "没有这个购买项");
  }

  // 防重复: 同时只能有一条 pending
  const [existing] = await db
    .select({ id: manualPaymentRequest.id })
    .from(manualPaymentRequest)
    .where(
      and(
        eq(manualPaymentRequest.userId, opts.userId),
        eq(manualPaymentRequest.status, "pending")
      )
    )
    .limit(1);
  if (existing) {
    throw new BillingError(
      409,
      "ALREADY_PENDING",
      "你已经提交过一次了, 等管理员确认就好"
    );
  }

  const [row] = await db
    .insert(manualPaymentRequest)
    .values({
      userId: opts.userId,
      planCode: product.planCode,
      amountCents: product.amountCents,
      days: product.days,
      payerNote: opts.payerNote?.slice(0, 200) ?? null,
      proofUrl: opts.proofUrl ?? null,
      status: "pending",
      updatedAt: new Date(),
    })
    .returning();

  return row;
}

/** 我的申请 (最近 5 条) */
export async function listMyManualPayments(
  userId: bigint
): Promise<ManualPaymentRequest[]> {
  return await db
    .select()
    .from(manualPaymentRequest)
    .where(eq(manualPaymentRequest.userId, userId))
    .orderBy(desc(manualPaymentRequest.createdAt))
    .limit(5);
}

/** 管理员: 待审/全部申请 */
export async function listManualPaymentsForAdmin(opts: {
  status?: "pending" | "approved" | "rejected";
  limit?: number;
}): Promise<ManualPaymentRequest[]> {
  const q = db.select().from(manualPaymentRequest);
  const rows = opts.status
    ? await q
        .where(eq(manualPaymentRequest.status, opts.status))
        .orderBy(desc(manualPaymentRequest.createdAt))
        .limit(opts.limit ?? 50)
    : await q.orderBy(desc(manualPaymentRequest.createdAt)).limit(opts.limit ?? 50);
  return rows;
}

/**
 * 管理员核销
 *
 * - approve: 给会员加天数 (grantDays, 幂等键用申请单 id) + 标记 approved
 * - reject: 标记 rejected + 理由 (不给天数)
 * - grantedDays 可由管理员覆盖 (例: 用户一次付了 2 个月)
 */
export async function decideManualPayment(opts: {
  requestId: bigint;
  actorUserId: bigint;
  decision: "approve" | "reject";
  grantedDays?: number;
  rejectReason?: string | null;
}): Promise<{ status: "approved" | "rejected"; grantedDays: number | null }> {
  const [row] = await db
    .select()
    .from(manualPaymentRequest)
    .where(eq(manualPaymentRequest.id, opts.requestId))
    .limit(1);
  if (!row) throw new BillingError(404, "NOT_FOUND", "申请不存在");
  if (row.status !== "pending") {
    throw new BillingError(409, "ALREADY_REVIEWED", "这条已经处理过了");
  }

  const now = new Date();

  if (opts.decision === "reject") {
    await db
      .update(manualPaymentRequest)
      .set({
        status: "rejected",
        reviewedByUserId: opts.actorUserId,
        reviewedAt: now,
        rejectReason: opts.rejectReason?.slice(0, 200) ?? null,
        updatedAt: now,
      })
      .where(eq(manualPaymentRequest.id, opts.requestId));
    return { status: "rejected", grantedDays: null };
  }

  const days = opts.grantedDays ?? row.days;
  if (days <= 0 || days > 3650) {
    throw new BillingError(400, "BAD_DAYS", "天数不合理");
  }

  // 先标记再发 (发失败可重试; grantDays 自己幂等)
  await db
    .update(manualPaymentRequest)
    .set({
      status: "approved",
      reviewedByUserId: opts.actorUserId,
      reviewedAt: now,
      grantedDays: days,
      updatedAt: now,
    })
    .where(eq(manualPaymentRequest.id, opts.requestId));

  await grantDays({
    userId: row.userId,
    days,
    reason: "manual",
    idempotencyKey: grantIdempotencyKey("manual_pay", opts.requestId.toString()),
    grantedByUserId: opts.actorUserId,
    note: `人工收款核销 申请#${opts.requestId} ¥${(row.amountCents / 100).toFixed(0)}`,
    now,
  });

  return { status: "approved", grantedDays: days };
}
