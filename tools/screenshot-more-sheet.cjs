const { chromium } = require('@playwright/test');

(async () => {
  const url = process.argv[2] || 'http://192.168.1.200:3010/admin';
  const out = process.argv[3] || '/tmp/more-sheet.png';

  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: 393, height: 852 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
  });
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: 'networkidle' });
  // 点"更多" tab
  await page.click('[aria-label="更多菜单"]');
  await page.waitForTimeout(300);  // 等动画
  await page.screenshot({ path: out, fullPage: false });
  console.log('OK:', out);
  await browser.close();
})();
