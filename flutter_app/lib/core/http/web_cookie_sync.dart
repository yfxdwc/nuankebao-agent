// ============================================
// 暖客宝 web 平台 cookie 同步 (R12 治本方案 B)
// ============================================
//
// 背景: Flutter web (XHR) 走 dio, dio onResponse 拦截器遍历 response.headers
// 取不到 Set-Cookie 头 (Chromium 在 XHR 层把 Set-Cookie 自动写 document.cookie,
// 不通过 XHR response headers 暴露)。结果: 登录成功 → session cookie 已经
// 写进 document.cookie → 但 dio 拦截器收不到 → storage 空 → 后续 API
// 全 401 → 跳回 /login → 主人看到"两页循环"。
//
// 治本: web 平台从 document.cookie 显式读 Auth.js cookie, 写到 ApiClient
// storage (跟 native 拦截器存同一 key, onRequest 拦截器读 storage 拼
// Cookie 头 → 后续 API 用 storage 里的 token, 跟原生路径一致)。
//
// 条件 import: web 平台走 html (dart:js_interop / dart:html),
// native (Android/iOS) 走 stub (返回空 map)。
//
// 边界:
//   - 不替代 dio onResponse 拦截器: native APK 仍然从 Set-Cookie 头走 (那个路径 work)
//   - 仅在 web 平台补 Set-Cookie 头不可见的问题
//   - 必须 callback POST 后 (302 响应时浏览器已写 cookie) 立即 sync
// ============================================

// dart:io 是 native 平台的标识 (Android/iOS)
// dart:html 是 web 平台的标识
// 条件 import: 当 dart:html 不可用 (即非 web) 时用 stub
export 'web_cookie_sync_stub.dart'
    if (dart.library.html) 'web_cookie_sync_web.dart';
