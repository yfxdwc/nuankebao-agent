import type { Config } from "drizzle-kit";
import { config as loadEnv } from "dotenv";

// drizzle-kit 默认读 .env, 主机跑需要 .env.local 的 localhost 地址
loadEnv({ path: ".env.local" });

if (!process.env.DATABASE_URL) {
  throw new Error("DATABASE_URL is not set in .env.local");
}

export default {
  schema: "./src/lib/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: {
    url: process.env.DATABASE_URL,
  },
  strict: true,
  verbose: true,
} satisfies Config;