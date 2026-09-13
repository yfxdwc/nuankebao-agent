import { defineConfig, devices } from "@playwright/test";

/**
 * Playwright E2E 测试配置
 * 跑: pnpm test:e2e
 *
 * 详见 docs/w5-implementation.md §E2E 测试
 */
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false, // 串行, 避免 dev server 状态污染
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: "list",

  // 共享 dev server 启动 (复用主人当前跑在 3003 的)
  use: {
    baseURL: process.env.E2E_BASE_URL || "http://127.0.0.1:3003",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },

  // 不自动启 server (假设主人已跑 pnpm dev)
  // 主人跑前确保:
  //   pnpm dev
  // 在另一个终端

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});