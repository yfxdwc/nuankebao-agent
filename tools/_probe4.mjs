import { chromium } from "@playwright/test";
const b = await chromium.launch();
const p = await b.newPage();
const want = { sage:"#4A7C59", spring:"#5A7D3C", summer:"#2F7A72", autumn:"#A65E24", winter:"#8C4A4A" };
for (const [id, hex] of Object.entries(want)) {
  await p.goto("http://localhost:3003/admin", { waitUntil: "networkidle" });
  await p.evaluate(([k,v])=>localStorage.setItem(k,v), ["nuankebao.theme", id]);
  await p.reload({ waitUntil: "networkidle" });
  await p.waitForTimeout(350);
  const got = (await p.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--primary").trim())).toUpperCase();
  const meta = await p.evaluate(() => document.querySelector('meta[name="theme-color"]')?.content);
  const status = got === hex && meta === hex ? "✅" : "❌";
  console.log(`  ${id.padEnd(7)} --primary=${got.padEnd(9)} theme-color=${meta}  期望=${hex}  ${status}`);
}
await b.close();
