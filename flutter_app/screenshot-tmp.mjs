import pkg from './node_modules/.pnpm/playwright@1.62.1/node_modules/playwright/index.js';
const { chromium } = pkg;
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 880 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
page.on('console', msg => { const t = msg.text(); if (t.includes('R12') || t.includes('main()') || t.includes('document')) console.log('[browser]', t); });

// 1. 打开 /app
await page.goto('http://localhost:3003/app/?_init=15', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(20000);
const r1 = await page.evaluate(() => ({ cookies: document.cookie.length }));
console.log('1st open: docCookies len=', r1.cookies);

// 2. 调 login (同源)
const r2 = await page.evaluate(async () => {
  const resp = await fetch('/api/auth/flutter-login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: '13800138000', code: '123456' }) });
  return { status: resp.status, cookies: document.cookie.length };
});
console.log('after login: docCookies len=', r2.cookies);

// 3. 再读 document.cookie (verify)
const r3 = await page.evaluate(() => ({ cookies: document.cookie.length, preview: document.cookie.slice(0, 50) }));
console.log('3rd check: docCookies len=', r3.cookies, 'preview=', r3.preview);

await browser.close();
