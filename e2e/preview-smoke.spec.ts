/**
 * e2e/preview-smoke.spec.ts
 *
 * 预览框架 — Playwright smoke test (L4 验收兜底)
 *
 * 守护目标 (核心: preview framework 没挂):
 *   1. /app-preview (无参) 静态路径: 加载 200, iframe 存在, src = "/app"
 *   2. /app-preview?path=/xxx 自定义路径: 加载 200, iframe src 含 path
 *   3. /app-preview?dev=1 (无 path): iframe src = "/dev-app/" — 仅当 :8080 起才跑
 *   4. /preview → /app-preview 307 redirect 兜底
 *   5. 不应有 5xx response
 *
 * 故意 NOT 测:
 *   - R12 banner 文案 (默认 dismissed, 见 flutter-web-login-banner.tsx:27 useState(true))
 *   - iframe 内部渲染 (那是 Flutter app 的责任)
 *   - 设备切换按钮 (PreviewFrame 内部 state, 跟 preview framework 稳定性无关)
 *
 * 前置 (主人 dev server 跑在 3003):
 *   pnpm dev
 *
 * 与 ADR-0009 §2.4 / AGENTS §9.6 验收清单对应.
 * 见: docs/adr/0009-preview-framework-freeze.md
 */

import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

/**
 * 检查 Flutter web dev server (:8080) 是否可达.
 * 不通 → test.skip (不强依赖, 主人没起 Flutter dev 也能跑 CI)
 */
function isFlutterDevServerUp(): boolean {
  try {
    execSync("curl -sI -m 2 http://127.0.0.1:8080/ >/dev/null 2>&1", {
      stdio: "pipe",
    });
    return true;
  } catch {
    return false;
  }
}

test.describe("预览框架 smoke test (ADR-0009, AGENTS §9)", () => {
  test("1. /app-preview (无参): 静态路径, iframe src 应为 /app", async ({ page }) => {
    const response = await page.goto("/app-preview", {
      waitUntil: "domcontentloaded",
    });

    // 1. 页面加载 200
    expect(response?.status(), "/app-preview 应 200 OK").toBe(200);

    // 2. 主容器 (PreviewFrame wrapper, gradient bg)
    await expect(
      page.locator("div.min-h-screen").first(),
      "主容器 div.min-h-screen 应存在"
    ).toBeVisible();

    // 3. iframe 应有且仅有一个 (PreviewFrame 核心)
    const iframe = page.locator("iframe");
    await expect(iframe, "iframe 应存在").toHaveCount(1);

    // 4. 默认 iframe src = "/app"
    const src = await iframe.getAttribute("src");
    expect(src, "?无参时 iframe src 应是 /app").toBe("/app");
  });

  test("2. /app-preview?path=/profile: 自定义路径生效", async ({ page }) => {
    const response = await page.goto("/app-preview?path=/profile", {
      waitUntil: "domcontentloaded",
    });
    expect(response?.status()).toBe(200);

    const iframe = page.locator("iframe");
    await expect(iframe).toHaveCount(1);

    const src = await iframe.getAttribute("src");
    // path 参数应传给 iframe 作为 src
    expect(src, "?path=/profile 应传给 iframe").toContain("/profile");
  });

  test("3. /app-preview?dev=1 (无 path): Flutter dev server 路径 — 默认 skip", async ({
    page,
  }) => {
    // 前置检查: Flutter web dev server :8080 是否可达
    // 不通 → skip (不强依赖, 主人没起 Flutter dev 也能跑 CI)
    test.skip(
      !isFlutterDevServerUp(),
      "Flutter web dev server :8080 未起, 跳过 ?dev=1 路径测试"
    );

    // 不传 path, 让 page.tsx 的 defaultPath = "/dev-app/" 生效
    const response = await page.goto("/app-preview?dev=1", {
      waitUntil: "domcontentloaded",
    });
    expect(response?.status()).toBe(200);

    const iframe = page.locator("iframe");
    await expect(iframe).toHaveCount(1);

    const src = await iframe.getAttribute("src");
    // ?dev=1 + 无 path → src 应是 /dev-app/
    expect(src, "?dev=1 无 path 时 iframe src 应是 /dev-app/").toBe("/dev-app/");
  });

  test("4. /preview → /app-preview 307 redirect 兜底", async ({ page }) => {
    const response = await page.goto("/preview", {
      waitUntil: "domcontentloaded",
    });

    // redirect 后 URL 应含 /app-preview
    await expect(page, "/preview 应 307 到 /app-preview").toHaveURL(/\/app-preview/, {
      timeout: 3000,
    });
    // /app-preview 应 200 (跟随 redirect 后)
    expect(response?.status(), "redirect 后 /app-preview 应 200").toBe(200);
  });

  test("5. /app-preview 不应抛 5xx response", async ({ page }) => {
    const errors: string[] = [];
    page.on("response", (response) => {
      const url = response.url();
      // 只看 /app-preview 主页面, 忽略 HMR / RSC / 静态资源
      if (
        (url.includes("/app-preview") || url.endsWith("/app-preview")) &&
        response.status() >= 500
      ) {
        errors.push(`${response.status()} ${url}`);
      }
    });

    await page.goto("/app-preview", { waitUntil: "networkidle" });
    expect(errors, `不应有 5xx response: ${errors.join(", ")}`).toHaveLength(0);
  });
});
