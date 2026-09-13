"use client";

import { useState, useEffect } from "react";
import { AlertTriangle, ExternalLink, Copy, Check, Info } from "lucide-react";

/**
 * Flutter Web 预览模式横幅 — informational only (v0.1.x 改)
 *
 * 旧版 (2026-09-11 ~ 2026-09-12): R12 止血, 配合 PreviewFrame blockIframe=true
 *   物理上禁用 iframe 交互, 强制用户走真机扫码.
 *
 * v0.1.x (主人 2026-09-12 拍): 删掉 blockIframe 机制, iframe 现在永远可点.
 *   本组件降级为纯 informational: 解释 R12 是什么、为什么会出现、推荐用真机扫码
 *   来避免, 不再 enforce 任何禁用. 主人拍用其他方式处理 R12 循环 (puppeteer 拦截 /
 *   middleware 拦截 / API disable 等).
 *
 * 行为:
 *   - 默认显示, dismiss 后 localStorage 记住 (v0.4.0 之前是 non-dismissable,
 *     主人反馈太烦, 现在恢复 dismissable)
 *   - 复制当前 URL (方便主人 / 销售 PC 浏览器扫码)
 *   - 顶层打开 Flutter web (注意顶层也命中 R12, 仅供调试非登录功能)
 *
 * 详见 docs/login-failure-triage.md §2.B R12 + CHANGELOG [0.4.1]
 */
export function FlutterWebLoginBanner() {
  // 默认 true 避免 hydration 闪烁, useEffect 后再判断 (与 w14 旧实现对齐)
  const [dismissed, setDismissed] = useState(true);
  const [copied, setCopied] = useState(false);
  const [currentUrl, setCurrentUrl] = useState("");

  useEffect(() => {
    const stored = localStorage.getItem("flutter-web-login-banner-dismissed-v2");
    if (stored !== "1") setDismissed(false);
    setCurrentUrl(window.location.href);
  }, []);

  function dismiss() {
    try {
      localStorage.setItem("flutter-web-login-banner-dismissed-v2", "1");
    } catch {
      // localStorage 不可用 (隐私模式等), 仅本次会话关闭
    }
    setDismissed(true);
  }

  async function copyUrl() {
    try {
      await navigator.clipboard.writeText(currentUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      const ta = document.createElement("textarea");
      ta.value = currentUrl;
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand("copy");
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      } catch {
        // 忽略
      } finally {
        document.body.removeChild(ta);
      }
    }
  }

  if (dismissed) return null;

  return (
    <div
      role="alert"
      className="border-b-2 border-sky-400 bg-sky-50 px-3 py-2.5 md:px-4 md:py-3 shadow-sm"
    >
      <div className="max-w-7xl mx-auto flex items-start gap-3">
        <Info
          className="h-5 w-5 text-sky-600 shrink-0 mt-0.5"
          aria-hidden="true"
        />
        <div className="flex-1 min-w-0 text-sm text-sky-900">
          <p className="font-semibold text-sky-950 flex items-center gap-1.5 flex-wrap">
            <Info className="h-3.5 w-3.5" aria-hidden="true" />
            Flutter Web 预览模式 — R12 登录循环提示 (informational, 不再 enforce)
          </p>

          <p className="mt-1 leading-relaxed">
            <strong className="text-sky-950">什么是 R12:</strong>{" "}
            Flutter web 在 iframe 里用 XHR (dio), 拿不到 Auth.js 的{" "}
            <code className="bg-sky-100 px-1 rounded text-xs">Set-Cookie</code> 头 →
            session cookie 永远存不上 → 点登录按钮 → 跳回 /login → 死循环.
          </p>

          <p className="mt-1.5 leading-relaxed">
            <strong className="text-sky-950">iframe 现在可点 (2026-09-12 主人拍):</strong>{" "}
            之前用 <code className="bg-sky-100 px-1 rounded text-xs">pointer-events: none</code> 物理阻断,
            现在删除. 你可以直接点 input / button / 导航, 但
            <strong className="text-sky-950">不要点登录按钮</strong>{" "}
            (会触发 R12 循环).
          </p>

          <p className="mt-1.5 leading-relaxed">
            <strong className="text-sky-950">真用户路径不受影响:</strong>{" "}
            真机扫码 / 安装 APK 走 native dio (HttpURLConnection / Cronet),
            能拿 Set-Cookie 头, 登录全链路 OK。
          </p>

          <p className="mt-1 text-xs leading-relaxed text-sky-800">
            调试登录请用: ① puppeteer E2E (API 层) ② 真机 APK (UI 层) ③ 本预览仅看 UI, 不要测登录。详见{" "}
            <code className="bg-sky-100 px-1 rounded text-[10px]">docs/login-failure-triage.md §2.B R12</code>。
          </p>
        </div>

        {/* 操作按钮组 */}
        <div className="shrink-0 flex flex-col gap-1.5 items-end">
          <button
            type="button"
            onClick={copyUrl}
            className="inline-flex items-center gap-1 h-7 px-2 text-xs font-medium bg-white border border-sky-300 text-sky-900 rounded hover:bg-sky-100"
            aria-label="复制当前 URL, 方便真机扫码"
            title="复制当前 URL"
          >
            {copied ? (
              <>
                <Check className="h-3 w-3" />
                <span className="hidden sm:inline">已复制</span>
              </>
            ) : (
              <>
                <Copy className="h-3 w-3" />
                <span className="hidden sm:inline">复制 URL</span>
              </>
            )}
          </button>
          <a
            href="/app"
            target="_blank"
            rel="noopener"
            className="inline-flex items-center gap-1 h-7 px-2 text-xs font-medium bg-white border border-sky-300 text-sky-900 rounded hover:bg-sky-100"
            title="顶层打开 Flutter web (browser-level R12 仍命中, 仅供调试非登录功能)"
          >
            <ExternalLink className="h-3 w-3" />
            <span className="hidden sm:inline">顶层打开</span>
          </a>
          <button
            type="button"
            onClick={dismiss}
            className="h-7 w-7 inline-flex items-center justify-center rounded text-sky-700 hover:bg-sky-100"
            aria-label="关闭提示"
            title="关闭提示 (不影响其他功能, 仅本次 / 下次不再显示)"
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>
      </div>
    </div>
  );
}
