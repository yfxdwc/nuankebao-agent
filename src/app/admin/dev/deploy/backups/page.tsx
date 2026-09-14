// ============================================
// /admin/dev/deploy/backups — 备份详情 (借鉴 sales-ai /admin/night-tasks/reports)
//
// 数据源: /home/tooyan/nuankebao-databackups/{pg-backups,media,offsite}/
// 显示: 本地 vs 异地对比, GFS 副本数, 还原演练状态
// 主人 v0.1.4 拍板 C 选项 (借鉴 sales-ai)
// per docs/UI_STYLE_GUIDE.md: token 驱动, icon h-4 w-4
// ============================================

import { readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DevPageHeader } from "@/components/dev/dev-page-header";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Database,
  HardDrive,
  Cloud,
  CheckCircle2,
  AlertTriangle,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "备份详情 · 暖客宝开发工具",
  description: "PG + Media 备份 (本地 vs 异地), GFS 副本, 还原演练",
};

const DATABACKUPS_ROOT = "/home/tooyan/nuankebao-databackups";

interface BackupFile {
  name: string;
  size: number;
  mtime: string;
}

async function listBackups(dir: string): Promise<BackupFile[]> {
  if (!existsSync(dir)) return [];
  try {
    const files = await readdir(dir);
    const results: BackupFile[] = [];
    for (const f of files) {
      const fp = path.join(dir, f);
      try {
        const s = await stat(fp);
        results.push({
          name: f,
          size: s.size,
          mtime: s.mtime.toISOString(),
        });
      } catch {
        // skip
      }
    }
    return results.sort((a, b) => b.mtime.localeCompare(a.mtime));
  } catch {
    return [];
  }
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleString("zh-CN", { hour12: false });
}

interface BackupCategoryProps {
  title: string;
  description: string;
  localDir: string;
  offsiteDir: string;
  icon: typeof Database;
  color: string;
}

