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
  // 直接到"全部" filter
  await page.goto('http://192.168.1.200:3010/admin/follow-ups?filter=all', { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);

  // 模拟左滑第一张卡片
  const card = page.locator('[aria-label*="跟进"]').first().locator('..').locator('> div').first();
  // 直接用 page 触屏 API
  const box = await page.locator('text=全部').first().boundingBox();
  console.log('chip box:', box);

  // 用 page.mouse 模拟
  const cardBox = await page.locator('text=/[A-Za-z一-龥]/').first().boundingBox();
  console.log('first text box:', cardBox);

  // 找到第一个任务卡片 (有 "X 位待跟进" 那种)
  const taskCard = await page.locator('.border, .border-rose-200').filter({ has: page.locator('text=/今天|周|逾期|全部/') }).first();
  // 简单点: 找最上面一张 card
  const firstCard = page.locator('main .rounded-lg, main [class*="Card"]').first();
  const fbox = await firstCard.boundingBox();
  console.log('first card box:', fbox);

  if (fbox) {
    // 模拟左滑: 起点 x=350, 终点 x=200
    await page.touchscreen.tap(fbox.x + fbox.width - 20, fbox.y + 30);
    await page.waitForTimeout(100);
    // 用 mouse swipe (更可靠)
    await page.mouse.move(fbox.x + fbox.width - 30, fbox.y + 30);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++) {
      await page.mouse.move(
        fbox.x + fbox.width - 30 - i * 20,
        fbox.y + 30
      );
      await page.waitForTimeout(20);
    }
    await page.mouse.up();
    await page.waitForTimeout(300);
  }

  await page.screenshot({ path: '/tmp/v2-follow-swipe.png', fullPage: false });
  console.log('OK: /tmp/v2-follow-swipe.png');
  await browser.close();
})();
