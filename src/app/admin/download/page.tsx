import { headers } from "next/headers";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { getApkMeta, getAppVersion } from "@/lib/apk";

export const dynamic = "force-dynamic";

export default async function DownloadPage() {
  // 从当前请求的 host 推断 (Next 15 headers 是 async)
  const h = await headers();
  const host = h.get("host") ?? "127.0.0.1:3003";
  const proto = h.get("x-forwarded-proto") ?? "http";
  const apkUrl = `${proto}://${host}/api/apk-download`;
  const qrUrl = `${proto}://${host}/api/apk-qr?url=${encodeURIComponent(apkUrl)}`;

  // 版本 + APK 元数据全部动态读, 不手抄 (避免 rebuild 后显示旧值)
  const [version, meta] = await Promise.all([getAppVersion(), getApkMeta()]);
  const sizeMB = meta ? Math.round((meta.sizeBytes / 1024 / 1024) * 10) / 10 : null;

  return (
    <div className="space-y-6 max-w-3xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">下载 暖客宝 App</h1>
        <p className="text-sm text-muted-foreground mt-1">
          移动端 (Android) 销售用 · 登录 13800138000 + 验证码 123456
        </p>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        {/* 二维码 */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">手机扫码下载</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col items-center space-y-3">
            {/* /api/apk-qr 默认返回 png 字节流, <img> 直接渲染 */}
            <img
              src={qrUrl}
              alt="暖客宝 APK 二维码"
              className="w-64 h-64 border rounded"
            />
            <p className="text-xs text-muted-foreground text-center break-all">
              {apkUrl}
            </p>
          </CardContent>
        </Card>

        {/* 直接下载 */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">直接下载</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <div className="text-sm flex flex-wrap items-center gap-1">
                <strong>暖客宝 v{version}</strong>
                <Badge variant="outline">release</Badge>
              </div>
              {meta ? (
                <p className="text-xs text-muted-foreground break-all">
                  文件: {meta.path}
                  <br />
                  {sizeMB} MB · 构建时间: {meta.mtimeLocal} (本地)
                  <br />
                  md5: <code className="text-xxs">{meta.md5}</code>
                </p>
              ) : (
                <p className="text-xs text-danger">
                  ⚠ APK 文件未找到。在 flutter_app 里跑{" "}
                  <code>flutter build apk --release</code> 后刷新本页即可。
                </p>
              )}
            </div>
            {meta ? (
              <Button asChild className="w-full">
                <a href="/api/apk-download" download>
                  ⬇ 下载 APK ({sizeMB} MB)
                </a>
              </Button>
            ) : (
              <Button className="w-full" disabled>
                ⬇ 下载 APK (无文件)
              </Button>
            )}
            <details className="text-xs text-muted-foreground">
              <summary className="cursor-pointer">安装说明</summary>
              <ol className="list-decimal pl-5 mt-2 space-y-1">
                <li>下载 APK 到手机</li>
                <li>打开文件管理器, 点 APK</li>
                <li>
                  允许{" "}
                  <code>设置 → 安全 → 未知来源</code>{" "}
                  (各品牌路径略不同)
                </li>
                <li>装, 打开 &quot;暖客宝&quot; app</li>
                <li>
                  登录: 手机号 <code>13800138000</code> + 验证码{" "}
                  <code>123456</code>
                </li>
              </ol>
            </details>
          </CardContent>
        </Card>
      </div>

      {/* 说明 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">登录测试账号</CardTitle>
        </CardHeader>
        <CardContent className="text-sm space-y-2">
          <p>
            <strong>手机号:</strong> 13800138000
          </p>
          <p>
            <strong>验证码:</strong> 123456 (开发期 mock, 任何手机号都行)
          </p>
          <p className="text-xs text-muted-foreground">
            验证码是开发期硬编码, 生产环境 W2 接入阿里云 SMS 后会用真实短信。
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
