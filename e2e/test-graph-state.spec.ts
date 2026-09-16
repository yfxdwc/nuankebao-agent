import { test } from "@playwright/test";

test.setTimeout(90000); // 90s 给 Flutter web 加载

test("graph view 当前状态截图", async ({ page }) => {
  await page.goto("http://127.0.0.1:3003/app-preview?path=/customers&view=graph&dev=1", {
    waitUntil: "domcontentloaded",
  });

  // 等 Flutter web 加载 + 渲染 (Flutter web canvas 通常需要 ~15-25s)
  await page.waitForTimeout(45000);

  await page.screenshot({ path: "/tmp/screenshots/graph-current.png", fullPage: false });
  console.log("✓ 截图保存到 /tmp/screenshots/graph-current.png");
});
