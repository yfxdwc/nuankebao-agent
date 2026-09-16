import { test, expect } from "@playwright/test";

test.setTimeout(90000);

test("graph view 当前状态截图 (直连 Flutter web dev)", async ({ page }) => {
  // 直连 Flutter web dev server (不走 iframe, 避开 R12)
  await page.goto("http://127.0.0.1:8080/#/customers?view=graph", {
    waitUntil: "domcontentloaded",
  });

  await page.waitForTimeout(25000);

  // 截图整页
  await page.screenshot({ path: "/tmp/screenshots/graph-direct.png", fullPage: false });
  console.log("✓ 截图保存到 /tmp/screenshots/graph-direct.png");
});
