// ============================================
// /dev/deploy — 部署 + 备份健康 dashboard
//
// 主人 2026-09-13 拍板 key_modules_ui (3 个关键 UI 之二).
// 读取 deploy/backup.sh + code_snapshot.sh + restore_verify.sh 输出的
// atomic JSON 状态 + 最近日志, 显示备份健康.
//
// 数据源 (硬编码路径, 与 deploy/*.sh 的 HEALTH_DIR 一致):
// - /home/tooyan/nuankebao-databackups/backup-health/backup.json
// - /home/tooyan/nuankebao-databackups/backup-health/code-snapshot.json
// - /home/tooyan/nuankebao-databackups/backup-health/restore-verify.json
// - /home/tooyan/nuankebao-databackups/logs/backup.log (最近 20 行)
// - /home/tooyan/nuankebao-databackups/logs/restore-verify.log (最近 10 行)
//
// 部署位置: 主人机器 (per AGENTS.md §6.1 + deploy/README.md)
// 不在 docker / web 容器内运行, 直接读主机的 databackups 目录.
// ============================================

import { readFile, readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  ArrowLeft,
  Database,
  CheckCircle2,
  XCircle,
  Clock,
  HardDrive,
  FileText,
  Activity,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "部署 + 备份 · 暖客宝开发工具",
};

// 硬编码路径 (与 deploy/*.sh 一致)
const DATABACKUPS_ROOT = "/home/tooyan/nuankebao-databackups";
const HEALTH_DIR = path.join(DATABACKUPS_ROOT, "backup-health");
const LOG_DIR = path.join(DATABACKUPS_ROOT, "logs");

interface BackupHealth {
  status: string;
  ts: string;
  host?: string;
  pg_container?: string;
  pg_size_bytes?: number;
  media_size_bytes?: number;
  pg_backup_count?: number;
  media_backup_count?: number;
  elapsed_sec?: number;
  reason?: string;
}

interface RestoreVerifyHealth {
  status: string;
  ts: string;
  host?: string;
  backup_file?: string;
  tables_matched?: number;
  tables_total?: number;
  elapsed_sec?: number;
  reason?: string;
}

async function readJsonSafe<T>(filePath: string): Promise<T | null> {
  try {
    if (!existsSync(filePath)) return null;
    const content = await readFile(filePath, "utf-8");
    return JSON.parse(content) as T;
  } catch {
    return null;
  }
}

async function readTailSafe(
  filePath: string,
  lines: number
): Promise<string[]> {
  try {
    if (!existsSync(filePath)) return [];
    const content = await readFile(filePath, "utf-8");
    const allLines = content.split("\n").filter((l) => l.trim());
    return allLines.slice(-lines);
  } catch {
    return [];
  }
}

function formatBytes(bytes?: number): string {
  if (!bytes) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024)
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function formatDate(iso?: string): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("zh-CN", { hour12: false });
}

function relativeTime(iso?: string): string {
  if (!iso) return "—";
  const now = Date.now();
  const then = new Date(iso).getTime();
  const diffSec = Math.floor((now - then) / 1000);
  if (diffSec < 60) return `${diffSec} 秒前`;
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)} 分钟前`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 3600)} 小时前`;
  return `${Math.floor(diffSec / 86400)} 天前`;
}

async function listPgBackups(): Promise<{ name: string; size: number; mtime: string }[]> {
  const dir = path.join(DATABACKUPS_ROOT, "pg-backups");
  try {
    if (!existsSync(dir)) return [];
    const files = await readdir(dir);
    const stats = await Promise.all(
      files
        .filter((f) => f.startsWith("pg-") && f.endsWith(".dump.gpg"))
        .map(async (f) => {
          const fp = path.join(dir, f);
          const s = await stat(fp);
          return { name: f, size: s.size, mtime: s.mtime.toISOString() };
        })
    );
    return stats.sort((a, b) => b.mtime.localeCompare(a.mtime)).slice(0, 7); // GFS 7 份
  } catch {
    return [];
  }
}

