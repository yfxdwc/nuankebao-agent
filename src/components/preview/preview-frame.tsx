"use client";

import { useState, useEffect, useRef } from "react";
import Link from "next/link";
import { Smartphone, Maximize2, RotateCcw, ExternalLink, X } from "lucide-react";

/**
 * 暖客宝 真机预览框 (W19)
 *
 * PC 浏览器里看 mobile UI, 不开 DevTools.
 * 拿 iframe 套手机柜架, iframe 内部用真实路由 (dev 同源 cookie 共享).
 *
 * 设计:
 *   - 顶部 toolbar: 路径输入 + 设备尺寸选择 + 全屏 + 跳转新窗口
 *   - 中间: iPhone 14 Pro 柜架 (圆角 + 灵动岛 + Home Indicator)
 *   - 底部: 设备尺寸快选 (iPhone SE / 14 / 14 Pro Max / iPad Mini)
 *   - 响应 iframe src 变化时同步父 URL (router.replace, 不 push)
 *
 * v0.1.x 更新 (主人 2026-09-12 拍):
 *   - 移除 blockIframe 机制 (R12 物理阻断撤掉)
 *   - iframe 永远可点. R12 登录循环改用其他方式处理 (主人决策)
 *   - 详见 CHANGELOG [0.4.1] + AGENTS.md §5 反模式沉淀 (注意: 此变更与 §5 默认结论冲突, 主人 override)
 */

interface PreviewFrameProps {
  path: string;
  width: number;
  height: number;
  showFrame: boolean;
  /**
   * 注入 Flutter web glass-pane 修复 CSS (q3-A 真修复).
   *
   * 为 true 时, 在 iframe load 后注入 CSS:
   *   flutter-view, flt-glass-pane { display: block; position: absolute; inset: 0; width: 100%; height: 100%; }
   * 解决 Flutter web 在 Next.js 父页 + sandboxed iframe 下 glass-pane 坍缩到 0×0
   * 导致整个屏幕无法接收 pointer 事件的 bug.
   *
   * 详见: tools/debug-preview-*.ts + docs/login-failure-triage.md §2.D 新增 R13.
   * 默认 false (admin 预览不需要, 不影响).
   */
  flutterCssFix?: boolean;
}

const DEVICE_PRESETS: Array<{ label: string; w: number; h: number; desc: string }> = [
  { label: "iPhone SE", w: 375, h: 667, desc: "老安卓机 / 入门 iPhone" },
  { label: "iPhone 14", w: 390, h: 844, desc: "养生销售员主流" },
  { label: "iPhone 14 Pro", w: 393, h: 852, desc: "灵动岛 (默认)" },
  { label: "iPhone 14 Pro Max", w: 430, h: 932, desc: "大屏" },
  { label: "iPad Mini", w: 768, h: 1024, desc: "平板 (warm-up)" },
];

