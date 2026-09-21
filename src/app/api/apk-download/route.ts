import { NextResponse } from "next/server";
import { createReadStream } from "node:fs";
import { statSync } from "node:fs";
import { resolveApkPath } from "@/lib/apk";

export const dynamic = "force-dynamic";

/**
 * GET /api/apk-download
 * 公开下载 暖客宝 release APK
 *
 * 历史 (v0.1.4 之前): 需登录。原意"什么接口都加登录"惯性, 但**被推荐人还没账号**扫码
 *   必然 401 → 二维码形同摆设。主人 2026-09-21 拍「app 不准备上应用商店,
 *   需要让被推荐人方便下载 apk」, 公开下载。
 *
 * 安全评估 (为什么要公开):
 *   - APK = Flutter AOT 编译产物, 业务逻辑 + 加密密钥都在后端 (pgcrypto),
 *     前端 = 公开逻辑, 无敏感数据
 *   - APK 路径候选 (`src/lib/apk.ts`) 全是公开磁盘路径, 登录保护没增加任何机密性
 *   - 带宽滥用走 Cloudflare Tunnel / nginx 限速保护 (跟登录无关)
 *   - APK 版本号 / 元数据 / 二维码 (apk-qr) 同步公开 (扫码前客户就要知道最新版本)
 *
 * APK 发现规则 (见 src/lib/apk.ts):
 *   - NUANKEBAO_APK_PATH 环境变量 (部署时指定) 恒优先
 *   - 其余候选取 mtime 最新者 —— Flutter build 输出 / /tmp / public/downloads,
 *     避免 rebuild 后 /tmp 里的旧拷贝盖过新 APK
 */
export async function GET() {
  const apkPath = await resolveApkPath();
  if (!apkPath) {
    return NextResponse.json(
      {
        error: "APK not found",
        hint: "在 flutter_app 里 flutter build apk --release, 产物会自动被找到; 或拷到 /tmp/NUANKEBAO-release.apk 或 public/downloads/",
        tried: [
          ...(process.env.NUANKEBAO_APK_PATH ? [process.env.NUANKEBAO_APK_PATH] : []),
          "flutter_app/build/app/outputs/flutter-apk/app-release.apk",
          "/tmp/NUANKEBAO-release.apk",
          "public/downloads/NUANKEBAO-release.apk",
        ],
      },
      { status: 404 }
    );
  }

  const stat = statSync(apkPath);
  const stream = createReadStream(apkPath);

  return new Response(stream as unknown as ReadableStream, {
    headers: {
      "Content-Type": "application/vnd.android.package-archive",
      "Content-Disposition": `attachment; filename="nuankebao-release.apk"`,
      "Content-Length": stat.size.toString(),
      "Cache-Control": "no-cache",
    },
  });
}