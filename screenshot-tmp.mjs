import pkg from './node_modules/.pnpm/playwright@1.62.1/node_modules/playwright/index.js';
const { chromium } = pkg;
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 880 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
page.on('request', req => {
  if (req.url().includes('/api/customers') && !req.url().includes('graph')) {
    console.log('REQ:', req.url().slice(-30), 'cookie:', req.headers()['cookie']?.slice(0, 60) || '(none)');
  }
});
page.on('response', resp => {
  if (resp.url().includes('/api/customers') && !resp.url().includes('graph')) {
    console.log('RESP:', resp.url().slice(-30), 'status:', resp.status());
  }
});

// 1. 调 /api/auth/flutter-login 让浏览器存 non-HttpOnly cookie
await page.goto('http://localhost:3003/api/health');
await page.evaluate(async () => {
  await fetch('/api/auth/flutter-login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: '13800138000', code: '123456' }) });
});
const cookies = await ctx.cookies();
console.log('浏览器 cookie:', cookies.map(c => `${c.name} httpOnly=${c.httpOnly}`).join(', '));

// 2. 打开 /app 触发 Flutter boot + 试访问 /customers
await page.goto('http://localhost:3003/app/customers?_init=1', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(25000);

await page.screenshot({ path: '/tmp/r12-cookie.png', fullPage: false });
const url = page.url();
const html = await page.content();
console.log('URL:', url.slice(-50));
console.log('"图谱":', html.includes('图谱'));
console.log('"王女士":', html.includes('王女士'));
console.log('"网络":', html.includes('网络'));
console.log('"登录":', html.includes('登录'));
if (url.includes('/login')) console.log('❌ 还在 /login');
else if (url.includes('customers')) console.log('✅ 不循环!');
await browser.close();
