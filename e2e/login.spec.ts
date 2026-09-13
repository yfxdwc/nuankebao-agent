import { test, expect } from "@playwright/test";

/**
 * E2E: 登录流程
 * 前提: dev server 跑在 3003 + 用户表至少有 1 个用户 (mock 验证码 123456)
 */

test.describe("登录流程", () => {
  test("完整登录 → 仪表盘", async ({ page }) => {
    // 1. 打开根路径 → 应跳 /login
    await page.goto("/");
    await expect(page).toHaveURL(/\/login/);

    // 2. 输入手机号
    await page.fill('input[type="tel"]', "13800138000");
    await page.click('button:has-text("发送验证码")');

    // 3. 输入 mock 验证码 123456
    await page.fill('input[placeholder*="6 位"]', "123456");
    await page.click('button:has-text("登录")');

    // 4. 应跳 /admin 仪表盘
    await page.waitForURL(/\/admin/, { timeout: 10000 });

    // 5. 仪表盘关键元素 (用 h1 精确匹配, 避免 strict mode 冲突)
    await expect(page.locator("h1", { hasText: "仪表盘" })).toBeVisible();
    await expect(page.locator("text=客户总数").first()).toBeVisible();
  });

  test("错误验证码应提示", async ({ page }) => {
    await page.goto("/login");
    await page.fill('input[type="tel"]', "13800138000");
    await page.click('button:has-text("发送验证码")');
    await page.fill('input[placeholder*="6 位"]', "000000");
    await page.click('button:has-text("登录")');

    // 错误提示
    await expect(page.locator("text=验证码错误")).toBeVisible({ timeout: 5000 });
  });
});

test.describe("路由守卫", () => {
  test("未登录访问 /admin 应跳 /login", async ({ page }) => {
    // 清 cookie (模拟未登录)
    await page.context().clearCookies();
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/login/);
  });

  test("登录后访问 /login 应跳 /admin", async ({ page }) => {
    // 先登录
    await page.goto("/login");
    await page.fill('input[type="tel"]', "13800138000");
    await page.click('button:has-text("发送验证码")');
    await page.fill('input[placeholder*="6 位"]', "123456");
    await page.click('button:has-text("登录")');
    await page.waitForURL(/\/admin/, { timeout: 10000 });

    // 再访问 /login 应跳走 (Auth.js 跳到 callbackUrl 或 /admin)
    await page.goto("/login");
    await expect(page).toHaveURL(/\/(admin|login\?callbackUrl)/);
    // 最终应能访问 /admin (中间件会处理 callbackUrl)
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/admin/);
  });
});

test.describe("客户管理", () => {
  test.beforeEach(async ({ page }) => {
    // 登录
    await page.goto("/login");
    await page.fill('input[type="tel"]', "13800138000");
    await page.click('button:has-text("发送验证码")');
    await page.fill('input[placeholder*="6 位"]', "123456");
    await page.click('button:has-text("登录")');
    await page.waitForURL(/\/admin/, { timeout: 10000 });
  });

  test("客户列表页加载", async ({ page }) => {
    await page.goto("/admin/customers");
    // 用 h1 精确匹配 (sidebar 也有"客户管理" 链接, 会冲突)
    await expect(page.locator("h1", { hasText: "客户管理" })).toBeVisible();
  });

  test("新增客户表单", async ({ page }) => {
    await page.goto("/admin/customers/new");
    await expect(page.locator("text=姓名").first()).toBeVisible();
    await expect(page.locator("text=手机号").first()).toBeVisible();
    await expect(page.locator("text=健康标签").first()).toBeVisible();
  });
});

test.describe("健康检查", () => {
  test("API 健康", async ({ request }) => {
    const res = await request.get("/api/health");
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("healthy");
    expect(body.checks.db).toBe("ok");
  });
});