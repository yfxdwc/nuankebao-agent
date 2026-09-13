const { chromium } = require('@playwright/test');

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: 393, height: 852 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
  });
  const page = await ctx.newPage();

  // 先 seed 多点客户 (走 API, 但 seed 不能, 走 /admin/customers/new 表单也太慢)
  // 改: 走 seed 脚本生成
  // 这次直接测 swipe 触屏 (follow-up 第一张卡)
  await page.goto('http://192.168.1.200:3010/admin/follow-ups?filter=all', { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);

  // 用 touch API 模拟左滑
  // 找第一张卡片
  const firstCardHandle = await page.locator('main > div > div > div > div').first();
  // 简化: 找第一个 swipe container
  const card = page.locator('main .will-change-transform').first();
  const box = await card.boundingBox();
  if (!box) {
    console.log('no card found');
    process.exit(1);
  }
  console.log('card box:', box);

  const startX = box.x + box.width - 30;
  const y = box.y + 30;

  // 用 dispatch touch events
  await page.touchscreen.tap(startX, y);
  await page.waitForTimeout(100);

  // Playwright touch API: 模拟 swipe
  // touchscreen.tap 是单击, swipe 用 mouse + down/up
  // 改用 dispatchEvent
  await page.evaluate(({ startX, y, boxWidth }) => {
    const el = document.elementFromPoint(startX, y);
    if (!el) return;
    const touchStart = new TouchEvent('touchstart', {
      touches: [new Touch({ identifier: 1, target: el, clientX: startX, clientY: y })],
      bubbles: true,
      cancelable: true,
    });
    el.dispatchEvent(touchStart);

    // 模拟左滑 (X 减小, 从 startX 到 startX - 200)
    let curX = startX;
    const steps = 10;
    for (let i = 1; i <= steps; i++) {
      curX = startX - (200 * i / steps);
      const touchMove = new TouchEvent('touchmove', {
        touches: [new Touch({ identifier: 1, target: el, clientX: curX, clientY: y })],
        bubbles: true,
        cancelable: true,
      });
      el.dispatchEvent(touchMove);
    }
    const touchEnd = new TouchEvent('touchend', {
      touches: [],
      bubbles: true,
      cancelable: true,
    });
    el.dispatchEvent(touchEnd);
  }, { startX, y, boxWidth: box.width });

  await page.waitForTimeout(400);
  await page.screenshot({ path: '/tmp/v2-swipe-real.png', fullPage: false });
  console.log('OK: /tmp/v2-swipe-real.png');

  await browser.close();
})();
