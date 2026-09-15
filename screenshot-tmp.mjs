import pkg from './node_modules/.pnpm/playwright@1.62.1/node_modules/playwright/index.js';
const { chromium } = pkg;
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 880 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
page.on('console', msg => { const t = msg.text(); if (t.includes('R12') || t.includes('debug') || t.includes('WebCookieSync')) console.log('[browser]', t); });

await page.goto('http://localhost:3003/app/', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(25000);

const r = await page.evaluate(async () => {
  const resp = await fetch('/api/auth/flutter-login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: '13800138000', code: '123456' }) });
  return { status: resp.status, cookies: document.cookie };
});
console.log('after login docCookies len=', r.cookies.length);

await page.goto('http://localhost:3003/app/customers?_init=dbg2', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(35000);

const url = page.url();
console.log('URL:', url);
await browser.close();
