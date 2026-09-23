// ============================================
// 设计令牌契约测试 (纯本地, 不需要数据库)
// ============================================
// 守护的东西:
//   ① 单一真相源本身合法 (引用可解析 / 主题槽位对齐 / 对比度达标)
//   ② 生成产物与真相源一致 (没人绕过 pnpm tokens:build 手改 tokens.g.*)
//   ③ 两端真的消费了令牌 (而不是"生成了没人用")
//   ④ 已修掉的坑不再复发 (chip 白字 / hsl() 残留 / 字面 hex 回到 tailwind.config)
//
// 跑: pnpm test:run tests/design-tokens.test.ts
// ============================================

import { describe, it, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";

const ROOT = path.resolve(__dirname, "..");
const rd = (p: string) => readFileSync(path.join(ROOT, p), "utf8");

const doc = JSON.parse(rd("design/tokens/design-tokens.json"));

// ---------- WCAG ----------
function srgbToLinear(c: number): number {
  const v = c / 255;
  return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}
function luminance(hex: string): number {
  const h = hex.replace("#", "");
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return 0.2126 * srgbToLinear(r) + 0.7152 * srgbToLinear(g) + 0.0722 * srgbToLinear(b);
}
function ratio(a: string, b: string): number {
  const la = luminance(a);
  const lb = luminance(b);
  const hi = Math.max(la, lb);
  const lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

function resolveRef(value: string): string {
  const seen: string[] = [];
  let cur: any = value;
  while (typeof cur === "string" && /^\{[^}]+\}$/.test(cur.trim())) {
    const p = cur.trim().slice(1, -1);
    if (seen.includes(p)) throw new Error(`引用成环: ${seen.join(" → ")} → ${p}`);
    seen.push(p);
    cur = p.split(".").reduce((acc: any, seg: string) => acc?.[seg], doc);
    if (cur === undefined) throw new Error(`无法解析 {${p}}`);
  }
  return cur;
}

const palette: Record<string, string> = doc.palette;
const shared: Record<string, string> = Object.fromEntries(
  Object.entries(doc.shared).map(([k, v]) => [k, resolveRef(v as string)]),
);

describe("① 令牌真相源结构", () => {
  it("每个 palette 值都是合法 6 位 hex", () => {
    for (const [k, v] of Object.entries(palette)) {
      expect(v, `palette.${k}`).toMatch(/^#[0-9A-Fa-f]{6}$/);
    }
  });

  it("shared / 各主题里的每个 {引用} 都能解析到 hex", () => {
    const check = (map: Record<string, unknown>, where: string) => {
      for (const [k, v] of Object.entries(map)) {
        expect(resolveRef(v as string), `${where}.${k}`).toMatch(/^#[0-9A-Fa-f]{6}$/);
      }
    };
    check(doc.shared, "shared");
    for (const t of doc.themes) check(t.colors, `themes.${t.id}.colors`);
  });

  it("所有主题覆盖**同一组**品牌槽位 (加主题时漏槽位会在这里炸)", () => {
    const keysets = doc.themes.map(
      (t: any) => Object.keys(t.colors).sort().join(","),
    );
    expect(new Set(keysets).size, "主题之间的品牌槽位不一致").toBe(1);
  });

  it("恰好一个默认主题", () => {
    const defaults = doc.themes.filter((t: any) => t.isDefault === true);
    expect(defaults).toHaveLength(1);
  });

  it("语义别名 (semantic.space / semantic.radius) 指向存在的尺度键", () => {
    for (const target of Object.values(doc.semantic.space)) {
      expect(doc.scales.space, `scales.space 缺 ${target}`).toHaveProperty(target as string);
    }
    for (const target of Object.values(doc.semantic.radius)) {
      expect(doc.scales.radius, `scales.radius 缺 ${target}`).toHaveProperty(target as string);
    }
  });

  it("on* 前景色不许手写 (必须由生成器按对比度推导)", () => {
    for (const t of doc.themes) {
      for (const k of Object.keys(t.colors)) {
        expect(k, `themes.${t.id}.colors.${k} 不该手写`).not.toMatch(/^on[A-Z]/);
      }
    }
    for (const k of Object.keys(doc.shared)) {
      expect(k, `shared.${k} 不该手写`).not.toMatch(/^on[A-Z]/);
    }
  });
});

describe("② 对比度门槛 (WCAG 2.1)", () => {
  const LIGHT = resolveRef(doc.contrast.lightForeground);
  const DARK = resolveRef(doc.contrast.darkForeground);
  const min = doc.contrast.minOnColorRatio;

  /** 复刻生成器的推导规则 */
  const onColor = (bg: string) => (ratio(bg, LIGHT) >= ratio(bg, DARK) ? LIGHT : DARK);

  for (const t of doc.themes) {
    describe(t.label, () => {
      const c: Record<string, string> = Object.fromEntries(
        Object.entries({ ...shared, ...t.colors }).map(([k, v]) => [k, resolveRef(v as string)]),
      );

      it(`primary 底 + 自动推导的前景色 ≥ AA (${min}:1)`, () => {
        expect(ratio(c.primary, onColor(c.primary))).toBeGreaterThanOrEqual(min);
      });

      it(`accent 底 + 自动推导的前景色 ≥ AA (${min}:1)`, () => {
        expect(ratio(c.accent, onColor(c.accent))).toBeGreaterThanOrEqual(min);
      });

      it("正文 / 副文 对背景达 AAA (7:1) —— 中老年可读性底线", () => {
        expect(ratio(c.textPrimary, c.surface), "textPrimary/surface").toBeGreaterThanOrEqual(7);
        expect(ratio(c.textSecondary, c.surface), "textSecondary/surface").toBeGreaterThanOrEqual(7);
      });

      it("卡片上的正文达 AAA", () => {
        expect(ratio(c.textPrimary, c.surfaceCard)).toBeGreaterThanOrEqual(7);
      });

      it("边框在卡片上可见 (≥1.5:1, 太浅等于没画线)", () => {
        expect(ratio(c.border, c.surfaceCard)).toBeGreaterThanOrEqual(1.5);
      });

      it("分隔线比边框轻 (装饰性, ≥1.2:1 即可)", () => {
        const r = ratio(c.divider, c.surfaceCard);
        expect(r, "分隔线对卡片").toBeGreaterThanOrEqual(1.2);
        expect(r, "分隔线不该比边框还重").toBeLessThan(ratio(c.border, c.surfaceCard));
      });

      it("primaryDark 对白字达 AAA (给需要最高对比度的场景留的档)", () => {
        expect(ratio(c.primaryDark, LIGHT)).toBeGreaterThanOrEqual(7);
      });
    });
  }

  it("状态色 (success/warning/danger/info) 的前景色 ≥ AA", () => {
    for (const key of ["success", "warning", "danger", "info"]) {
      const bg = shared[key];
      expect(ratio(bg, onColor(bg)), `${key}/on${key}`).toBeGreaterThanOrEqual(min);
    }
  });

  it("之前修掉的坑: accent 配白字必死 (暖橙对白字只有 2.2:1)", () => {
    const sage = doc.themes.find((t: any) => t.isDefault);
    const accent = resolveRef(sage.colors.accent);
    expect(ratio(accent, "#FFFFFF"), "浅暖橙不该配白字").toBeLessThan(3);
    expect(onColor(accent)).toBe(DARK);
  });
});

describe("③ 生成产物与真相源一致", () => {
  it("pnpm tokens:check 通过 (没人手改 tokens.g.* / globals.css 生成块)", () => {
    try {
      execFileSync("npx", ["tsx", "scripts/generate-tokens.ts", "--check"], {
        cwd: ROOT,
        stdio: "pipe",
      });
    } catch (err: any) {
      throw new Error(
        "生成产物与 design-tokens.json 不一致 —— 跑 `pnpm tokens:build` 后一起提交。\n" +
          (err.stdout?.toString() ?? "") +
          (err.stderr?.toString() ?? ""),
      );
    }
  });

  it("三份产物都存在", () => {
    for (const f of doc.$meta.generatedArtifacts.map((s: string) =>
      s.replace(" (标记注入块)", ""),
    )) {
      // 允许 "src/styles/globals.css" 这类不带括号描述的写法
      const clean = f.split(" ")[0];
      expect(existsSync(path.join(ROOT, clean)), `缺产物 ${clean}`).toBe(true);
    }
  });
});

describe("④ Web 消费侧接线", () => {
  const css = rd("src/styles/globals.css");

  it("globals.css 带生成标记, 且注入块非空", () => {
    const b = css.indexOf("BEGIN GENERATED: design tokens");
    const e = css.indexOf("END GENERATED: design tokens");
    expect(b).toBeGreaterThan(-1);
    expect(e).toBeGreaterThan(b);
    expect(e - b, "注入块是空的 —— 忘了跑 tokens:build?").toBeGreaterThan(2000);
  });

  it("全局已切到 hex + var(): 不再有 hsl(var(--…)) 三元组残留", () => {
    // 我们的 tailwind.config 写的是 `var(--primary)` 而不是 `hsl(var(--primary))`;
    // 如果 CSS 变量还是 HSL 三元组, 颜色会整体失效 (反过来说也一样)
    for (const name of ["--primary", "--background", "--border"]) {
      const m = new RegExp(`${name}:\\s*([^;]+);`).exec(css);
      expect(m, `globals.css 缺 ${name}`).toBeTruthy();
      expect(m![1].trim(), `${name} 还是 HSL 三元组?`).toMatch(/^#/);
    }
  });

  it("shadcn 兼容层变量一个不少 (607 处存量用法依赖)", () => {
    const required = [
      "--background", "--foreground", "--card", "--card-foreground",
      "--primary", "--primary-foreground", "--secondary", "--secondary-foreground",
      "--muted", "--muted-foreground", "--accent", "--accent-foreground",
      "--destructive", "--destructive-foreground", "--border", "--input", "--ring", "--radius",
    ];
    for (const v of required) {
      expect(css, `缺 shadcn 变量 ${v}`).toContain(`${v}:`);
    }
  });

  it("每个主题都有一份 [data-theme] 覆盖块 (默认主题靠 :root)", () => {
    for (const t of doc.themes) {
      if (t.isDefault) continue;
      expect(css, `缺 [data-theme="${t.id}"]`).toContain(`[data-theme="${t.id}"]`);
    }
  });

  it("tailwind.config 里没有任何字面色值 (只允许 var(...) / 结构值)", () => {
    const tw = rd("tailwind.config.ts");
    // 去掉注释再找 hex
    const noComments = tw.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
    expect(noComments, "tailwind.config 里出现了字面 hex 色值").not.toMatch(/#[0-9A-Fa-f]{3,8}\b/);
  });

  it("缩放旋钮存在 (改 --density 一个数就能整体调间距)", () => {
    expect(css).toMatch(/--density:\s*[\d.]+/);
    expect(css).toMatch(/--space-16:\s*calc\([^)]*var\(--density\)/);
  });
});

describe("⑤ Flutter 消费侧接线", () => {
  const dart = rd("flutter_app/lib/core/theme/tokens.g.dart");
  const theme = rd("flutter_app/lib/core/theme/app_theme.dart");

  it("tokens.g.dart 生成了主题目录 + 全部主题实例", () => {
    expect(dart).toContain("abstract final class AppThemes");
    for (const t of doc.themes) {
      expect(dart, `缺主题实例 ${t.id}`).toContain(`static const AppTokens ${t.id}`);
    }
  });

  it("AppTheme 里没有任何字面色值 (含 inputBorder 那个 #D0D0D0)", () => {
    const noComments = theme.replace(/\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "");
    // 兼容层常量是刻意的白名单: 只允许出现在文件上半部分的 "兼容层" 段
    const compatEnd = noComments.indexOf("ColorScheme colorSchemeOf");
    expect(compatEnd).toBeGreaterThan(0);
    const assembling = noComments.slice(compatEnd);
    expect(assembling, "AppTheme 装配段出现字面 hex").not.toMatch(/Color\(0x/);
  });

  it("chipTheme 的 labelStyle / secondaryLabelStyle 都显式写了 color", () => {
    // 2026-09-22 主人报的「字号档位 chip 白字」就是这个 —— 不带主题的 widget test 测不出来
    const chip = dart + theme;
    expect(chip).toMatch(/chipTheme:[\s\S]*?labelStyle:\s*TextStyle\([^)]*color:/);
    expect(chip).toMatch(/chipTheme:[\s\S]*?secondaryLabelStyle:\s*TextStyle\([^)]*color:/);
  });

  it("AppTheme.light(tokens) 把令牌挂进 ThemeData.extensions (context.tokens 才有值)", () => {
    expect(theme).toContain("extensions: <ThemeExtension<dynamic>>[AppTokensTheme(t)]");
  });

  it("app.dart 用了运行时令牌 (而不是写死默认主题)", () => {
    const app = rd("flutter_app/lib/app.dart");
    expect(app).toContain("AppTheme.light(tokens)");
    expect(app).toContain("activeTokensProvider");
  });
});
