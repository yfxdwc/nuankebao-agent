import type { Metadata, Viewport } from "next";
import "@/styles/globals.css";
import { defaultThemeColors } from "@/lib/design-tokens.g";
import { themeBootScript } from "@/lib/theme";

export const metadata: Metadata = {
  title: "暖客宝 · 大健康销售 CRM",
  description: "大健康客户管理・AI助手",
  // favicon / apple-touch-icon 由 Next.js 15 metadata-icons 约定自动注入:
  //   src/app/icon.png       → <link rel="icon"> (192×192)
  //   src/app/apple-icon.png → <link rel="apple-touch-icon"> (180×180)
  // 唯一真源: tools/branding/nuankebao-logo-source.png (主人上传原图, 白底圆角 + 主题图)
  // 重新生成: python3 tools/branding/render-logo.py
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  // 默认主题的主色 —— 真源 design/tokens/design-tokens.json (换肤后由 theme.ts 在客户端改写)
  themeColor: defaultThemeColors.primary,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="zh-CN" suppressHydrationWarning>
      <head>
        {/*
          首屏防闪: 在 body 绘制前把用户的主题打到 <html data-theme> 上。
          必须内联且不能依赖任何 JS chunk —— 否则会先画默认绿再跳成用户选的主题。
          真源: src/lib/theme.ts (themeBootScript)
        */}
        <script dangerouslySetInnerHTML={{ __html: themeBootScript }} />
      </head>
      <body className="theme-transition min-h-screen bg-background font-sans text-body-lg text-content-primary antialiased">
        {children}
      </body>
    </html>
  );
}