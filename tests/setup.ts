// 全局测试 setup
// - 设置环境变量
// - mock dotenv / fs 等

// process.env.NODE_ENV 默认就是 "test" (vitest 跑时)
process.env.DATABASE_URL = process.env.DATABASE_URL || "postgres://test:test@localhost:5432/test";
process.env.AUTH_SECRET = "test-secret-32chars-123456789012345";
process.env.PGCRYPTO_KEY = "0".repeat(64); // 32 bytes hex, 测试用
process.env.MINIMAX_API_KEY = ""; // 强制走 mock