import pkg from './node_modules/.pnpm/playwright@1.62.1/node_modules/playwright/index.js';
const { chromium } = pkg;
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 880 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
page.on('console', msg => { const t = msg.text(); if (t.includes('R12') || t.includes('main()') || t.includes('document')) console.log('[browser]', t); });

await page.goto('http://localhost:3003/app/?_init=dbg3', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(20000);
const r1 = await page.evaluate(() => ({ cookies: document.cookie.length }));
console.log('1st open: docCookies len=', r1.cookies);

const r2 = await page.evaluate(async () => {
  const resp = await fetch('/api/auth/flutter-login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: '13800138000', code: '123456' }) });
  return { status: resp.status, cookies: document.cookie.length };
});
console.log('after login: docCookies len=', r2.cookies);

await page.goto('http://localhost:3003/app/customers?_init=dbg4', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(35000);

const url = page.url();
console.log('URL:', url);
if (url.includes('/login')) console.log('❌ 还在 /login');
else if (url.includes('customers')) console.log('✅ 不循环!');
await browser.close();