export default async function DeployDashboardPage() {
  const [backup, codeSnapshot, restoreVerify, backupLog, restoreLog, pgBackups] =
    await Promise.all([
      readJsonSafe<BackupHealth>(path.join(HEALTH_DIR, "backup.json")),
      readJsonSafe<BackupHealth>(path.join(HEALTH_DIR, "code-snapshot.json")),
      readJsonSafe<RestoreVerifyHealth>(
        path.join(HEALTH_DIR, "restore-verify.json")
      ),
      readTailSafe(path.join(LOG_DIR, "backup.log"), 20),
      readTailSafe(path.join(LOG_DIR, "restore-verify.log"), 10),
      listPgBackups(),
    ]);

  // GFS 副本数警告 (< 7 即告警)
  const pgBackupCount = backup?.pg_backup_count ?? 0;
  const mediaBackupCount = backup?.media_backup_count ?? 0;
  const gfsWarn = pgBackupCount < 7 || mediaBackupCount < 7;

  return (
    <main className="mx-auto max-w-6xl px-4 py-8 sm:py-12">
      <div className="mb-6">
        <Button variant="ghost" size="sm" asChild className="mb-3">
          <Link href="/dev">
            <ArrowLeft className="size-4 mr-1" />
            返回 /dev
          </Link>
        </Button>

        <div className="flex items-center gap-2 mb-2">
          <Database className="size-7 text-green-700" />
          <h1 className="text-3xl font-bold text-slate-900">
            部署 + 备份 Dashboard
          </h1>
        </div>
        <p className="text-slate-600">
          读取{" "}
          <code className="text-xs bg-slate-100 px-1.5 py-0.5 rounded">
            {DATABACKUPS_ROOT}
          </code>{" "}
          下的 atomic JSON 状态 + 最近日志.
        </p>
        <div className="mt-3 flex gap-2 flex-wrap">
          <Badge variant="outline">每日 03:00 自动跑</Badge>
          <Badge variant="secondary">GFS 7 份 + 异地副本</Badge>
          <Badge variant="secondary">GPG AES256 加密</Badge>
        </div>
      </div>

      {/* 备份健康总览 */}
      <section className="mb-8 grid gap-4 sm:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              {backup?.status === "success" ? (
                <CheckCircle2 className="size-5 text-green-600" />
              ) : (
                <XCircle className="size-5 text-red-600" />
              )}
              上次备份
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div>
              <span className="text-slate-500">状态: </span>
              <Badge
                variant={backup?.status === "success" ? "default" : "destructive"}
              >
                {backup?.status ?? "无数据"}
              </Badge>
            </div>
            <div>
              <span className="text-slate-500">时间: </span>
              {formatDate(backup?.ts)} ({relativeTime(backup?.ts)})
            </div>
            <div>
              <span className="text-slate-500">耗时: </span>
              {backup?.elapsed_sec ?? "—"} 秒
            </div>
            {backup?.reason && (
              <div className="text-xs text-red-600 mt-1">
                原因: {backup.reason}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <HardDrive className="size-5 text-blue-600" />
              备份大小
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div>
              <span className="text-slate-500">PG: </span>
              {formatBytes(backup?.pg_size_bytes)}
            </div>
            <div>
              <span className="text-slate-500">Media: </span>
              {formatBytes(backup?.media_size_bytes)}
            </div>
            <div className="text-xs text-slate-500 mt-2">
              host: {backup?.host ?? "—"}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <FileText className="size-5 text-amber-600" />
              GFS 副本数
              {gfsWarn && (
                <Badge variant="destructive" className="text-xs">
                  警告 &lt; 7
                </Badge>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            <div>
              <span className="text-slate-500">PG: </span>
              <strong>{pgBackupCount}</strong> / 7
            </div>
            <div>
              <span className="text-slate-500">Media: </span>
              <strong>{mediaBackupCount}</strong> / 7
            </div>
            <div className="text-xs text-slate-500 mt-2">
              异地副本: /media/tooyan/&lt;盘符&gt;/nuankebao-*
            </div>
          </CardContent>
        </Card>
      </section>

      {/* 代码快照 + 恢复演练 */}
      <section className="mb-8 grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <Activity className="size-5 text-purple-600" />
              代码快照 (每日 04:00)
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            {codeSnapshot ? (
              <>
                <div>
                  <span className="text-slate-500">状态: </span>
                  <Badge
                    variant={
                      codeSnapshot.status === "success"
                        ? "default"
                        : "destructive"
                    }
                  >
                    {codeSnapshot.status}
                  </Badge>
                </div>
                <div>
                  <span className="text-slate-500">时间: </span>
                  {formatDate(codeSnapshot.ts)} ({relativeTime(codeSnapshot.ts)})
                </div>
                {codeSnapshot.reason && (
                  <div className="text-xs text-red-600 mt-1">
                    原因: {codeSnapshot.reason}
                  </div>
                )}
              </>
            ) : (
              <div className="text-slate-500">无数据</div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <CheckCircle2 className="size-5 text-indigo-600" />
              恢复演练 (月度)
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            {restoreVerify ? (
              <>
                <div>
                  <span className="text-slate-500">状态: </span>
                  <Badge
                    variant={
                      restoreVerify.status === "success"
                        ? "default"
                        : "destructive"
                    }
                  >
                    {restoreVerify.status}
                  </Badge>
                </div>
                <div>
                  <span className="text-slate-500">时间: </span>
                  {formatDate(restoreVerify.ts)} ({relativeTime(restoreVerify.ts)})
                </div>
                <div>
                  <span className="text-slate-500">表行数比对: </span>
                  <strong>{restoreVerify.tables_matched ?? 0}</strong> /{" "}
                  {restoreVerify.tables_total ?? 0}
                </div>
                {restoreVerify.reason && (
                  <div className="text-xs text-red-600 mt-1">
                    原因: {restoreVerify.reason}
                  </div>
                )}
              </>
            ) : (
              <div className="text-slate-500">无数据</div>
            )}
          </CardContent>
        </Card>
      </section>

      {/* PG 备份文件列表 (GFS 7 份) */}
      <section className="mb-8">
        <h2 className="text-lg font-semibold text-slate-900 mb-3">
          PG 备份文件 ({pgBackups.length} 份)
        </h2>
        <Card>
          <CardContent className="pt-4">
            {pgBackups.length === 0 ? (
              <p className="text-sm text-slate-500">无备份文件</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs text-slate-500 border-b">
                    <tr>
                      <th className="pb-2">文件名</th>
                      <th className="pb-2">大小</th>
                      <th className="pb-2">修改时间</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {pgBackups.map((b) => (
                      <tr key={b.name}>
                        <td className="py-1.5 font-mono text-xs">{b.name}</td>
                        <td className="py-1.5">{formatBytes(b.size)}</td>
                        <td className="py-1.5 text-xs">
                          {formatDate(b.mtime)} ({relativeTime(b.mtime)})
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </section>

      {/* 日志摘要 */}
      <section className="mb-8 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">backup.log (最近 20 行)</CardTitle>
          </CardHeader>
          <CardContent>
            <pre className="text-xs font-mono whitespace-pre-wrap bg-slate-50 p-3 rounded max-h-96 overflow-y-auto">
              {backupLog.length === 0
                ? "(空)"
                : backupLog.join("\n")}
            </pre>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">restore-verify.log (最近 10 行)</CardTitle>
          </CardHeader>
          <CardContent>
            <pre className="text-xs font-mono whitespace-pre-wrap bg-slate-50 p-3 rounded max-h-96 overflow-y-auto">
              {restoreLog.length === 0 ? "(空)" : restoreLog.join("\n")}
            </pre>
          </CardContent>
        </Card>
      </section>

      <footer className="text-xs text-slate-500 border-t pt-4 space-y-1">
        <p>
          ⚠️ 数据源是主机的 databackups 目录, 不在 docker / web 容器内. web 服务必须跑在
          主人机器上才能正常读取.
        </p>
        <p>
          📋 完整部署 SOP 见{" "}
          <a
            href="https://github.com/tooyan/nuankebao-agent/blob/main/deploy/README.md"
            className="text-blue-600 hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            deploy/README.md
          </a>{" "}
          (10 章, 含 GFS / 异地 / 密钥管理 / 排错).
        </p>
        <p>
          🔧 systemd 调度: <code>systemctl --user list-timers nuankebao-*</code>
        </p>
      </footer>
    </main>
  );
}
