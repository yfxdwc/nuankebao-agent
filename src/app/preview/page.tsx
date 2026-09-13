// force-dynamic for build (sandbox EAGAIN on static prerender)
import { PreviewFrame } from "@/components/preview/preview-frame";

export const dynamic = "force-dynamic";

/**
 * 暖客宝 手机真机预览 (W19)
 *
 * 用法:
 *   /preview                              # 默认预览 /admin
 *   /preview?path=/admin/customers        # 预览任意路径
 *   /preview?path=/admin/customers&w=375  # 自定义宽度 (默认 393 iPhone 14 Pro)
 *   /preview?path=/admin&h=750            # 自定义高度
 *   /preview?frame=0                      # 不要手机柜架, 只要缩放 iframe
 *
 * 设计原则:
 *   - 同一 origin iframe, 共享 cookie/session (手机扫码场景)
 *   - 中心化 PC 浏览器查看, 不开 DevTools
 *   - 给产品人/老板/销售内训用, 不熟 DevTools
 *   - URL 同步: iframe 内部路由变化时, 外层 URL 不变 (防止历史栈污染)
 */
export default async function PreviewPage({
  searchParams,
}: {
  searchParams: Promise<{
    path?: string;
    w?: string;
    h?: string;
    frame?: string;
  }>;
}) {
  const { path = "/admin", w, h, frame } = await searchParams;

  const width = parseInt(w ?? "393", 10);  // iPhone 14 Pro 默认
  const height = parseInt(h ?? "852", 10);
  const showFrame = frame !== "0";

  // q3-A 修复: Flutter web 在 iframe 里启动时 glass-pane 坍缩到 0×0
  // 检测 path 以 /app 开头 (Flutter web 入口), 自动开 CSS 注入
  const isFlutterWeb = path.startsWith("/app");

  return (
    <div className="min-h-screen flex flex-col">
      <PreviewFrame
        path={path}
        width={width}
        height={height}
        showFrame={showFrame}
        flutterCssFix={isFlutterWeb}
      />
      {isFlutterWeb && (
        // q3-A 修复 (inline script 注入): 备用路径 — PreviewFrame 客户端 chunk 可能未热重载.
        // 这个 script 在 HTML 里直接跑, 不依赖 React bundle. 幂等: 检测到 fix style 已注入就不重复.
        <script
          dangerouslySetInnerHTML={{
            __html: `
              (function nuankebaoFlutterGlassPaneFix() {
                const FIX_ID = 'nuankebao-flutter-glass-pane-fix';
                const CSS = \`
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
                  flt-glass-pane { z-index: 9999 !important; }
                  body { margin: 0 !important; padding: 0 !important; }
                \`;
                let attempts = 0;
                const MAX = 60;
                function tryFix() {
                  attempts++;
                  const iframe = document.getElementById('preview-iframe');
                  if (!iframe) return scheduleNext();
                  let doc;
                  try { doc = iframe.contentDocument; } catch { return scheduleNext(); }
                  if (!doc) return scheduleNext();
                  // 注入 style (幂等)
                  let style = doc.getElementById(FIX_ID);
                  if (!style) {
                    style = doc.createElement('style');
                    style.id = FIX_ID;
                    style.textContent = CSS;
                    if (doc.head) doc.head.appendChild(style);
                    else { doc.documentElement.appendChild(style); }
                  }
                  // 检查 glass-pane 是否已撑开
                  const glass = doc.querySelector('flt-glass-pane');
                  if (glass) {
                    const r = glass.getBoundingClientRect();
                    if (r.width > 100 && r.height > 100) return; // 成功
                    // glass-pane 0×0 时强制 inline style
                    glass.style.setProperty('display', 'block', 'important');
                    glass.style.setProperty('position', 'absolute', 'important');
                    glass.style.setProperty('top', '0', 'important');
                    glass.style.setProperty('left', '0', 'important');
                    glass.style.setProperty('width', '100%', 'important');
                    glass.style.setProperty('height', '100%', 'important');
                  }
                  scheduleNext();
                }
                function scheduleNext() {
                  if (attempts < MAX) setTimeout(tryFix, 500);
                }
                if (document.readyState === 'loading') {
                  document.addEventListener('DOMContentLoaded', tryFix);
                } else {
                  tryFix();
                }
              })();
            `,
          }}
        />
      )}
    </div>
  );
}
