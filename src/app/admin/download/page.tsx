import { headers } from "next/headers";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/ui/page-header";
import { Section } from "@/components/ui/section";
import { StatRow, StatGroup } from "@/components/ui/stat-row";
import { Badge } from "@/components/ui/badge";
import { getApkMeta, getAppVersion } from "@/lib/apk";

export const dynamic = "force-dynamic";

export default async function DownloadPage() {
  // 从当前请求的 host 推断 (Next 15 headers 是 async)
  const h = await headers();
  const host = h.get("host") ?? "127.0.0.1:3003";
  const proto = h.get("X-Forwarded-Proto") ?? "http";
  const apkUrl = `${proto}://${host}/api/apk-download`;
  const qrUrl = `${proto}://${host}/api/apk-qr?url=${encodeURIComponent(apkUrl)}`;

  // 版本 + APK 元数据全部动态读, 不手抄 (避免 rebuild 后显示旧值)
  const [version, meta] = await Promise.all([getAppVersion(), getApkMeta()]);
  const sizeMB = meta ? Math.round((meta.sizeBytes / 1024 / 1024) * 10) / 10 : null;

  return (
    <div className="space-y-section-y max-w-3xl">
      <PageHeader
        title="下载 暖客宝 App"
        description="移动端 (Android) 销售用 · 登录 13800138000 + 验证码 123456"
      />

      {/* 二维码 + 直接下载 (左右两栏, 桌面端 lg:grid-cols-2) */}
      <div className="grid gap-section-y md:grid-cols-2">
        <Section title="手机扫码下载">
          <div className="flex flex-col items-center space-y-3">
            <img
              src={qrUrl}
              alt="暖客宝 APK 二维码"
              className="w-64 h-64 border border-divider rounded"
            />
            <p className="text-caption text-content-secondary text-center break-all tabular-nums">
              {apkUrl}
            </p>
          </div>
        </Section>

        <Section title="直接下载">
          <div className="space-y-section-y">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-body-lg font-medium text-content-primary">
                暖客宝 v{version}
              </span>
              <Badge variant="outline" className="text-caption">release</Badge>
            </div>
            <StatGroup divided={false}>
              {meta ? (
                <>
                  <StatRow label="文件大小" value={`${sizeMB} MB`} />
                  <StatRow label="构建时间" value={meta.mtimeLocal} />
                  <StatRow label="MD5" value={meta.md5} />
                </>
              ) : (
                <p className="text-body text-danger bg-danger-surface rounded-md p-2">
                  ⚠ APK 文件未找到。在 flutter_app 里跑
                  <code> flutter build apk --release </code>
                  后刷新本页即可。
                </p>
              )}
            </StatGroup>
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
            <details className="text-caption text-content-secondary">
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
          </div>
        </Section>
      </div>

      {/* 登录测试账号 */}
      <Section title="登录测试账号">
        <ul className="divide-y divide-divider">
          <li className="py-2.5 flex items-center justify-between gap-2">
            <span className="text-body-lg text-content-primary">手机号</span>
            <span className="text-body-lg tabular-nums">13800138000</span>
          </li>
          <li className="py-2.5 flex items-center justify-between gap-2">
            <span className="text-body-lg text-content-primary">验证码</span>
            <span className="text-body-lg text-content-secondary">123456 (开发期 mock, 任何手机号都行)</span>
          </li>
        </ul>
        <p className="text-caption text-content-tertiary mt-section-y">
          验证码是开发期硬编码, 生产环境 W2 接入阿里云 SMS 后会用真实短信。
        </p>
      </Section>
    </div>
  );
}