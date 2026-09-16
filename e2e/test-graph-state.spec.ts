import { test, chromium } from "@playwright/test";

test.setTimeout(120000);

test("graph view fix 验证", async () => {
  const browser = await chromium.launch({
    headless: true,
    args: [
      "--use-gl=swiftshader",
      "--enable-unsafe-swiftshader",
      "--font-render-hinting=none",
      "--disable-web-security",
    ],
  });
  const context = await browser.newContext({
    viewport: { width: 393, height: 852 },
    locale: "zh-CN",
  });
  const page = await context.newPage();

  // 1. dev login
  const loginResp = await page.request.post("http://127.0.0.1:3003/api/auth/flutter-login", {
    data: { phone: "13800138000", code: "123456" }
  });
  const body = await loginResp.json();
  await context.addCookies([{
    name: body.cookieName || "authjs.session-token",
    value: body.sessionToken,
    domain: "127.0.0.1",
    path: "/",
    httpOnly: false,
    secure: false,
  }]);

  // 2. 直接 goto /customers?view=graph (用 URL hash 走 deep link)
  await page.goto("http://127.0.0.1:8080/#/customers?view=graph", {
    waitUntil: "domcontentloaded",
  });
  await page.waitForTimeout(25000);

  await page.screenshot({ path: "/tmp/screenshots/graph-fix-v3.png", fullPage: false });
  console.log("✓ 截图保存");

  await browser.close();
});
