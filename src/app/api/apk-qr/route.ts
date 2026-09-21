import { NextRequest, NextResponse } from "next/server";
import QRCode from "qrcode";

export const dynamic = "force-dynamic";

/**
 * GET /api/apk-qr
 * 生成 APK 下载 URL 的二维码 (公开 — 跟 apk-download 同步, 主因见下载路由)
 *
 * Query:
 *   - url: 要编码的 URL (默认用当前请求的 host)
 *   - format: png | svg | dataurl (默认 png —— 直接吐图片, 给 <img> 用)
 *
 * ⚠ W14 修: 之前默认返回 JSON {url, dataUrl}, <img src> 拿到 JSON 显示破图。
 *   现在默认 format=png 直接返回 image/png 字节流。
 *
 * 历史 (2026-09-21): 跟 apk-download 同步去掉登录保护。二维码内容是公开 URL,
 *   生成过程无敏感数据, 未登录用户也能用 (例如 web admin 预览 / 营销页生成)。
 *   已登录用户的 Flutter dio 仍能正常用 (调这个端点拿 PNG bytes 渲染)。
 */
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const format = searchParams.get("format") ?? "png";

  // 默认 URL: 当前 host + /api/apk-download
  const host = request.headers.get("host") ?? "127.0.0.1:3003";
  const protocol = request.headers.get("x-forwarded-proto") ?? "http";
  const url = searchParams.get("url") ?? `${protocol}://${host}/api/apk-download`;

  const common = {
    errorCorrectionLevel: "M" as const,
    margin: 1,
    width: 300,
    color: { dark: "#1F8A4C", light: "#FFFFFF" }, // 养生绿
  };

  try {
    if (format === "svg") {
      const svg = await QRCode.toString(url, { ...common, type: "svg" });
      return new Response(svg, {
        headers: {
          "Content-Type": "image/svg+xml",
          "Cache-Control": "no-store",
        },
      });
    }

    if (format === "dataurl") {
      const dataUrl = await QRCode.toDataURL(url, common);
      return NextResponse.json({ url, dataUrl });
    }

    // 默认 png: 直接吐图片, <img src> 可渲染
    const buf = await QRCode.toBuffer(url, { ...common, type: "png" });
    return new Response(new Uint8Array(buf), {
      headers: {
        "Content-Type": "image/png",
        "Content-Length": buf.byteLength.toString(),
        "Cache-Control": "no-store",
      },
    });
  } catch (error) {
    console.error("[GET /api/apk-qr]", error);
    return NextResponse.json({ error: "QR 生成失败" }, { status: 500 });
  }
}