export function PreviewFrame({ path, width, height, showFrame, flutterCssFix = false }: PreviewFrameProps) {
  // v0.1.x: blockIframe 机制已删 (主人 2026-09-12 拍). iframe 永远可点.
  // R12 登录循环改用其他方式处理 (puppeteer 拦截 / middleware / API disable 等).
  const [currentPath, setCurrentPath] = useState(path);
  const [inputPath, setInputPath] = useState(path);
  const [dimensions, setDimensions] = useState({ w: width, h: height });
  const [scale, setScale] = useState(1);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const injectedRef = useRef<string | null>(null); // 记录已注入的 iframe src, 避免重复

  // q3-A 修复: 当前路径变化时重新注入 CSS (iframe src 变化 = 新文档)
  useEffect(() => {
    if (!flutterCssFix) return;
    if (injectedRef.current === currentPath) return; // 已注入过当前路径
    // 等 iframe 加载 (currentPath 改变时 iframe src 改变, React 会触发 onLoad)
    // 但 useEffect 在 render 后立即跑, onLoad 可能还没触发, 给一个延迟重试
    const tryInject = () => {
      const iframe = iframeRef.current;
      if (iframe && iframe.contentDocument) {
        injectFlutterGlassPaneFix(iframe);
        injectedRef.current = currentPath;
      }
    };
    // 立即试一次 (iframe 已存在的场景)
    const timer1 = setTimeout(tryInject, 100);
    // 500ms 后再试 (iframe.onLoad 触发后)
    const timer2 = setTimeout(tryInject, 500);
    // 1.5s 后还试一次 (Flutter web 启动慢)
    const timer3 = setTimeout(tryInject, 1500);
    return () => {
      clearTimeout(timer1);
      clearTimeout(timer2);
      clearTimeout(timer3);
    };
  }, [currentPath, flutterCssFix]);

  // iframe 内部 SPA 路由变化时, 同步外层 input (用户可手动改路径)
  // flutterCssFix=true 时: 注入 CSS 修复 flt-glass-pane 0×0 坍缩 (q3-A 真修复)
  function handleIframeLoad() {
    try {
      const iframe = document.getElementById("preview-iframe") as HTMLIFrameElement | null;
      if (iframe && iframe.contentWindow) {
        const loc = iframe.contentWindow.location;
        if (loc.pathname + loc.search !== currentPath) {
          setCurrentPath(loc.pathname + loc.search);
          setInputPath(loc.pathname + loc.search);
        }
        // q3-A 修复: Flutter web 在 sandboxed iframe 里 glass-pane 坍缩到 0×0
        // 必须等 iframe 内 Flutter 启动完才注入 (DOM 节点存在)
        if (flutterCssFix) {
          injectFlutterGlassPaneFix(iframe);
        }
      }
    } catch {
      // cross-origin 不让读, 忽略
    }
  }

  /**
   * 给 iframe 内 Flutter web 注入 glass-pane 修复 CSS.
   *
   * 背景: Flutter web 在 Next.js 父页 + sandboxed iframe 里启动时,
   * `<flt-glass-pane>` 自定义元素被浏览器按未知 tag 默认样式渲染
   * (display: inline, position: static, width: auto, height: auto),
   * 尺寸坍缩到 0×0, 整个 Flutter UI 表面无法接收 pointer 事件.
   * Flutter web 引擎自己应该设 position: fixed; inset: 0 但此环境下未生效.
   *
   * 修复: 强制 display: block; position: absolute; inset: 0; width/height: 100%.
   * 用 absolute 而非 fixed 是因为 fixed 在某些 iframe sandbox 下会被裁剪.
   *
   * 重试机制: Flutter web 启动需要时间, 多次尝试直到 glass-pane 出现.
   */
  function injectFlutterGlassPaneFix(iframe: HTMLIFrameElement) {
    let attempts = 0;
    const MAX_ATTEMPTS = 30;
    const INTERVAL_MS = 500;

    function tryInject() {
      attempts++;
      try {
        const doc = iframe.contentDocument;
        if (!doc) return scheduleNext();

        // 注入 style 标签 (幂等)
        let style = doc.getElementById("nuankebao-flutter-glass-pane-fix") as HTMLStyleElement | null;
        if (!style) {
          style = doc.createElement("style");
          style.id = "nuankebao-flutter-glass-pane-fix";
          style.textContent = `
            /* q3-A 修复: Flutter web glass-pane 0×0 坍缩 */
            flutter-view, flt-glass-pane, flt-scene-host {
              display: block !important;
              position: absolute !important;
              top: 0 !important;
              left: 0 !important;
              width: 100% !important;
              height: 100% !important;
              flex: 1 1 auto !important;
              pointer-events: auto !important;
            }
            flt-glass-pane {
              z-index: 9999 !important;
            }
            body {
              margin: 0 !important;
              padding: 0 !important;
            }
          `;
          doc.head?.appendChild(style);
        }

        // 验证: glass-pane 是否已撑开
        const glass = doc.querySelector("flt-glass-pane") as HTMLElement | null;
        if (glass) {
          const rect = glass.getBoundingClientRect();
          if (rect.width > 100 && rect.height > 100) {
            // console.debug(`[preview-frame] Flutter glass-pane fix applied (attempt ${attempts}, ${rect.width}x${rect.height})`);
            return; // 成功
          }
          // glass-pane 存在但还是 0×0, 直接强制 inline style
          glass.style.setProperty("display", "block", "important");
          glass.style.setProperty("position", "absolute", "important");
          glass.style.setProperty("top", "0", "important");
          glass.style.setProperty("left", "0", "important");
          glass.style.setProperty("width", "100%", "important");
          glass.style.setProperty("height", "100%", "important");
          const newRect = glass.getBoundingClientRect();
          if (newRect.width > 100) {
            // console.debug(`[preview-frame] Flutter glass-pane inline override (attempt ${attempts}, ${newRect.width}x${newRect.height})`);
            return;
          }
        }
        scheduleNext();
      } catch (err) {
        console.warn("[preview-frame] Flutter glass-pane fix failed:", err);
        scheduleNext();
      }
    }

    function scheduleNext() {
      if (attempts < MAX_ATTEMPTS) {
        setTimeout(tryInject, INTERVAL_MS);
      } else {
        console.warn(`[preview-frame] Flutter glass-pane fix gave up after ${MAX_ATTEMPTS} attempts`);
      }
    }

    tryInject();
  }

  function navigate(newPath: string) {
    const trimmed = newPath.trim() || "/admin";
    setCurrentPath(trimmed);
    setInputPath(trimmed);
  }

  function pickPreset(preset: (typeof DEVICE_PRESETS)[number]) {
    setDimensions({ w: preset.w, h: preset.h });
    setCurrentPath((p) => p);  // 触发 iframe 重新加载保持尺寸
  }

  function toggleFullscreen() {
    const el = document.getElementById("preview-frame-wrapper");
    if (!el) return;
    if (document.fullscreenElement) {
      document.exitFullscreen();
    } else {
      el.requestFullscreen();
    }
  }

  return (
    <div className="flex flex-col bg-gradient-to-br from-muted via-background to-muted flex-1 min-h-0">
      {/* Toolbar */}
      <header className="border-b bg-white/80 backdrop-blur sticky top-0 z-30">
        <div className="max-w-7xl mx-auto px-4 py-2.5 flex flex-wrap items-center gap-2 md:gap-3">
          <div className="flex items-center gap-2 shrink-0">
            <Smartphone className="h-4 w-4 text-primary" />
            <h1 className="text-sm md:text-base font-semibold">真机预览</h1>
            <span className="hidden md:inline text-xs text-muted-foreground">
              (PC 浏览器查看移动 UI)
            </span>
          </div>

          {/* 路径输入 */}
          <form
            onSubmit={(e) => {
              e.preventDefault();
              navigate(inputPath);
            }}
            className="flex-1 min-w-0 flex items-center gap-1.5"
          >
            <span className="text-xs text-muted-foreground shrink-0">路径:</span>
            <input
              type="text"
              value={inputPath}
              onChange={(e) => setInputPath(e.target.value)}
              placeholder="/admin"
              className="flex-1 min-w-0 h-8 px-2 text-sm border rounded-md bg-background font-mono"
              aria-label="预览路径"
            />
            <button
              type="submit"
              className="h-8 px-3 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 shrink-0"
            >
              跳转
            </button>
          </form>

          {/* 操作按钮 */}
          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={() => navigate(currentPath)}
              className="h-8 w-8 inline-flex items-center justify-center rounded-md hover:bg-muted text-muted-foreground"
              aria-label="刷新"
              title="刷新"
            >
              <RotateCcw className="h-3.5 w-3.5" />
            </button>
            <a
              href={currentPath}
              target="_blank"
              rel="noopener"
              className="h-8 w-8 inline-flex items-center justify-center rounded-md hover:bg-muted text-muted-foreground"
              aria-label="新窗口打开"
              title="新窗口打开"
            >
              <ExternalLink className="h-3.5 w-3.5" />
            </a>
            <button
              type="button"
              onClick={toggleFullscreen}
              className="h-8 w-8 inline-flex items-center justify-center rounded-md hover:bg-muted text-muted-foreground"
              aria-label="全屏"
              title="全屏 (iframe 不变, 外框全屏)"
            >
              <Maximize2 className="h-3.5 w-3.5" />
            </button>
            <Link
              href="/admin"
              className="h-8 w-8 inline-flex items-center justify-center rounded-md hover:bg-muted text-muted-foreground"
              aria-label="返回 admin"
              title="返回 admin"
            >
              <X className="h-3.5 w-3.5" />
            </Link>
          </div>
        </div>
      </header>

      {/* 设备尺寸快选 */}
      <div className="border-b bg-white/50">
        <div className="max-w-7xl mx-auto px-4 py-2 flex gap-1.5 overflow-x-auto">
          {DEVICE_PRESETS.map((d) => {
            const isActive = d.w === dimensions.w && d.h === dimensions.h;
            return (
              <button
                key={d.label}
                type="button"
                onClick={() => pickPreset(d)}
                className={
                  "shrink-0 inline-flex flex-col items-start px-2.5 py-1.5 rounded-md text-xs transition-colors " +
                  (isActive
                    ? "bg-primary text-primary-foreground"
                    : "bg-background border hover:bg-muted")
                }
                title={d.desc}
              >
                <span className="font-medium">{d.label}</span>
                <span className={"text-[10px] " + (isActive ? "opacity-80" : "text-muted-foreground")}>
                  {d.w}×{d.h}
                </span>
              </button>
            );
          })}
          <span className="ml-auto text-[10px] text-muted-foreground self-center hidden md:inline">
            当前: {dimensions.w}×{dimensions.h}
          </span>
        </div>
      </div>

      {/* iframe 容器 (居中 + 缩放) */}
      <main
        id="preview-frame-wrapper"
        className="flex-1 flex items-start md:items-center justify-center p-4 md:p-8 overflow-auto"
      >
        <div
          className="relative"
          style={{
            width: dimensions.w * scale + (showFrame ? 32 : 0),
            height: dimensions.h * scale + (showFrame ? 32 : 0),
          }} /* ui-style-allow-inline-style: 动态计算 (scale/top/bottom/width/height) */
        >
          {showFrame ? (
            /* iPhone 风格柜架 */
            <div
              className="absolute inset-0 bg-foreground rounded-[3rem] shadow-2xl ring-1 ring-foreground/10"
              style={{
                padding: 12 * scale,
              }} /* ui-style-allow-inline-style: 动态计算 (scale/top/bottom/width/height) */
            >
              {/* 灵动岛 (iPhone 14 Pro+) */}
              {dimensions.w >= 390 && (
                <div
                  className="absolute left-1/2 -translate-x-1/2 bg-black rounded-full z-10"
                  style={{
                    top: 8 * scale,
                    width: 100 * scale,
                    height: 28 * scale,
                  }} /* ui-style-allow-inline-style: 动态计算 (scale/top/bottom/width/height) */
                  aria-hidden="true"
                />
              )}

              {/* 屏幕 */}
              <div
                className="relative w-full h-full bg-background rounded-[2.4rem] overflow-hidden"
                style={{
                  borderRadius: `${2.4 * scale}rem`,
                }}
              >
                <iframe
                  ref={iframeRef}
                  id="preview-iframe"
                  src={currentPath}
                  className="w-full h-full border-0"
                  title={`预览 ${currentPath}`}
                  onLoad={handleIframeLoad}
                  // 允许同源 iframe 完整功能 (cookie/session/storage)
                  sandbox="allow-same-origin allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox"
                  // v0.1.x: blockIframe 机制已删 (主人 2026-09-12 拍), iframe 永远可点
                />
              </div>

              {/* Home Indicator */}
              <div
                className="absolute left-1/2 -translate-x-1/2 bg-white rounded-full"
                style={{
                  bottom: 6 * scale,
                  width: 120 * scale,
                  height: 4 * scale,
                }} /* ui-style-allow-inline-style: 动态计算 (scale/top/bottom/width/height) */
                aria-hidden="true"
              />
            </div>
          ) : (
            /* 无柜架: 直接显示缩放 iframe */
            <iframe
              ref={iframeRef}
              id="preview-iframe"
              src={currentPath}
              className="border-0 bg-background rounded-lg shadow-xl"
              style={{
                width: dimensions.w * scale,
                height: dimensions.h * scale,
                // v0.1.x: blockIframe 机制已删 (主人 2026-09-12 拍), iframe 永远可点
              }} /* ui-style-allow-inline-style: 动态计算 (scale/top/bottom/width/height) */
              title={`预览 ${currentPath}`}
              onLoad={handleIframeLoad}
            />
          )}
        </div>
      </main>

      {/* 底部说明 */}
      <footer className="border-t bg-white/50 py-2">
        <div className="max-w-7xl mx-auto px-4 text-[10px] text-muted-foreground flex flex-wrap items-center gap-x-4 gap-y-1">
          <span>💡 这是 mobile-first UI, 在窄屏 (&lt;768px) 才完整</span>
          <span>•</span>
          <span>养生销售员实测机型: iPhone 11/12/13, 华为畅享</span>
          <span>•</span>
          <span>
            路径:
            <code className="bg-muted px-1.5 py-0.5 rounded ml-1 text-[10px]">{currentPath}</code>
          </span>
          <span className="ml-auto hidden md:inline">
            按 Ctrl/Cmd + +/- 调整缩放 (浏览器)
          </span>
        </div>
      </footer>
    </div>
  );
}
