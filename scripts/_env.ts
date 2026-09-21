// ============================================
// 脚本环境变量加载 (必须在任何读 process.env 的模块**之前**求值)
// ============================================
// 背景 (2026-09-21 修):
//   `import { config as loadEnv } from "dotenv"; loadEnv({path:".env.local"});` 这种写法
//   在 ESM 下**无效** —— import 声明会被提升到模块顶部, 于是 `@/lib/db` 先求值,
//   `DATABASE_URL` 还没进 process.env → 直接抛 "DATABASE_URL is not set"。
//   (14 个脚本都是这个写法, 只有先 `export $(grep -v '^#' .env.local | xargs)` 才跑得起来。)
//
// 用法: 把它放成脚本的**第一个 import** —— ESM 按源码顺序深度优先求值,
//       所以 `import "./_env"` 的副作用一定先于后面的 `import { db }` 执行。
import { config as loadEnv } from "dotenv";

loadEnv({ path: ".env.local" });
