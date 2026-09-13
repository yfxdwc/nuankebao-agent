import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: ["tests/**/*.test.ts"],
    setupFiles: ["./tests/setup.ts"],
    testTimeout: 10000,
    // 单 fork 顺序跑: 多个 test file 共享同一个 Postgres 测试库,
    // 并行 worker 会互相冲突 (插入失败 / 看不见对方数据)
    // 详见 Plan F1 实施记录
    pool: "forks",
    poolOptions: {
      forks: {
        singleFork: true,
      },
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
});