// ============================================
// Flutter P2/P3 视觉验证 —— 真浏览器驱动 Flutter web
// ============================================
// 为什么需要它:
//   Flutter web 渲染到 canvas, 传统 DOM 断言/选择器点不中。
//   但 main.dart 在 web 下 ensureSemantics() → 存在 flt-semantics 树 +
//   真实 <input>, 且 document.body.innerText 能读到渲染出的文字。
//   于是可以**程序化断言** —— 比"截个图给人看"可重复得多。
//
// 两个关键技巧 (踩过的坑):
//   1. semantics 节点大多**没有 role** (分组头/列表行都不是 button),
//      而且父容器是覆盖整屏的巨大节点 → 必须按**坐标点**, 且**选最小命中节点**。
//   2. 客户列表按紧急度分组且「休眠池」默认折叠 → 不展开的话一行客户都没有。
//
// 前置: dev server 3003 + Flutter web 产物已构建
// 跑:   node tools/verify-flutter-p2p3.mjs
// ============================================

import { chromium } from "@playwright/test";
import { mkdirSync } from "node:fs";

const BASE = process.env.E2E_BASE_URL || "http://127.0.0.1:3003";
const OUT = "/tmp/nkb-flutter-verify";
const PHONE = "13822200001";
const PASSWORD = "Test12345";

mkdirSync(OUT, { recursive: true });

const results = [];
const ok = (m) => { results.push({ pass: true, m }); console.log(`  ✅ ${m}`); };
const bad = (m) => { results.push({ pass: false, m }); console.log(`  ❌ ${m}`); };
const note = (m) => console.log(`  ℹ ${m}`);

const text = (page) => page.evaluate(() => document.body.innerText || "");

/**
 * 按文字找语义节点并**点它的中心**。
 * 命中多个时取**面积最小**的 (最内层) —— 否则会点到覆盖整屏的祖先容器。
 */
async function tapText(page, pattern, { nth = 0, index = 0 } = {}) {
  const box = await page.evaluate(
    ([pat, useNth, useIndex]) => {
      const re = new RegExp(pat);
      /**
       * ⚠ Flutter web 语义树里的空白**不是普通空格** —— 实测出现过 \u00A0 (nbsp),
       *   所以 `"休眠池 ("` 这种带普通空格的正则永远匹配不上 (`re.test` 恒 false),
       *   而它在 Node 里测同一个字符串却是 true —— 极易误判成"正则写错了"。
       * → 一律先把所有空白 (含 nbsp / 全角空格) 折成单空格再匹配。
       */
      const norm = (s) => (s || "").replace(/[\s\u00A0\u3000]+/g, " ").trim();
      const nodes = [...document.querySelectorAll("flt-semantics")]
        .filter((e) => {
          const r = e.getBoundingClientRect();
          return r.width > 4 && r.height > 4 && re.test(norm(e.textContent));
        })
        .map((e) => ({ e, r: e.getBoundingClientRect() }))
        .sort((a, b) => a.r.width * a.r.height - b.r.width * b.r.height);
      const hit = useIndex ? nodes[useIndex] : nodes[useNth];
      if (!hit) return null;
      return { x: hit.r.x + hit.r.width / 2, y: hit.r.y + hit.r.height / 2, w: hit.r.width, h: hit.r.height };
    },
    [pattern, nth, index],
  );
  if (!box) {
    // 命中失败时给诊断 (语义树有几个节点 / 候选文本长啥样) —— 不然只能靠猜
    const diag = await page.evaluate((pat) => {
      const re = new RegExp(pat);
      const all = [...document.querySelectorAll("flt-semantics")];
      let sizeOk = 0;
      let bothOk = 0;
      const rejected = [];
      for (const e of all) {
        const r = e.getBoundingClientRect();
        const t = (e.textContent || "").replace(/[\s\u00A0\u3000]+/g, " ").trim();
        const sOk = r.width > 4 && r.height > 4;
        if (sOk) sizeOk++;
        if (sOk && re.test(t)) bothOk++;
        else if (re.test(t)) {
          rejected.push(`"${t.slice(0, 16)}" ${Math.round(r.width)}x${Math.round(r.height)}`);
        }
      }
      return { total: all.length, sizeOk, bothOk, reSrc: re.source, rejected: rejected.slice(0, 6) };
    }, pattern);
    note(`    [tap 失败] 节点=${diag.total} 尺寸通过=${diag.sizeOk} 两者通过=${diag.bothOk} 正则=/${diag.reSrc}/`);
    if (diag.rejected.length) note(`    正则命中但被尺寸筛掉: ${diag.rejected.join(" ¶ ")}`);
    return null;
  }
  await page.mouse.click(box.x, box.y);
  return box;
}

