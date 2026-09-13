import { NextRequest, NextResponse } from "next/server";
import { createReadStream } from "node:fs";
import { statSync } from "node:fs";
import { auth } from "@/lib/auth";
import { resolveApkPath } from "@/lib/apk";

export const dynamic = "force-dynamic";

/**
 * GET /api/apk-download
 * 下载 暖客宝 release APK (需登录)
 *
 * APK 发现规则 (见 src/lib/apk.ts):
 *   - NUANKEBAO_APK_PATH 环境变量 (部署时指定) 恒优先
 *   - 其余候选取 mtime 最新者 —— Flutter build 输出 / /tmp / public/downloads,
 *     避免 rebuild 后 /tmp 里的旧拷贝盖过新 APK
 */
export async function GET(request: NextRequest) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

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