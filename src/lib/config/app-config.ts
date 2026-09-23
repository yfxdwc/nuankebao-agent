// ============================================
// 通用「可调参数组」覆盖层 (app_config 表)
// ============================================
// 主人 2026-09-23 拍: 「在 admin 里增加管理、调节页面, 让评分规则及其他客户管理中的
//   参数可在管理页面进行调节」
//
// 这一层**不懂业务**: 它只管 key → jsonb 的读写。
// 业务语义 (默认值、区间夹取、版本号) 一律留给各自的 `*-store.ts`:
//   src/lib/customer/insight-config-store.ts  ← 客户洞察 31 个参数
//   将来: urgency / 列表分页 / 标签阈值 ...
//
// 为什么不把默认值也存 DB:
//   默认值在代码里 = 「重置为默认」就是删一行, 且改代码默认值立刻生效,
//   不需要写一条"把 DB 里旧默认值也改掉"的迁移 —— 少一类漂移。
// ============================================

import { eq, desc } from "drizzle-orm";

import { db } from "@/lib/db";
import { appConfig } from "@/lib/db/schema";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";

/** 已知的配置键 (集中登记, 防拼错字符串) */
export const APP_CONFIG_KEYS = {
  /** 客户洞察: 评分 3 维 + 行动 9 条规则 + 阈值 (31 个可调参数) */
  CUSTOMER_INSIGHT: "customer.insight",
} as const;

export type AppConfigKey = (typeof APP_CONFIG_KEYS)[keyof typeof APP_CONFIG_KEYS];

export interface AppConfigRecord {
  key: string;
  value: unknown;
  description: string | null;
  updatedBy: bigint | null;
  updatedAt: Date;
}

/** 读一条覆盖值; 没有 → undefined (= 全用代码默认值) */
export async function getAppConfigValue(key: string): Promise<unknown | undefined> {
  const [row] = await db
    .select({ value: appConfig.value })
    .from(appConfig)
    .where(eq(appConfig.key, key))
    .limit(1);
  return row?.value;
}

/** 读整条记录 (admin 页要展示"最后谁改的/什么时候") */
export async function getAppConfigRecord(
  key: string
): Promise<AppConfigRecord | undefined> {
  const [row] = await db
    .select()
    .from(appConfig)
    .where(eq(appConfig.key, key))
    .limit(1);
  return row;
}

/**
 * 写入覆盖值 (upsert)
 *
 * ⚠ 走 `withAuditContext`: app_config 挂了 audit_trigger, 谁改的/改成什么
 *   由 audit_log 记录 —— 这是 ADR-0015「诊断/配置类改动要留痕」的落地。
 */
export async function setAppConfigValue(
  key: string,
  value: unknown,
  ctx: AuditContext,
  description?: string
): Promise<void> {
  await withAuditContext(ctx, async (tx) => {
    await tx
      .insert(appConfig)
      .values({
        key,
        value,
        description: description ?? null,
        updatedBy: ctx.userId ?? null,
      })
      .onConflictDoUpdate({
        target: appConfig.key,
        set: {
          value,
          description: description ?? null,
          updatedBy: ctx.userId ?? null,
          updatedAt: new Date(),
        },
      });
  });
}

/**
 * 删除覆盖值 = 回落代码默认值 ("重置为默认")
 *
 * 用 DELETE 而不是"写一份等于默认值的 value": 后者会在代码改默认值后**变成陈旧覆盖**,
 * 而用户以为自己用的就是默认 —— 这是配置系统最阴的一类 bug。
 */
export async function deleteAppConfigValue(
  key: string,
  ctx: AuditContext
): Promise<boolean> {
  return await withAuditContext(ctx, async (tx) => {
    const deleted = await tx
      .delete(appConfig)
      .where(eq(appConfig.key, key))
      .returning({ key: appConfig.key });
    return deleted.length > 0;
  });
}

/** 列出所有覆盖 (admin 页"最近变更" / 体检用) */
export async function listAppConfigs(): Promise<AppConfigRecord[]> {
  return await db
    .select()
    .from(appConfig)
    .orderBy(desc(appConfig.updatedAt));
}