async function BackupCategory({
  title,
  description,
  localDir,
  offsiteDir,
  icon: Icon,
  color,
}: BackupCategoryProps) {
  const [local, offsite] = await Promise.all([
    listBackups(localDir),
    listBackups(offsiteDir),
  ]);

  // 取本地第 1 个文件做"最新备份"摘要
  const latest = local[0];
  const totalLocalSize = local.reduce((sum, f) => sum + f.size, 0);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base flex items-center gap-2">
          <Icon className="h-5 w-5 text-primary" />
          {title}{" "}
          <span className="text-muted-foreground font-normal">
            ({local.length} 本地 / {offsite.length} 异地)
          </span>
        </CardTitle>
        <p className="text-sm text-muted-foreground mt-1">{description}</p>
      </CardHeader>
      <CardContent>
        {/* 最新备份摘要 */}
        {latest && (
          <div className="mb-4 p-3 bg-muted rounded-lg">
            <p className="text-xs text-muted-foreground mb-1">
              最新备份 ({formatDate(latest.mtime)})
            </p>
            <p className="font-mono text-sm">{latest.name}</p>
            <p className="text-xs text-muted-foreground mt-1">
              {formatBytes(latest.size)} · 总本地 {formatBytes(totalLocalSize)}
            </p>
          </div>
        )}

        {/* 本地 vs 异地对比 */}
        <div className="grid gap-4 md:grid-cols-2">
          <div>
            <h3 className="text-sm font-semibold text-foreground mb-2 flex items-center gap-1">
              <HardDrive className="h-4 w-4 text-primary" />
              本地 ({local.length} 副本)
            </h3>
            <div className="space-y-1">
              {local.slice(0, 7).map((f) => (
                <div
                  key={f.name}
                  className="flex items-center justify-between text-xs py-1 border-b last:border-0"
                >
                  <span className="font-mono truncate">{f.name}</span>
                  <span className="text-muted-foreground shrink-0 ml-2">
                    {formatBytes(f.size)}
                  </span>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h3 className="text-sm font-semibold text-foreground mb-2 flex items-center gap-1">
              <Cloud className="h-4 w-4 text-primary" />
              异地 ({offsite.length} 副本)
            </h3>
            {offsite.length === 0 ? (
              <p className="text-xs text-muted-foreground italic">
                异地副本未挂载 / 未同步
              </p>
            ) : (
              <div className="space-y-1">
                {offsite.slice(0, 7).map((f) => (
                  <div
                    key={f.name}
                    className="flex items-center justify-between text-xs py-1 border-b last:border-0"
                  >
                    <span className="font-mono truncate">{f.name}</span>
                    <span className="text-muted-foreground shrink-0 ml-2">
                      {formatBytes(f.size)}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

export default async function BackupsPage() {
  return (
    <main className="mx-auto max-w-5xl">
      <DevPageHeader
        backHref="/admin/dev/deploy"
        backLabel="返回 /admin/dev/deploy"
        icon={Database}
        title="备份详情"
        description={
          <>
            PG dump + Media tar 备份文件 (本地 vs 异地对比). 借鉴自{" "}
            <a
              href="https://github.com/sales-ai/sales-ai/blob/main/web-next/src/app/(dashboard)/admin/night-tasks/reports/page.tsx"
              className="text-primary hover:underline"
              target="_blank"
              rel="noreferrer"
            >
              sales-ai /admin/night-tasks/reports
            </a>
            .
          </>
        }
        badges={[
          { label: "v0.1.4", variant: "outline" },
          { label: "★ 借鉴 sales-ai" },
          { label: "GFS 7 副本" },
          { label: "GPG AES256" },
        ]}
      />

      <section className="mb-8 space-y-6">
        <BackupCategory
          title="PG 备份"
          description="PostgreSQL 数据库备份 (pg_dump -Fc)"
          localDir={`${DATABACKUPS_ROOT}/pg-backups`}
          offsiteDir={`${DATABACKUPS_ROOT}/offsite/pg-backups`}
          icon={Database}
          color="bg-primary/10 text-primary border-primary/30"
        />
        <BackupCategory
          title="Media 备份"
          description="上传媒体文件 (tar --zstd + GPG)"
          localDir={`${DATABACKUPS_ROOT}/media`}
          offsiteDir={`${DATABACKUPS_ROOT}/offsite/media`}
          icon={HardDrive}
          color="bg-primary/10 text-primary border-primary/30"
        />
      </section>

      {/* 3-2-1 备份策略说明 */}
      <section className="mb-8 p-4 bg-muted border border-primary/30 rounded-lg">
        <div className="flex items-start gap-3">
          <CheckCircle2 className="h-5 w-5 text-primary mt-0.5 shrink-0" />
          <div className="text-sm">
            <p className="font-semibold text-foreground mb-2">
              3-2-1 备份策略 (per deploy/README §2.1)
            </p>
            <div className="space-y-1 text-muted-foreground text-xs">
              <p>
                <strong>3</strong> 副本: 本地 (1) + 异地 (1) + 上一期 GFS 轮转 (1+)
              </p>
              <p>
                <strong>2</strong> 介质: nvme (本地) + 外置盘 (异地) [AGENTS §6.1]
              </p>
              <p>
                <strong>1</strong> 异地: /media/tooyan/&lt;盘符&gt;/nuankebao-databackups (3-2-1 防单点)
              </p>
              <p className="mt-2">
                <strong>GFS 双保险</strong>: mtime+14 AND count≤7 (per SOP §2.4)
              </p>
              <p>
                <strong>GPG AES256</strong>: passphrase-file 加密 (SOP §2.2)
              </p>
            </div>
          </div>
        </div>
      </section>

      <section className="mb-8 p-4 bg-muted border border-primary/30 rounded-lg">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-primary mt-0.5 shrink-0" />
          <div className="text-sm">
            <p className="font-semibold text-foreground mb-1">⚠️ 实战建议</p>
            <ul className="space-y-1 text-muted-foreground text-xs">
              <li>
                📊 GFS 副本数 &lt; 7 → 警告, 详见{" "}
                <Link
                  href="/admin/dev/deploy"
                  className="text-primary hover:underline"
                >
                  /admin/dev/deploy
                </Link>{" "}
                总览
              </li>
              <li>🔄 月度演练: restore-verify.sh (临时 PG:5435 + 行数比对)</li>
              <li>📋 还原 SOP: deploy/README.md §5 (分步指南)</li>
            </ul>
          </div>
        </div>
      </section>

      <footer className="text-xs text-muted-foreground border-t pt-4">
        <p>
          📊 自动扫描:{" "}
          <code className="bg-muted px-1.5 py-0.5 rounded">
            /home/tooyan/nuankebao-databackups/
          </code>
        </p>
        <p className="mt-1">
          ⚙️ 备份脚本:{" "}
          <code className="bg-muted px-1.5 py-0.5 rounded">deploy/backup.sh</code>{" "}
          (PG) + <code className="bg-muted px-1.5 py-0.5 rounded">deploy/backup.sh</code>{" "}
          (Media, 同一脚本)
        </p>
      </footer>
    </main>
  );
}
