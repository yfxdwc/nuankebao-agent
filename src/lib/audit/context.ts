import { db } from "@/lib/db";
import { sql } from "drizzle-orm";

// ============================================
// 审计上下文封装
// 在事务中设置 session 变量, audit_trigger 自动捕获
// 详见 docs/security-compliance.md §5
// ============================================

export interface AuditContext {
  userId?: bigint | null;
  ipAddress?: string | null;
}

/**
 * 在事务中执行操作, 设置 session 变量让 audit_trigger 自动捕获
 *
 * 用法:
 *   const customer = await withAuditContext(
 *     { userId, ipAddress },
 *     async (tx) => {
 *       return await tx.insert(customer).values(data).returning();
 *     }
 *   );
 */
export async function withAuditContext<T>(
  ctx: AuditContext,
  fn: (tx: typeof db) => Promise<T>
): Promise<T> {
  return await db.transaction(async (tx) => {
    if (ctx.userId != null) {
      // postgres-js 不支持参数化 SET LOCAL, 用 raw SQL
      await tx.execute(
        sql.raw(`SET LOCAL app.current_user_id = ${ctx.userId.toString()}`)
      );
    }
    if (ctx.ipAddress) {
      await tx.execute(
        sql.raw(`SET LOCAL app.client_ip = '${ctx.ipAddress.replace(/'/g, "''")}'`)
      );
    }
    return await fn(tx as unknown as typeof db);
  });
}

/**
 * 从 Next.js request 提取 AuditContext
 */
export function getAuditContextFromRequest(
  request: Request,
  session: { user?: { id?: string } } | null
): AuditContext {
  const userId = session?.user?.id ? BigInt(session.user.id) : null;
  const ipAddress =
    request.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    request.headers.get("x-real-ip") ||
    null;
  return { userId, ipAddress };
}