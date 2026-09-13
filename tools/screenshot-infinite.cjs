const { chromium } = require('@playwright/test');

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: 393, height: 852 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
  });
  const page = await ctx.newPage();
  await page.goto('http://192.168.1.200:3010/admin/customers', { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);

  // 截首屏
  await page.screenshot({ path: '/tmp/v2-cust-initial.png', fullPage: false });
  console.log('initial: /tmp/v2-cust-initial.png');

  // 模拟滚到底
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(1500);  // 等 fetch + 渲染
  await page.screenshot({ path: '/tmp/v2-cust-scrolled.png', fullPage: false });
  console.log('scrolled: /tmp/v2-cust-scrolled.png');

  // 截全页
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(300);
  await page.screenshot({ path: '/tmp/v2-cust-full.png', fullPage: true });
  console.log('full: /tmp/v2-cust-full.png');

  // 看 items count
  const count = await page.locator('main a[href^="/admin/customers/"]').count();
  console.log('total items rendered:', count);

  await browser.close();
})();
