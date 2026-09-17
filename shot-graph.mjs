import pkg from './node_modules/.pnpm/playwright@1.62.1/node_modules/playwright/index.js';
const { chromium } = pkg;
import { writeFileSync } from 'fs';

const CHROME = '/home/tooyan/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome';
const BASE = 'http://127.0.0.1:3003';
const PHONE = '13800138000';
const CODE = '123456';

const browser = await chromium.launch({
  executablePath: CHROME,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});
const ctx = await browser.newContext({
  viewport: { width: 420, height: 880 },
  serviceWorkers: 'block',
});
const page = await ctx.newPage();

page.on('console', msg => {
  const t = msg.text();
  if (t.length < 200) console.log('[b]', t);
});
page.on('pageerror', e => console.log('[ERR]', e.message.slice(0, 200)));

console.log('--- step 1: open /app (Flutter web) to set up session');
await page.goto(`${BASE}/app/`, { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(8000);

console.log('--- step 2: login via API');
const loginResp = await page.evaluate(async ({ phone, code }) => {
  const r = await fetch('/api/auth/flutter-login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone, code }),
  });
  return { status: r.status, cookies: document.cookie };
}, { phone: PHONE, code: CODE });
console.log('login:', loginResp);

console.log('--- step 3: navigate Flutter app to /customers?view=graph');
// Flutter web 用 hash route. 在 iframe 里 = /app-preview 走 hash
// 实际 iframe src 是 /app/ + Flutter 自己的 #/customers?view=graph
// 直接 hash 改写即可, Flutter web 会监听 popstate/hashchange
await page.evaluate(() => {
  window.location.hash = '#/customers?view=graph';
});
await page.waitForTimeout(6000);

// 检查是否还在 login
const url = page.url();
console.log('after hash nav URL:', url);
const onLogin = await page.evaluate(() => location.hash.includes('login'));
console.log('on login?', onLogin);

console.log('--- step 4: screenshot');
const shot = `screenshot-graph-current.png`;
await page.screenshot({ path: shot, fullPage: false });
console.log('saved', shot);

await browser.close();
