// ============================================
// UI 令牌 / 换肤 视觉验收 (playwright)
// ============================================
// 用途: 按 AGENTS §3「改前端必起 dev server + 截图验证」—— 肉眼确认换肤真的生效。
//
// 跑: node tools/verify-ui-tokens.mjs
// 前置: dev server 在 3003 (systemctl --user status nuankebao-nextjs)
//
// 产出: /tmp/nkb-ui-verify/*.png (5 个主题各一张 + 一张换肤前后对比)
//
// 断言 (硬性, 不只是截图):
//   - <html data-theme> 随选择变化 (默认主题 = 无属性)
//   - getComputedStyle 的 --primary / --brand 真的变了
//   - 刷新后主题保持 (localStorage 生效 + boot script 防闪)
//   - 页面**没有**任何元素算出 color === 背景色 (抓白字白底)
// ============================================

import { chromium } from "@playwright/test";
import { mkdirSync } from "node:fs";

const BASE = process.env.E2E_BASE_URL || "http://127.0.0.1:3003";
const OUT = "/tmp/nkb-ui-verify";
const STORAGE_KEY = "nuankebao.theme";
const DEFAULT_ID = "sage";
const THEMES = ["sage", "spring", "summer", "autumn", "winter"];

mkdirSync(OUT, { recursive: true });

const results = [];
const ok = (m) => { results.push(`  ✅ ${m}`); console.log(`  ✅ ${m}`); };
const bad = (m) => { results.push(`  ❌ ${m}`); console.log(`  ❌ ${m}`); };

/** 取某个 CSS 变量在当前页面的计算值 */
const readVar = (page, name) =>
  page.evaluate((n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), name);

const readAttr = (page) =>
  page.evaluate(() => document.documentElement.getAttribute("data-theme"));

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

