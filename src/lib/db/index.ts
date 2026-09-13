import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { config as loadEnv } from "dotenv";
import * as schema from "./schema";

// 主机跑 (seed/migrate/tsx) 需要加载 .env.local
// Next.js dev server 会自动加载, 这里双保险
if (!process.env.DATABASE_URL && process.env.NODE_ENV !== "production") {
  loadEnv({ path: ".env.local" });
}

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error(
    "DATABASE_URL is not set. 请检查 .env.local 或 docker-compose 环境变量。"
  );
}

// 单例 postgres 客户端
// 开发期 max=1 避免热重载时连接泄漏
const isDev = process.env.NODE_ENV !== "production";
const client = postgres(connectionString, {
  max: isDev ? 1 : 10,
  idle_timeout: 20,
  prepare: false,
});

export const db = drizzle(client, { schema });

/**
 * 健康检查 (供 /api/health 使用)
 */
export async function checkDb(): Promise<boolean> {
  try {
    await client`SELECT 1`;
    return true;
  } catch (error) {
    console.error("[db] health check failed:", error);
    return false;
  }
}

/**
 * 设置当前会话的 user_id (供 audit_trigger 使用)
 */
export async function withAuditContext<T>(
  userId: bigint,
  ipAddress: string,
  fn: () => Promise<T>
): Promise<T> {
  return await fn();
  // W2 实现: 用 transaction + SET LOCAL
}