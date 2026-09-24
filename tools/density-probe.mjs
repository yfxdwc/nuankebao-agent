// density-probe.mjs — 路由密度体检 (P2 baseline)
// 配合 tools/density-report.sh 调用; 也可独立 node tools/density-probe.mjs

import { chromium } from "@playwright/test";
import { mkdirSync } from "node:fs";

const VIEWPORTS = process.env.VIEWPORTS.split(",").map((v) => {
  const [w, h] = v.split("x").map(Number);
  return { name: v, width: w, height: h };
});
const ROUTES = process.env.ROUTES.split(",");
const OUT = process.env.OUT;

const browser = await chromium.launch();
const ctx = await browser.newContext({
  baseURL: "http://127.0.0.1:3003",
});

const results = [];
for (const vp of VIEWPORTS) {
  const page = await ctx.newPage();
  await page.setViewportSize({ width: vp.width, height: vp.height });
  for (const route of ROUTES) {
    const dir = `${OUT}/${vp.name}`;
    mkdirSync(dir, { recursive: true });
    const fname = route.replace(/[/]/g, "_") || "root";
    const shot = `${dir}/${fname}.png`;
    const t0 = Date.now();
    try {
      const resp = await page.goto(`http://127.0.0.1:3003${route}`, {
        waitUntil: "domcontentloaded",
        timeout: 60000,
      });
      await page.waitForLoadState("networkidle", { timeout: 60000 }).catch(() => {});
      await page.waitForTimeout(400);

      const metrics = await page.evaluate(() => {
        // "cards-like" = 有边框或阴影的容器
        // 排除: rounded-full (chip/badge) + 高度 < 32 (小按钮/标签) + 宽度 < 80 (原子元素)
        //   这样 dashboard 的 4 张统计块算 4 张 card, 但每行 8 个 badge 不算 8 张
        const cardsLike = [...document.querySelectorAll("div,section,article")].filter((el) => {
          const cs = getComputedStyle(el);
          const b = parseFloat(cs.borderTopWidth) || 0;
          const sh = cs.boxShadow;
          const hasFrame = (b > 0 && cs.borderTopStyle !== "none") || (sh && sh !== "none");
          if (!hasFrame) return false;
          const r = el.getBoundingClientRect();
          if (r.height < 32 || r.width < 80) return false;
          // 排除 badge / chip (圆角 9999)
          if (parseFloat(cs.borderRadius) > r.height / 2 - 1) return false;
          return true;
        });
        const bodyFont = parseFloat(getComputedStyle(document.body).fontSize);
        const primaryBtn = document.querySelector(
          'button[class*="bg-primary"],a[class*="bg-primary"]',
        );
        const listItems = document.querySelectorAll(
          '[role="listitem"],li,[class*="divide-y"] > *',
        ).length;
        // 真正在视口里可见的「列表行」 (用于「一屏可见行数 ≥ 10」的棘轮).
        //   旧 visibleRows 是 (vh-80)/(font*1.5) 的理论值, 跟实际渲染无关;
        //   这个用 getBoundingClientRect 算的才是真值 —— tools/check-ui-density.sh 用它.
        const rowEls = [...document.querySelectorAll('[class*="divide-y"] > *')].filter(
          (e) => e.getBoundingClientRect().height > 20,
        );
        const vh = window.innerHeight;
        const visibleListRows = rowEls.filter((e) => {
          const b = e.getBoundingClientRect();
          return b.top < vh - 60 && b.bottom > 0;
        }).length;
        return {
          cardsCount: cardsLike.length,
          visibleRows: Math.floor((window.innerHeight - 80) / (bodyFont * 1.5)),
          visibleListRows,                                          // ← B4 新增 (棘轮真值)
          listRowHeight: rowEls.length ? Math.round(rowEls[0].getBoundingClientRect().height) : 0,
          bodyFont,
          primaryBtnHeight: primaryBtn
            ? primaryBtn.getBoundingClientRect().height
            : null,
          listItems,
        };
      });

      await page.screenshot({ path: shot, fullPage: false });
      results.push({
        route,
        viewport: vp.name,
        ok: resp?.status() === 200,
        status: resp?.status() ?? 0,
        loadMs: Date.now() - t0,
        ...metrics,
        screenshot: shot,
      });
    } catch (err) {
      results.push({
        route,
        viewport: vp.name,
        ok: false,
        error: String(err.message).slice(0, 200),
      });
    }
  }
  await page.close();
}
await browser.close();

if (process.env.JSON === "1") {
  process.stdout.write(JSON.stringify(results, null, 2));
} else {
  console.log("\n=== Density probe ===");
  for (const r of results) {
    if (!r.ok) {
      console.log(
        `[${r.viewport}] ${r.route.padEnd(32)} FAIL ${r.status || ""} ${r.error || ""}`,
      );
      continue;
    }
    const cards = String(r.cardsCount).padStart(3);
    const rows = String(r.visibleRows ?? "-").padStart(3);
    const font = r.bodyFont.toFixed(0).padStart(2);
    const btnH = r.primaryBtnHeight ? r.primaryBtnHeight.toFixed(0) : "-";
    const list = String(r.listItems).padStart(3);
    const load = String(r.loadMs).padStart(5);
    console.log(
      `[${r.viewport}] ${r.route.padEnd(32)} cards=${cards} rows=${rows} font=${font}px btnH=${btnH}px list=${list} load=${load}ms`,
    );
  }
  console.log("---");
  console.log("B-target (mobile 375x812): rows>=18 font=15 btnH=48 cards<=3");
  console.log("B-target (desktop 1440x900): cards<=5 btnH=48");
  console.log(`Shots: ${OUT}`);
}