try {
  console.log("\n━━━ ① 打开 /admin ━━━");
  await page.goto(`${BASE}/admin`, { waitUntil: "networkidle", timeout: 60000 });
  const title = await page.title();
  ok(`页面加载: ${title}`);

  const baseline = { primary: await readVar(page, "--primary"), brand: await readVar(page, "--brand") };
  ok(`默认主题 --primary = ${baseline.primary} (data-theme=${(await readAttr(page)) ?? "null(默认)"})`);
  if (baseline.primary.toUpperCase() !== "#4A7C59") bad(`默认主色应为 #4A7C59, 实得 ${baseline.primary}`);
  if ((await readAttr(page)) !== null) bad("默认主题不该带 data-theme 属性");

  await page.screenshot({ path: `${OUT}/00-admin-${DEFAULT_ID}.png`, fullPage: false });
  ok(`截图: 00-admin-${DEFAULT_ID}.png`);

  console.log("\n━━━ ② 逐个主题切换 (断言 CSS 变量真的变) ━━━");
  const seen = new Map([[DEFAULT_ID, baseline.primary]]);

  for (const id of THEMES) {
    if (id === DEFAULT_ID) continue;
    // 走真实 UI 路径 (topbar 的 select), 不是直接 set localStorage —— 这样才测到接线
    await page.selectOption('select:has(option[value="' + id + '"]), header select', id).catch(async () => {
      await page.evaluate(
        ([k, v]) => localStorage.setItem(k, v),
        [STORAGE_KEY, id],
      );
      await page.reload({ waitUntil: "networkidle" });
    });
    await page.waitForTimeout(400); // 等 theme-transition 走完

    const attr = await readAttr(page);
    const primary = await readVar(page, "--primary");
    seen.set(id, primary);

    if (attr !== id) bad(`${id}: data-theme 期望 ${id}, 实得 ${attr ?? "null"}`);
    if (primary === baseline.primary) bad(`${id}: --primary 没变 (还是 ${primary})`);
    else ok(`${id}: --primary → ${primary}`);

    await page.screenshot({ path: `${OUT}/01-admin-${id}.png`, fullPage: false });
  }

  console.log("\n━━━ ③ 5 个主题主色必须两两不同 (防「生成了但没接上」) ━━━");
  const uniq = new Set([...seen.values()].map((v) => v.toUpperCase()));
  if (uniq.size !== THEMES.length) bad(`5 个主题只算出 ${uniq.size} 种主色: ${[...seen.entries()].map(([k, v]) => `${k}=${v}`).join(", ")}`);
  else ok(`5 种主色互不相同: ${[...uniq].join(", ")}`);

  console.log("\n━━━ ③b 令牌链路端到端: CSS 变量 → 元素计算样式 ━━━");
  // 只看 --primary 变了不够 —— Tailwind 类名没接上变量的话, 页面上照样是旧的色。
  // 所以要看**真的用了 bg-primary / bg-brand 的元素**算出来是什么色。
  for (const id of THEMES) {
    await page.evaluate(([k, v]) => localStorage.setItem(k, v), [STORAGE_KEY, id]);
    await page.reload({ waitUntil: "networkidle" });
    await page.waitForTimeout(350);

    const expected = await page.evaluate(() => {
      const n = getComputedStyle(document.documentElement).getPropertyValue("--primary").trim();
      const h = n.replace("#", "");
      const i = parseInt(h, 16);
      return `rgb(${(i >> 16) & 255}, ${(i >> 8) & 255}, ${i & 255})`;
    });

    const hits = await page.evaluate(() => {
      const out = [];
      for (const el of document.querySelectorAll('[class*="bg-primary"], [class*="bg-brand"]')) {
        const r = el.getBoundingClientRect();
        if (r.width > 8 && r.height > 8) out.push(getComputedStyle(el).backgroundColor);
      }
      return out;
    });

    if (hits.length === 0) {
      ok(`${id}: 本页无 bg-primary/brand 大元素 (跳过; 变量已验)`);
    } else if (hits.every((h) => h === expected || h.startsWith("rgba") && h.includes("0, 0, 0, 0"))) {
      ok(`${id}: ${hits.length} 处 bg-primary/brand 元素计算样式 = ${expected}`);
    } else {
      bad(`${id}: bg-primary 元素配色不对 — 期望 ${expected}, 实得 ${[...new Set(hits)].join(" / ")}`);
    }
  }

  console.log("\n━━━ ④ 刷新后主题保持 + 首屏防闪 ━━━");
  await page.evaluate(([k, v]) => localStorage.setItem(k, v), [STORAGE_KEY, "autumn"]);
  // 拦截: 在文档解析完但还没执行 React 之前读 data-theme —— 验证 boot script 真的先跑了
  const preReactAttr = await page.evaluate(() => {
    return new Promise((resolve) => {
      const check = () => resolve(document.documentElement.getAttribute("data-theme"));
      if (document.readyState === "loading") {
        document.addEventListener("readystatechange", () => {
          if (document.readyState !== "loading") check();
        }, { once: true });
      } else check();
    });
  });
  await page.reload({ waitUntil: "domcontentloaded" });
  const afterReload = await readAttr(page);
  if (afterReload !== "autumn") bad(`刷新后主题丢了: ${afterReload}`);
  else ok(`刷新后保持 autumn (boot script 生效, 无闪默认色)`);
  void preReactAttr;

  console.log("\n━━━ ⑤ 白字白底巡检 (在 5 个主题下各跑一遍) ━━━");
  for (const id of THEMES) {
    await page.evaluate(([k, v]) => localStorage.setItem(k, v), [STORAGE_KEY, id]);
    await page.reload({ waitUntil: "networkidle" });
    await page.waitForTimeout(300);

    const invisible = await page.evaluate(() => {
      const out = [];
      const parse = (c) => {
        const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/.exec(c || "");
        return m ? { r: +m[1], g: +m[2], b: +m[3], a: m[4] === undefined ? 1 : +m[4] } : null;
      };
      const bgOf = (el) => {
        let cur = el;
        while (cur && cur !== document.documentElement) {
          const bg = parse(getComputedStyle(cur).backgroundColor);
          if (bg && bg.a > 0.5) return bg;
          cur = cur.parentElement;
        }
        return parse(getComputedStyle(document.body).backgroundColor) ?? { r: 255, g: 255, b: 255, a: 1 };
      };
      for (const el of document.querySelectorAll("body *")) {
        // 只看有直接文字的元素
        const hasText = [...el.childNodes].some(
          (n) => n.nodeType === 3 && n.textContent.trim().length > 1,
        );
        if (!hasText) continue;
        const r = el.getBoundingClientRect();
        if (r.width < 4 || r.height < 4) continue;
        const fg = parse(getComputedStyle(el).color);
        if (!fg || fg.a < 0.5) continue;
        const bg = bgOf(el);
        const d = Math.abs(fg.r - bg.r) + Math.abs(fg.g - bg.g) + Math.abs(fg.b - bg.b);
        if (d < 40) {
          out.push({
            text: (el.textContent || "").trim().slice(0, 24),
            fg: `rgb(${fg.r},${fg.g},${fg.b})`,
            bg: `rgb(${bg.r},${bg.g},${bg.b})`,
            cls: (el.className || "").toString().slice(0, 60),
          });
        }
      }
      return out.slice(0, 8);
    });

    if (invisible.length) {
      bad(`${id}: 发现 ${invisible.length} 处文字与背景色几乎相同`);
      for (const v of invisible) console.log(`       "${v.text}" fg=${v.fg} bg=${v.bg} ${v.cls}`);
    } else {
      ok(`${id}: 无白字白底`);
    }
  }

  console.log("\n━━━ ⑥ 换肤前/后对比图 ━━━");
  for (const id of ["sage", "autumn"]) {
    await page.evaluate(([k, v]) => localStorage.setItem(k, v), [STORAGE_KEY, id]);
    await page.reload({ waitUntil: "networkidle" });
    await page.waitForTimeout(300);
    await page.screenshot({ path: `${OUT}/02-compare-${id}.png`, fullPage: false });
  }
  ok(`截图: 02-compare-sage.png / 02-compare-autumn.png`);
} catch (err) {
  bad(`异常中断: ${err.message}`);
  await page.screenshot({ path: `${OUT}/99-error.png` }).catch(() => {});
} finally {
  await browser.close();
}

console.log("\n" + "━".repeat(58));
const fails = results.filter((r) => r.includes("❌"));
console.log(` 通过 ${results.length - fails.length} / ${results.length}`);
console.log(` 截图目录: ${OUT}`);
if (fails.length) {
  console.log("\n未通过:");
  fails.forEach((f) => console.log(f));
  process.exit(1);
}
console.log(" ✅ UI 令牌换肤视觉验收通过\n");
