const { chromium } = require('@playwright/test');
(async () => {
  const url = process.argv[2], out = process.argv[3];
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('console', m => { const t = m.text(); if (/R12 debug\] dio|error|403/.test(t)) console.log('[c]', t.slice(0,150)); });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(10000);
  await page.screenshot({ path: out });
  console.log('OK', out);
  await browser.close();
})();
