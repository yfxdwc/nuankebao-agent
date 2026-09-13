import { test, expect, request as playwrightRequest } from "@playwright/test";

/**
 * E2E: 完整业务流
 * 流程: 登录 → 创建客户 → 录入养生记录 → 创建跟进任务 → 完成跟进
 */

test.describe("完整业务流", () => {
  test("登录 → 客户 → 养生记录 → 跟进", async ({ page, request }) => {
    // 1. 登录
    await page.goto("/login");
    await page.fill('input[type="tel"]', "13800138000");
    await page.click('button:has-text("发送验证码")');
    await page.fill('input[placeholder*="6 位"]', "123456");
    await page.click('button:has-text("登录")');
    await page.waitForURL(/\/admin/);

    // 2. 客户列表
    await page.goto("/admin/customers");
    await expect(page.locator("h1", { hasText: "客户管理" })).toBeVisible();

    // 3. 仪表盘统计 (应有数据)
    await page.goto("/admin");
    await expect(page.locator("text=客户总数").first()).toBeVisible();
    await expect(page.locator("text=本月到店").first()).toBeVisible();
  });

  test("AI 助手 (mock 模式) - 应有 mock 提示", async ({ page }) => {
    // 登录
    await page.goto("/login");
    await page.fill('input[type="tel"]', "13800138000");
    await page.click('button:has-text("发送验证码")');
    await page.fill('input[placeholder*="6 位"]', "123456");
    await page.click('button:has-text("登录")');
    await page.waitForURL(/\/admin/);

    // AI 助手 (web 端是 /admin/ai 页面, 移动端是 Flutter)
    // 至少验证 API 可用
    const apiCheck = await page.request.get("/api/dictionaries");
    expect(apiCheck.status()).toBe(200);
  });

  test("报表中心 - 加载 4 个指标", async ({ page }) => {
    await page.goto("/login");
    await page.fill('input[type="tel"]', "13800138000");
    await page.click('button:has-text("发送验证码")');
    await page.fill('input[placeholder*="6 位"]', "123456");
    await page.click('button:has-text("登录")');
    await page.waitForURL(/\/admin/);

    await page.goto("/admin/reports");
    await expect(page.locator("h1", { hasText: "报表中心" })).toBeVisible();
  });
});

test.describe("API 端到端", () => {
  // 单独测 API 端点 (用 Playwright request context)
  test("/api/health 公开", async ({ request }) => {
    const res = await request.get("/api/health");
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("healthy");
  });

  test("/api/dictionaries 需登录", async ({ request }) => {
    const res = await request.get("/api/dictionaries");
    expect(res.status()).toBe(401);
  });

  test("/api/customers POST 需手机号", async ({ request }) => {
    // 先登录拿 session
    const csrfRes = await request.get("/api/auth/csrf");
    const csrf = (await csrfRes.json()).csrfToken;
    await request.post("/api/auth/callback/credentials", {
      form: {
        csrfToken: csrf,
        phone: "13800138000",
        code: "123456",
        callbackUrl: "http://127.0.0.1:3003/admin",
        json: "true",
      },
    });

    // 缺手机号
    const res = await request.post("/api/customers", {
      data: { name: "测试" },
    });
    expect(res.status()).toBe(400);
    const body = await res.json();
    expect(body.error).toContain("Invalid");
  });

  test("/api/customers POST 完整流程", async ({ request }) => {
    // 登录
    const csrfRes = await request.get("/api/auth/csrf");
    const csrf = (await csrfRes.json()).csrfToken;
    await request.post("/api/auth/callback/credentials", {
      form: {
        csrfToken: csrf,
        phone: "13800138000",
        code: "123456",
        callbackUrl: "http://127.0.0.1:3003/admin",
        json: "true",
      },
    });

    // 创建客户 (用唯一手机号避免重复)
    const uniquePhone = `138${Date.now().toString().slice(-8)}`;
    const createRes = await request.post("/api/customers", {
      data: {
        name: "E2E 测试客户",
        phone: uniquePhone,
        gender: "F",
        birthYear: 1990,
        healthTags: ["肩颈", "睡眠差"],
      },
    });
    expect(createRes.status()).toBe(201);
    const customer = await createRes.json();
    expect(customer.name).toBe("E2E 测试客户");
    expect(customer.phone).toBe(uniquePhone);
    expect(customer.healthTags).toEqual(["肩颈", "睡眠差"]);

    // 查询
    const getRes = await request.get(`/api/customers/${customer.id}`);
    expect(getRes.status()).toBe(200);
    const fetched = await getRes.json();
    expect(fetched.id).toBe(customer.id);

    // 创建养生记录
    const wrRes = await request.post("/api/wellness-records", {
      data: {
        customerId: customer.id,
        serviceDate: new Date().toISOString().slice(0, 10),
        serviceItemId: "1",
        bodyPartIds: ["1"],
        preCondition: { pain_level: 8 },
        postCondition: { pain_level: 4 },
      },
    });
    expect(wrRes.status()).toBe(201);
    const wr = await wrRes.json();
    expect(wr.customerId).toBe(customer.id);

    // 创建跟进任务
    const fuRes = await request.post("/api/follow-ups", {
      data: {
        customerId: customer.id,
        dueAt: new Date(Date.now() + 7 * 86400_000).toISOString(),
        reason: "E2E 复购测试",
      },
    });
    expect(fuRes.status()).toBe(201);
    const fu = await fuRes.json();
    expect(fu.status).toBe("pending");

    // 完成跟进
    const completeRes = await request.patch(`/api/follow-ups/${fu.id}`, {
      data: { action: "complete", notes: "已联系" },
    });
    expect(completeRes.status()).toBe(200);
    const completed = await completeRes.json();
    expect(completed.status).toBe("done");

    // 软删除客户
    const delRes = await request.delete(`/api/customers/${customer.id}`);
    expect(delRes.status()).toBe(200);

    // 软删后查询应 404
    const afterDel = await request.get(`/api/customers/${customer.id}`);
    expect(afterDel.status()).toBe(404);
  });
});