import pkg from './node_modules/.pnpm/playwright@1.62.1/node_modules/playwright/index.js';
const { chromium } = pkg;
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 880 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
page.on('console', msg => console.log('[console]', msg.type().slice(0,3), msg.text().slice(0, 200)));
page.on('pageerror', err => console.log('[pageerror]', err.message.slice(0, 200)));
page.on('response', resp => {
  if (resp.url().includes('/api/customers')) {
    console.log('RESP:', resp.url().slice(-30), 'status:', resp.status());
  }
});

await page.goto('http://localhost:3003/api/health');
await page.evaluate(async () => {
  await fetch('/api/auth/flutter-login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: '13800138000', code: '123456' }) });
});

await page.goto('http://localhost:3003/app/customers?_init=4', { waitUntil: 'domcontentloaded', timeout: 60000 });
// 等更久
await page.waitForTimeout(40000);
await page.screenshot({ path: '/tmp/r12-final.png', fullPage: false });

const url = page.url();
console.log('URL:', url.slice(-50));
const html = await page.content();
console.log('"图谱":', html.includes('图谱'));
console.log('"王女士":', html.includes('王女士'));
console.log('"客户":', html.includes('客户'));
console.log('"网络":', html.includes('网络'));
if (url.includes('/login')) console.log('❌ 还在 /login');
else if (url.includes('customers')) console.log('✅ 不循环!');

await browser.close();
