import pkg from './node_modules/.pnpm/playwright@1.62.1/node_modules/playwright/index.js';
const { chromium } = pkg;
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 880 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
page.on('requestfailed', req => console.log('[reqfail]', req.url().slice(-60), req.failure()?.errorText));
page.on('response', resp => {
  if (resp.status() >= 400) console.log('[resp]', resp.status(), resp.url().slice(-60));
});

await page.goto('http://localhost:3003/api/health');
await page.evaluate(async () => {
  await fetch('/api/auth/flutter-login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: '13800138000', code: '123456' }) });
});

await page.goto('http://localhost:3003/app/customers', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(60000);

const url = page.url();
console.log('URL:', url);
// 看 页面 DOM 结构
const html = await page.content();
console.log('flutters view:', html.includes('flutter-view'));
console.log('flutt glass:', html.includes('flt-glass-pane'));
console.log('canvas:', html.match(/<canvas[^>]*>/g)?.length || 0);

// 看 Flutter web 渲染了什么
const bodyText = await page.evaluate(() => {
  const canvas = document.querySelector('flt-glass-pane');
  return canvas ? 'fltt-glass-pane exists, size=' + canvas.getBoundingClientRect() : 'no glass-pane';
});
console.log('canvas state:', bodyText);

await page.screenshot({ path: '/tmp/r12-diag.png', fullPage: false });
await browser.close();
