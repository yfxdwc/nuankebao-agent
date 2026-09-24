// ============================================
// UI 验收探针 (web admin) —— 登录后逐路由采集「布局语义」指标
// ============================================
//
// 为什么不用 tools/density-probe.mjs 的 cardsLike:
//   src/components/ui/card.tsx 早在 c32c741 就把 default 变体改成「无边框无阴影」,
//   所以 cardsLike 恒为 ~0, 真假不分。真正会退化的是**布局语义** —— 字号越档、
//   行高变胖、KPI tile 墙回潮、双层标题。本探针量的是这些。
//
// 用法:
//   node tools/ui-acceptance-probe.mjs                     # 默认 13822200001 / Test12345
//   ROUTES="/admin,/admin/customers" node tools/ui-acceptance-probe.mjs
//   NKB_IDENT=xxx NKB_PW=yyy node tools/ui-acceptance-probe.mjs
//   JSON=1 node tools/ui-acceptance-probe.mjs > /tmp/out.json
//
// ⚠ 前置: dev server (3003) 或 prod server 活着。prod 模式没有 DEV_SKIP_AUTH 旁路,
//   必须带登录; dev 模式 (DEV_SKIP_AUTH=1) 登录也照样能用 (更接近真实)。
// ⚠ 不要并发跑多个实例 —— dev server 会在 cgroup 内存上限卡死 (见 AGENTS §5)。
// ============================================

import { chromium } from "@playwright/test";
import { mkdirSync } from "node:fs";

const BASE = process.env.E2E_BASE_URL || "http://127.0.0.1:3003";
const IDENT = process.env.NKB_IDENT || "13822200001";
const PW = process.env.NKB_PW || "Test12345";
const JSON_OUT = process.env.JSON === "1";
const OUT = process.env.OUT_DIR || "/tmp/nkb-ui-acceptance";
const VIEWPORTS = (process.env.VIEWPORTS || "1440x900,375x812").split(",").map((v) => {
  const [w, h] = v.split("x").map(Number);
  return { name: v, width: w, height: h };
});
const ROUTES = (
  process.env.ROUTES ||
  "/admin,/admin/customers,/admin/wellness-records,/admin/follow-ups,/admin/interactions,/admin/reports,/admin/usage,/admin/import,/admin/ai,/admin/download,/admin/plan,/admin/settings/insight"
).split(",");

// 令牌字号档位 (design-tokens.json scales.type)
const TOKEN_SIZES = new Set(["11px", "12px", "13px", "15px", "17px", "20px", "28px"]);

mkdirSync(OUT, { recursive: true });

// ---- 第一阶段: 登录 (独立浏览器, 崩了也不影响探测) ----
// ⚠ dev 环境登录页会抛 `TypeError: Failed to construct 'URL': Invalid URL`
//   (AUTH_URL 指向隧道域名 —— 登录排查文档同族问题, 与本轮 UI 改动无关),
//   实测会把整个 chromium 带崩 → 所以登录必须跟探测**分开两个浏览器**。
let storageState = undefined;
let loggedIn = false;
{
  const b1 = await chromium.launch();
  const c1 = await b1.newContext({ baseURL: BASE });
  const lp = await c1.newPage();
  try {
    await lp.goto("/login", { waitUntil: "domcontentloaded", timeout: 45000 });
    await lp.waitForLoadState("networkidle", { timeout: 20000 }).catch(() => {});
    for (let i = 0; i < 10; i++) {
      await lp.fill("#identifier", IDENT);
      await lp.fill("#password", PW);
      const enabled = await lp
        .locator('button[type="submit"]')
        .isEnabled()
        .catch(() => false);
      if (enabled) break;
      await lp.waitForTimeout(1000);
    }
    await lp.click('button[type="submit"]');
    await lp.waitForURL(/\/admin/, { timeout: 20000 });
    loggedIn = true;
    storageState = await c1.storageState().catch(() => undefined);
  } catch {
    loggedIn = false;
  }
  await b1.close().catch(() => {});
}

// ---- 第二阶段: 探测 ----
const browser = await chromium.launch();
const ctx = await browser.newContext({ baseURL: BASE, storageState });

if (!loggedIn) {
  // dev 模式有 DEV_SKIP_AUTH=1 旁路 → /admin 匿名可读, 不必卡在登录上。
  const probe = await ctx.newPage();
  const code = await probe
    .goto("/admin", { waitUntil: "domcontentloaded", timeout: 30000 })
    .then((r) => r?.status())
    .catch(() => 0);
  const ok = code === 200 && /\/admin/.test(probe.url());
  await probe.close();
  if (ok) {
    console.warn(`⚠ 登录失败, 但 /admin 匿名可读 (DEV_SKIP_AUTH=1) → 继续采集`);
  } else {
    console.error(`✗ 登录失败 (${IDENT}) 且 /admin 匿名不可读 (HTTP ${code}) —— 指标不可信`);
    await browser.close();
    process.exit(2);
  }
}

