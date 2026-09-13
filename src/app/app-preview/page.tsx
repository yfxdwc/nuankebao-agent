// 暖客宝 Flutter Mobile UI 真机预览 (桌面浏览器版)
// 主人反馈: 真机 APK 看是 Flutter mobile UI, 但桌面浏览器要怎么看?
// 实施: Flutter web build → public/app/ + iframe 套 iPhone 柜架
//
// v0.1.x 更新 (主人 2026-09-12 拍):
//   - 删掉 blockIframe={true} (R12 物理阻断撤掉)
//   - iframe 现在默认可点. 顶部 banner 仅留 R12 历史说明 (informational only,
//     不再 enforce 任何禁用)
//   - 已知风险: Flutter web (XHR-based dio) 拿不到 Auth.js Set-Cookie 头,
//     在 iframe 里点登录会触发 R12 循环. 主人拍用其他方式处理 (puppeteer 拦截 /
//     middleware 拦截 / API disable 等), 详见 docs/login-failure-triage.md §2.B R12
//   - ⚠ 此变更与 AGENTS.md §5 反模式沉淀"贴告示 ≠ 修复"冲突, 主人 override, 见 CHANGELOG [0.4.1]

import { PreviewFrame } from "@/components/preview/preview-frame";
import { FlutterWebLoginBanner } from "@/components/preview/flutter-web-login-banner";

export const dynamic = "force-dynamic";

/**
 * 桌面浏览器预览 Flutter Mobile UI (中老年妇女易用版本)
 *
 * 用法:
 *   /app-preview                          # 默认预览 /app (Flutter web 自适应宽, iframe 可点)
 *   /app-preview?path=/customers          # 预览 Flutter 客户列表
 *   /app-preview?path=/profile           # 预览 我的
 *   /app-preview?path=/customers/123     # 预览客户详情
 *   /app-preview?path=/franchise-tree   # 预览加盟图谱
 *
 * Flutter web 在 iframe 里运行, 桌面浏览器看 mobile UI:
 *   - 默认 iPhone 14 Pro (393x852, 灵动岛)
 *   - 中老年大字 18pt+ / 64pt 按钮 / 80pt FAB
 *   - 🟣 加盟 / 🟢 普通 区分
 *
 * 设计原则:
 *   - Flutter web build 静态文件在 /public/app/ (Next.js serve)
 *   - iframe src = /app (Flutter web 自适应)
 *   - 同源 cookie 共享 (登录态可复用)
 *
 * 历史背景 (R12, w14 第五刀, 2026-09-11):
 *   Flutter web (XHR-based dio) 拿不到 Auth.js Set-Cookie 头 → 在 iframe 里点登录
 *   会无限循环. 当时用 PreviewFrame blockIframe=true (pointer-events: none) 作为
 *   "物理阻断" 止血. 2026-09-12 主人拍板撤掉这个阻断, 改用其他方式处理 (puppeteer
 *   拦截 / middleware 拦截 / API disable). 此页面顶部 banner 仅留 R12 历史说明,
 *   不再 enforce 禁用, iframe 可点.
 *   详见 docs/login-failure-triage.md §2.B R12
 */

interface PageProps {
  searchParams: Promise<{
    path?: string;
    w?: string;
    h?: string;
    frame?: string;
  }>;
}

export default async function AppPreviewPage({ searchParams }: PageProps) {
  const params = await searchParams;
  // 默认 path 是 /app (Flutter web 自适应入口)
  const path = params.path ?? "/app";
  const width = params.w ? parseInt(params.w) : 393;
  const height = params.h ? parseInt(params.h) : 852;
  const showFrame = params.frame !== "0";

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-slate-100 flex flex-col">
      {/* Banner 仅 informational (R12 历史说明, 不再 enforce 禁用)
          v0.1.x: 2026-09-12 主人拍删除 blockIframe 机制 */}
      <FlutterWebLoginBanner />
      <PreviewFrame
        path={path}
        width={width}
        height={height}
        showFrame={showFrame}
        // v0.1.x: 不再 blockIframe=true (主人拍, R12 改用其他方式处理)
      />
    </div>
  );
}
