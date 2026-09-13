import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // typedRoutes 临时关闭: 复杂 Link 类型问题, 后期再开
  // experimental: { typedRoutes: true },
  // postgres 客户端需要 native binding, 标记为外部包
  serverExternalPackages: ["postgres"],

  // standalone 输出: 避免 build 阶段静态生成 (sandbox spawn EAGAIN 限制),
  // 生产运行时不变 (运行时只调现成产物, 不需要 worker pool)
  output: "standalone",

  // W5 RBAC: Flutter web (public/app/) SPA 路由处理
  // Flutter go_router 内部跳 /login → 浏览器 URL 变 /app/login
  // Next.js 默认当 404 → rewrite 到 Flutter index.html 让 Flutter 处理
  async rewrites() {
    return [
      {
        // /app/* (除了静态文件) 都走 Flutter index.html
        source: '/app/:path*',
        destination: '/app/index.html',
      },
    ];
  },

  // 允许手机/同网段设备访问 dev server (Next.js 15 安全默认拒绝)
  // 否则扫描 QR 跳 http://192.168.1.200:3010/* 会 404 (host header 跨域)
  // 用 hostname 正则: 192.168.x.x, 10.x.x.x, 172.16-31.x.x, localhost, 127.0.0.1
  allowedDevOrigins: [
    "192.168.*.*",
    "10.*.*.*",
    "172.16.*.*",
    "172.17.*.*",
    "172.18.*.*",
    "172.19.*.*",
    "172.20.*.*",
    "172.21.*.*",
    "172.22.*.*",
    "172.23.*.*",
    "172.24.*.*",
    "172.25.*.*",
    "172.26.*.*",
    "172.27.*.*",
    "172.28.*.*",
    "172.29.*.*",
    "172.30.*.*",
    "172.31.*.*",
    "localhost",
    "127.0.0.1",
  ],
};

export default nextConfig;