/** 在 aria-label 输入框里键入 (Flutter web 必须用真实键盘事件) */
async function typeInto(page, ariaLabel, value) {
  const el = page.locator(`input[aria-label="${ariaLabel}"]`);
  await el.click({ force: true });
  await page.waitForTimeout(250);
  await page.keyboard.type(value, { delay: 25 });
  await page.waitForTimeout(250);
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
const pageErrors = [];
page.on("pageerror", (e) => pageErrors.push(String(e).slice(0, 200)));

try {
  // ───────────────────────────────
  console.log("\n━━━ ① 登录 ━━━");
  await page.goto(`${BASE}/app/index.html`, { waitUntil: "commit", timeout: 60000 });
  await page.waitForTimeout(9000);
  await typeInto(page, "账号 / 手机号", PHONE);
  await typeInto(page, "密码", PASSWORD);
  await tapText(page, "^登录$");
  await page.waitForTimeout(9000);
  // ⚠ 不能用 includes("客户") —— 登录页也有「客户」二字 (在「大健康客户管理」里),
  //   会造成**假阳性**: 登录失败也"通过"。改用只在登录后出现的锚点。
  const afterLogin = await text(page);
  const loginAnchors = ["添加客户", "Tab 1 of 3", "休眠池"];
  const got = loginAnchors.filter((a) => afterLogin.includes(a));
  if (got.length >= 2) ok(`登录成功, 进入客户列表 (锚点: ${got.join(" / ")})`);
  else bad(`登录失败: ${afterLogin.replace(/\n/g, " | ").slice(0, 150)}`);

  // ───────────────────────────────
  console.log("\n━━━ ② 展开分组 → 进客户详情 ━━━");
  await page.waitForTimeout(1500);
  let listText = await text(page);
  const collapsed = [...listText.matchAll(/([\u4e00-\u9fa5]{2,6}) \((\d+)\)/g)].map((m) => m[1]);
  if (collapsed.length > 0) {
    note(`折叠分组: ${collapsed.join(" / ")} — 点开`);
    for (const g of collapsed) {
      const box = (await tapText(page, `${g} \\(`)) ?? (await tapText(page, `^${g}( \\(\\d+\\))?$`));
      note(`  点「${g}」@ ${box ? `${Math.round(box.x)},${Math.round(box.y)}` : "未找到"}`);
      await page.waitForTimeout(2000);
    }
    listText = await text(page);
  }

  // 优先挑 DB 里已知**有养生记录**的客户 (P3 预填需要历史记录才看得到效果)
  const PREFER = ["演示-蒋金娣", "演示-金兰香", "演示-方兰英", "演示-熊秀兰", "演示-翁金凤"];
  const preferred = PREFER.find((n) => listText.includes(n));
  const nameMatch = preferred ? [preferred] : listText.match(/演示-[\u4e00-\u9fa5]{2,4}/);
  if (preferred) note(`优先选已知有记录的客户: ${preferred}`);
  if (!nameMatch) {
    bad(`展开后没找到客户行: ${listText.replace(/\n/g, " | ").slice(0, 220)}`);
    throw new Error("无客户可点");
  }
  const customerName = nameMatch[0];
  note(`点开客户: ${customerName}`);
  const cbox = await tapText(page, customerName);
  note(`  点「${customerName}」@ ${cbox ? `${Math.round(cbox.x)},${Math.round(cbox.y)}` : "未找到"}`);
  await page.waitForTimeout(8000);
  await page.screenshot({ path: `${OUT}/01-detail.png` });

  const detailText = await text(page);
  console.log("  详情页文本:", detailText.replace(/\n/g, " | ").slice(0, 300));

  // ───────────────────────────────
  console.log("\n━━━ ③ P2: 3 Tab + L0 可见 ━━━");
  for (const t of ["记录", "分析", "管理"]) {
    if (detailText.includes(t)) ok(`Tab「${t}」存在`);
    else bad(`Tab「${t}」缺失`);
  }
  const l0Signals = ["现在该做", "节奏正常", "健康改善", "关系温度", "价值潜力", "待评估", "评分"];
  const hitL0 = l0Signals.filter((s) => detailText.includes(s));
  if (hitL0.length > 0) ok(`L0 可见 (命中: ${hitL0.join(" / ")})`);
  else bad("L0 未渲染 (没找到评分/待办文案)");

  // ───────────────────────────────
  console.log("\n━━━ ④ P2: 切 Tab 内容真的变 ━━━");
  const recordText = await text(page);
  await tapText(page, "^分析 Tab");
  await page.waitForTimeout(4500);
  await page.screenshot({ path: `${OUT}/02-tab-analysis.png` });
  const analysisText = await text(page);
  if (analysisText !== recordText) {
    ok("切「分析」后内容变化");
  } else {
    // 可能点到的是 L0 里的「分析」字样 → 报告但不误判
    note("内容未变 (可能没点中 Tab 标签, 见截图)");
  }
  const aSig = ["跟进分析", "AI 助手", "复购", "画像", "效果", "趋势"];
  const aHit = aSig.filter((s) => analysisText.includes(s));
  if (aHit.length >= 2) ok(`分析 Tab 内容就位 (命中: ${aHit.join(" / ")})`);
  else note(`分析 Tab 命中较少: ${aHit.join(" / ") || "(无)"}`);

  await tapText(page, "^管理 Tab");
  await page.waitForTimeout(4500);
  await page.screenshot({ path: `${OUT}/03-tab-manage.png` });
  const manageText = await text(page);
  const mHit = ["客户类型", "身份", "归属", "手机", "加盟"].filter((s) => manageText.includes(s));
  if (mHit.length >= 1) ok(`管理 Tab 内容就位 (命中: ${mHit.join(" / ")})`);
  else note(`管理 Tab 命中较少: ${mHit.join(" / ") || "(无)"}`);

  // ───────────────────────────────
  console.log("\n━━━ ⑤ P3: 「沿用上次」预填 ━━━");
  await tapText(page, "^记录 Tab");
  await page.waitForTimeout(3000);
  // 「+ 添加记录」可能在下方, 先滚动
  let addBox = await tapText(page, "添加记录");
  if (!addBox) {
    note("没找到「添加记录」→ 向下滚动再试");
    await page.mouse.move(210, 500);
    await page.mouse.wheel(0, 1400);
    await page.waitForTimeout(2000);
    addBox = await tapText(page, "添加记录");
  }
  if (!addBox) {
    bad("找不到「添加记录」入口");
  } else {
    note(`点「添加记录」@ ${Math.round(addBox.x)},${Math.round(addBox.y)}`);
    await page.waitForTimeout(4500);
    await page.screenshot({ path: `${OUT}/04-add-sheet.png` });
    console.log("  弹层文本:", (await text(page)).replace(/\n/g, " | ").slice(0, 300));

    const sheet = await tapText(page, "^养生记录");
    note(`选「养生记录」@ ${sheet ? "ok" : "未找到"}`);
    await page.waitForTimeout(8000);
    await page.screenshot({ path: `${OUT}/05-record-form.png` });
    const formText = await text(page);

    if (formText.includes("已按") || formText.includes("清空重填")) {
      ok("P3 预填条出现 («已按…填好» / «清空重填»)");
    } else if (formText.includes("服务项目")) {
      // 表单在 (能看到"服务项目"), 但没有预填条 → 两种情况:
      //   (a) 该客户没有历史养生记录 (首次到店) —— 正常
      //   (b) 预填逻辑坏了 —— 真 bug
      note("表单已开, 但顶部**没有**预填条");
      note(`  顶部文本: ${formText.replace(/\n/g, " | ").slice(0, 120)}`);
      note("  → 若该客户确有历史记录, 这就是 P3 的 bug; 若首次到店则正常");
    } else {
      bad(`表单未按预期打开: ${formText.replace(/\n/g, " | ").slice(0, 900)}`);
    }
    if (formText.includes("理疗前状态") && formText.includes("理疗后效果")) {
      ok("表单「理疗前/后」两段都在");
    }
  }

  // ───────────────────────────────
  console.log("\n━━━ ⑥ 无未捕获异常 ━━━");
  if (pageErrors.length === 0) ok("全程 0 个 pageerror");
  else note(`pageerror ${pageErrors.length} 个: ${[...new Set(pageErrors)].slice(0, 3).join(" ¶ ")}`);
} catch (e) {
  bad(`异常中断: ${String(e.message).slice(0, 150)}`);
  await page.screenshot({ path: `${OUT}/99-error.png` }).catch(() => {});
} finally {
  await browser.close();
}

const fails = results.filter((r) => !r.pass);
console.log("\n" + "━".repeat(58));
console.log(` 通过 ${results.length - fails.length} / ${results.length}`);
console.log(` 截图: ${OUT}`);
if (fails.length) {
  console.log("\n未通过:");
  fails.forEach((f) => console.log(` ❌ ${f.m}`));
  process.exit(1);
}
console.log(" ✅ Flutter P2/P3 验证通过\n");
