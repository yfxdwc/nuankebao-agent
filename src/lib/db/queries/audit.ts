// ============================================
// 审计日志查询 (2026-09-24)
//
// 背景 (管理 Tab 建议 #2): `audit_log` 由 Postgres 触发器自动写
//   (drizzle/audit_trigger.sql), 但**一直没有查询接口** —— 归属转移 / 合并 /
//   身份绑定 / 归档这些"动了别人东西"的操作, 事后没人能回答
//   "谁改的、什么时候改的"。
//
// ⚠ **`record_id` 跨表不唯一** (AGENTS §5 已沉淀过): 查审计**必须**带
//   `table_name` 一起过滤, 否则会静默拿到别的表同 id 的记录
//   (schema 里 `idx_audit_table_record(table_name, record_id)` 就是这个用途)。
//
// 隐私: 只返回**变更了哪些列** (列名), **不返回列值** —— 列值里可能是
//   pgcrypto 密文 / 手机号 / 病史, 没必要也不该透到前端。中文标签由 UI 映射。
// ============================================

import { and, desc, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { auditLog, user } from "@/lib/db/schema";

export interface AuditEntryView {
  id: string;
  /** INSERT / UPDATE / DELETE (触发器写入的原始操作名) */
  operation: string;
  /** 发生变化的列名 (INSERT/DELETE = 整行所有列; UI 按 operation 归并成"建档/修改 X/归档") */
  changedColumns: string[];
  /** 操作人姓名; null = 系统 / 脚本 / 未带审计上下文 (dev skip-auth 等) */
  actorName: string | null;
  /** ISO 时间 */
  createdAt: string;
}

/**
 * 某客户档案的最近改动 (倒序)
 *
 * @param customerId 客户 id (`audit_log.record_id`)
 * @param limit 最多几条 (调用方已夹取上限)
 */
export async function listCustomerAuditTrail(
  customerId: bigint,
  limit = 20
): Promise<AuditEntryView[]> {
  const rows = await db
    .select({
      id: auditLog.id,
      operation: auditLog.operation,
      changedFields: auditLog.changedFields,
      createdAt: auditLog.createdAt,
      actorName: user.name,
    })
    .from(auditLog)
    .leftJoin(user, eq(auditLog.userId, user.id))
    .where(
      and(
        // ★ 两列一起查 (只按 record_id 会拿到别的表的同 id 记录)
        eq(auditLog.tableName, "customer"),
        eq(auditLog.recordId, customerId)
      )
    )
    .orderBy(desc(auditLog.createdAt), desc(auditLog.id))
    .limit(limit);

  return rows.map((r) => {
    const fields = r.changedFields;
    return {
      id: r.id.toString(),
      operation: r.operation,
      changedColumns:
        fields !== null && typeof fields === "object"
          ? Object.keys(fields as Record<string, unknown>)
          : [],
      actorName: r.actorName ?? null,
      createdAt: r.createdAt.toISOString(),
    };
  });
}
