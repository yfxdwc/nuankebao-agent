// ============================================
// GET /api/app-version — App 版本 + 安装包元数据 (Flutter 「检查更新」用)
// ============================================
// 回答一个问题: 「服务器上这个包, 是不是比我手机里装的这个新?」
//
// 版本真源: flutter_app/pubspec.yaml 的 version: (0.2.2+3) —— APK 的 versionName
// 就是它 (见 src/lib/apk.ts getAppVersion 注释), 所以客户端拿 package_info 的
// version/buildNumber 直接比就行, 不需要再维护一份版本号。
//
// 安装包元数据: getApkMeta() (存在 / 大小 / 本地构建时间 / md5) —— 客户端用它显示
// 「服务器上的包: 2026-09-05 05:46 · 22.2 MB」并给出下载入口。
// apk 为 null = 服务器上还没有可下载的包 (纯 web 部署), 客户端只显示当前版本。
//
// 边界:
//   - 需要登录 (跟 /api/apk-download 一致, 下载链接本身也是登录保护的)
//   - 不解析 APK 本体 (太贵), 只读 mtime + size + md5
//   - 不做「强制更新」判断 (主人没这个需求, 也不该由服务端强制营业员升级)

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getApkMeta, getAppVersion, parseAppVersionSpec } from "@/lib/apk";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const [spec, apk] = await Promise.all([getAppVersion(), getApkMeta()]);
  const { version, buildNumber } = parseAppVersionSpec(spec);

  // 下载 URL: 跟随当前请求的 host (dev 走 LAN IP, 生产走 AUTH_URL 域名),
  // 跟 /api/apk-qr 同一套推导规则 —— 手机点开就能下, 不用客户端拼 base
  const host = request.headers.get("host") ?? "127.0.0.1:3003";
  const proto = request.headers.get("x-forwarded-proto") ?? "http";

  return NextResponse.json({
    version,
    buildNumber,
    apk: apk
      ? {
          sizeBytes: apk.sizeBytes,
          mtimeLocal: apk.mtimeLocal,
          md5: apk.md5,
          downloadPath: "/api/apk-download",
          downloadUrl: `${proto}://${host}/api/apk-download`,
        }
      : null,
  });
}
