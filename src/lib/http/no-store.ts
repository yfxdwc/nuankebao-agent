// ============================================
// HTTP 响应头 helper (暖客宝 web admin + Flutter web)
// 文档: docs/r9-r10-optimization.md §5 R-10 L3 跨端语义
//
// 单一真相源: 客户相关 route 全部走 noStoreJson() / noStoreResponse() 加
// `Cache-Control: no-store` 响应头, 防止中间层 (CDN / Next.js page cache /
// Service Worker) 把「撤销推送 / 改归属 / 合并」后的旧列表结果返回给前端。
//
// 历史 (R-10 沉淀, 2026-09-26):
//   L1 = 同端立即 (本机 invalidate + Flutter ref.invalidate(provider))
//   L2 = 同用户返回列表刷新 (RouteAware didPopNext + AppLifecycleState.resumed)
//   L3 = 跨端 (其他设备 / 另一台电脑) → 没实时推送通道 → 语义 = 下次拉取生效
//        → server 必须保证: 用户**下次拉取**拿到的是新数据
//        → Cache-Control: no-store 是 L3 的最后兜底 (防止中间层吃旧)
//   不做 SSE 的理由 (主人 2026-09-26 拍):
//     - SSE / WebSocket 成本 = 后端常驻连接 + 鉴权 / 重连 / 离线补偿
//     - 收益 = 跨端推送 1s 立刻可见
//     - 但 L3 实际触发频率 = 远程登录的"另一台电脑" (销售员本人) + 上级/下级
//       (用其他账号操作), 频率不高; "下次拉取生效"已经满足业务需求
//     - L1+L2 已覆盖 90% 场景 (同端 / 同用户返回)
//   本 helper = L3 兜底的实现细节。
//
// 用法:
//   import { noStoreJson } from "@/lib/http/no-store";
//   return noStoreJson({ items, total });
//
//   return noStoreResponse(svg, { "Content-Type": "image/svg+xml" });
// ============================================

import { NextResponse } from "next/server";

/**
 * `Cache-Control: no-store` 的常量字符串, 供所有 customer/share/stats route 用
 *
 * - no-store: 不入任何缓存 (CDN / browser disk / Next 路由缓存 / Service Worker)
 * - 不加 max-age=0: no-store 已最强, max-age=0 仍允许 conditional GET (304)
 *
 * ⚠️ 不在 route 层加 `dynamic = "force-dynamic"`: 部分 route 已在文件顶部导出
 *    (比如 customers/route.ts 拿 `force-dynamic` 控整页 cache), 本 helper
 *    兜的是**响应头**, 与 dynamic 标志互补不冲突。
 */
export const NO_STORE_HEADERS = {
  "Cache-Control": "no-store",
} as const;

/**
 * 与 NextResponse.json 同接口, 但**强制注入** `Cache-Control: no-store` 响应头。
 *
 * 为什么需要这个 wrapper:
 *   - 默认 NextResponse.json() 不会写 Cache-Control (Next 15 才会按 route
 *     配置自动加, 但部分场景需要手动兜)
 *   - R-10 L3 兜底: 跨端语义 = "下次拉取生效" → 必须保证每次拉取都是新数据
 *   - 即使前端 fetch 加 cache:"no-store", 中间层 (nginx / CDN / 浏览器 disk cache)
 *     仍可能在浏览器侧把旧响应喂回前端 → 必须在 server 响应里明确 no-store
 */
export function noStoreJson<T>(body: T, init?: ResponseInit): NextResponse<T> {
  const headers = new Headers(init?.headers);
  headers.set("Cache-Control", "no-store");
  return NextResponse.json<T>(body, { ...init, headers });
}

/**
 * 与 new Response() 同接口, 但**强制注入** `Cache-Control: no-store`。
 * 用于 SVG / PNG / 二进制响应 (如 QR 码图, 已用此模式, 见 apk-qr/route.ts)。
 */
export function noStoreResponse(
  body: BodyInit | null,
  init?: ResponseInit,
): Response {
  const headers = new Headers(init?.headers);
  headers.set("Cache-Control", "no-store");
  return new Response(body, { ...init, headers });
}