const rows = [];
for (const vp of VIEWPORTS) {
  const page = await ctx.newPage();
  await page.setViewportSize({ width: vp.width, height: vp.height });
  for (const route of ROUTES) {
    const t0 = Date.now();
    let http = 0;
    try {
      const resp = await page.goto(route, { waitUntil: "domcontentloaded", timeout: 45000 });
      http = resp?.status() ?? 0;
      await page.waitForLoadState("networkidle", { timeout: 20000 }).catch(() => {});
    } catch {
      http = -1;
    }
    const m = await page
      .evaluate(() => {
        const vis = (el) => {
          const r = el.getBoundingClientRect();
          const cs = getComputedStyle(el);
          return r.width > 0 && r.height > 0 && cs.visibility !== "hidden" && cs.display !== "none";
        };
        // 字号档位 (只取叶子文字节点, 避免父元素重复计)
        const sizes = {};
        document.querySelectorAll("h1,h2,h3,h4,p,span,a,td,th,li,button,label,dt,dd,div").forEach((el) => {
          const t = el.textContent?.trim();
          if (!t || el.children.length > 0 || !vis(el)) return;
          const s = getComputedStyle(el).fontSize;
          sizes[s] = (sizes[s] || 0) + 1;
        });
        // 有边框/阴影的容器
        const framed = [...document.querySelectorAll("div,section,article")].filter((el) => {
          const cs = getComputedStyle(el);
          const bw = parseFloat(cs.borderTopWidth) || 0;
          const sh = cs.boxShadow;
          if (!((bw > 0 && cs.borderTopStyle !== "none") || (sh && sh !== "none"))) return false;
          const r = el.getBoundingClientRect();
          if (r.height < 32 || r.width < 80) return false;
          return !(parseFloat(cs.borderRadius) > r.height / 2 - 1);
        }).length;
        // 列表行 (divide-y 子项) 的行高 + 首屏可见数
        const rowEls = [...document.querySelectorAll('[class*="divide-y"] > *')].filter(
          (e) => e.getBoundingClientRect().height > 20,
        );
        const vh = window.innerHeight;
        const visibleRows = rowEls.filter((e) => {
          const b = e.getBoundingClientRect();
          return b.top < vh - 60 && b.bottom > 0;
        }).length;
        return {
          h1Count: document.querySelectorAll("h1").length,
          h1Text: document.querySelector("h1")?.textContent?.slice(0, 24) ?? null,
          fontSizes: Object.keys(sizes).map(parseFloat).sort((a, b) => a - b),
          framed,
          rowCount: rowEls.length,
          rowHeight: rowEls.length ? Math.round(rowEls[0].getBoundingClientRect().height) : 0,
          visibleRows,
          kpiTiles: document.querySelectorAll('[class*="grid-cols-4"] > *').length,
          scrollW: document.documentElement.scrollWidth,
          clientW: document.documentElement.clientWidth,
        };
      })
      .catch(() => ({}));

    const offToken = (m.fontSizes || [])
      .map((s) => `${s}px`)
      .filter((s) => !TOKEN_SIZES.has(s));
    rows.push({
      viewport: vp.name,
      route,
      ms: Date.now() - t0,
      http,
      offToken,
      overflow: (m.scrollW || 0) > (m.clientW || 0) + 1 ? (m.scrollW || 0) - (m.clientW || 0) : 0,
      ...m,
    });

    await page
      .screenshot({ path: `${OUT}/${vp.name}${route.replace(/\//g, "_")}.png`, fullPage: vp.name === "1440x900" })
      .catch(() => {});
  }
  await page.close();
}

if (JSON_OUT) {
  console.log(JSON.stringify({ generatedAt: new Date().toISOString(), base: BASE, rows }, null, 1));
} else {
  console.log(`\n路由                          视口        HTTP  字号档                 越档      框/影 行高 可见行 h1 KPI 溢出  ms`);
  for (const r of rows) {
    console.log(
      `${r.route.padEnd(28)} ${String(r.viewport).padEnd(10)} ${String(r.http).padEnd(5)} ` +
        `${(r.fontSizes || []).join("/").padEnd(22)} ${(r.offToken.join(",") || "·").padEnd(8)} ` +
        `${String(r.framed).padEnd(5)} ${String(r.rowHeight ?? "-").padEnd(4)} ${String(r.visibleRows ?? "-").padEnd(5)} ` +
        `${String(r.h1Count).padEnd(2)} ${String(r.kpiTiles ?? "-").padEnd(3)} ${String(r.overflow || "ok").padEnd(5)} ${r.ms}`,
    );
  }
  console.log(`\n截图目录: ${OUT}/`);
}
await browser.close();
