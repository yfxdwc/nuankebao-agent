const { chromium } = require('@playwright/test');

(async () => {
  const url = process.argv[2] || 'http://192.168.1.200:3010/admin';
  const out = process.argv[3] || '/tmp/admin-mobile.png';
  const w = parseInt(process.argv[4] || '393', 10);
  const h = parseInt(process.argv[5] || '852', 10);

  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: w, height: h },
    deviceScaleFactor: 2,
    isMobile: w < 768,
    hasTouch: w < 768,
  });
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);  // 额外等客户端数据 (字典/API) 加载
  await page.screenshot({ path: out, fullPage: true });
  console.log('OK:', out, `(${w}x${h})`);
  await browser.close();
})();
