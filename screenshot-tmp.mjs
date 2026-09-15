import pkg from './node_modules/.pnpm/playwright@1.62.1/node_modules/playwright/index.js';
const { chromium } = pkg;
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 880 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
page.on('console', msg => { const t = msg.text(); if (t.includes('R12')) console.log('[browser]', t); });
page.on('response', resp => {
  if (resp.url().includes('/api/customers') && !resp.url().includes('graph')) {
    console.log('RESP', resp.status(), resp.url().slice(-30));
  }
});

// 1. 打开 /app (Flutter boot + _checkLogin 跑一次, 没 cookie → 跳 /login)
await page.goto('http://localhost:3003/app/', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(20000);

// 2. 调 /api/auth/flutter-login (在 Flutter web 内部)
const r = await page.evaluate(async () => {
  const resp = await fetch('/api/auth/flutter-login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: '13800138000', code: '123456' }) });
  return { status: resp.status, cookies: document.cookie };
});
console.log('login ok, docCookies len:', r.cookies.length);

// 3. 直接 navigate 到 /customers (retry 200ms 后 _checkLogin 跑, 这时 cookie 已设)
await page.goto('http://localhost:3003/app/customers?_init=11', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(40000);

await page.screenshot({ path: '/tmp/r12-final.png', fullPage: false });
const url = page.url();
const html = await page.content();
console.log('URL:', url);
console.log('"图谱":', html.includes('图谱'));
console.log('"王女士":', html.includes('王女士'));
console.log('"网络":', html.includes('网络'));
if (url.includes('/login')) console.log('❌ 还在 /login');
else if (url.includes('customers')) console.log('✅ 不循环!');
await browser.close();
