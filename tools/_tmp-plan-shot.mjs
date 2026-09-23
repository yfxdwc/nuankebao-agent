// 临时截图脚本 — 验证 /admin/plan 页面渲染 (桌面 1440x900 + 移动 375x812)
// 一次性工具, 不入版本控制 (gitignore tools/_tmp-*.mjs)
import { chromium } from "@playwright/test";

const browser = await chromium.launch();
const ctx = await browser.newContext({ baseURL: "http://127.0.0.1:3003" });

const shots = [
  { name: "desktop-1440x900", w: 1440, h: 900 },
  { name: "mobile-375x812", w: 375, h: 812 },
];

for (const s of shots) {
  const page = await ctx.newPage();
  await page.setViewportSize({ width: s.w, height: s.h });
  const resp = await page.goto("http://127.0.0.1:3003/admin/plan", {
    waitUntil: "networkidle",
    timeout: 30000,
  });
  await page.waitForTimeout(500);
  await page.screenshot({ path: `/tmp/plan-${s.name}.png`, fullPage: true });
  console.log(`✓ ${s.name}: HTTP ${resp.status()}, saved /tmp/plan-${s.name}.png`);
  await page.close();
}

await browser.close();