// ============================================
// /dev/deploy/systemd — systemd units 详情 (借鉴 sales-ai /admin/night-tasks)
//
// 数据源: deploy/systemd/ 模板 + systemctl --user status (实时)
// 主人 v0.1.4 拍板 C 选项 (借鉴 sales-ai)
// per docs/UI_STYLE_GUIDE.md: token 驱动, icon h-4 w-4
// ============================================

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile, readdir } from "node:fs/promises";
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
  Server,
  Clock,
  CheckCircle2,
  XCircle,
  Settings,
  AlertCircle,
  PlayCircle,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "systemd Units · 暖客宝开发工具",
  description: "6 个 systemd unit (3 service + 3 timer) 详情",
};

const execFileAsync = promisify(execFile);

interface UnitConfig {
  filename: string;
  type: "service" | "timer";
  description: string;
  execStart: string;
  onCalendar?: string;
  persistent?: boolean;
  randomizedDelay?: string;
  wants?: string;
  after?: string;
}

async function parseUnitFile(filePath: string, type: "service" | "timer"): Promise<UnitConfig> {
  try {
    const content = await readFile(filePath, "utf-8");
    const desc = content.match(/^#\s*Description:\s*(.+)/m)?.[1].trim() ?? "";
    const execStart = content.match(/^ExecStart=(.+)/m)?.[1].trim() ?? "";
    const onCalendar = content.match(/^OnCalendar=(.+)/m)?.[1].trim();
    const persistent = content.includes("Persistent=true");
    const delay = content.match(/RandomizedDelaySec=(\d+)/)?.[1];
    const wants = content.match(/^Wants=(.+)/m)?.[1].trim();
    const after = content.match(/^After=(.+)/m)?.[1].trim();
    return {
      filename: path.basename(filePath),
      type,
      description: desc,
      execStart,
      onCalendar,
      persistent,
      randomizedDelay: delay,
      wants,
      after,
    };
  } catch {
    return { filename: path.basename(filePath), type, description: "(无)", execStart: "" };
  }
}

async function getUnitStatus(unitName: string): Promise<string> {
  try {
    const { stdout } = await execFileAsync(
      "systemctl",
      ["--user", "is-active", unitName],
      { timeout: 3000 }
    );
    return stdout.trim();
  } catch {
    return "unknown";
  }
}

async function listUnits(): Promise<UnitConfig[]> {
  const systemdDir = path.join(process.cwd(), "deploy/systemd");
  try {
    const files = await readdir(systemdDir);
    const units: UnitConfig[] = [];
    for (const f of files.sort()) {
      if (!f.endsWith(".service") && !f.endsWith(".timer")) continue;
      const type = f.endsWith(".service") ? "service" : "timer";
      const unit = await parseUnitFile(path.join(systemdDir, f), type);
      units.push(unit);
    }
    return units;
  } catch {
    return [];
  }
}

function statusBadge(status: string) {
  if (status === "active")
    return (
      <Badge variant="default" className="bg-primary/10 text-primary border-primary/30">
        <CheckCircle2 className="h-3 w-3 mr-1" />
        active
      </Badge>
    );
  if (status === "inactive")
    return (
      <Badge variant="outline" className="text-muted-foreground">
        <XCircle className="h-3 w-3 mr-1" />
        inactive
      </Badge>
    );
  if (status === "failed")
    return (
      <Badge variant="destructive">
        <AlertCircle className="h-3 w-3 mr-1" />
        failed
      </Badge>
    );
  return (
    <Badge variant="outline" className="text-muted-foreground">
      ? {status}
    </Badge>
  );
}

export default async function SystemdPage() {
  const units = await listUnits();
  // 并行查所有 unit 状态
  const statuses = await Promise.all(units.map((u) => getUnitStatus(u.filename)));

  // 分组
  const services = units.filter((u) => u.type === "service");
  const timers = units.filter((u) => u.type === "timer");
  const serviceStatuses = units
    .filter((u) => u.type === "service")
    .map((_, i) => statuses[units.findIndex((u) => u.type === "service") === i ? i : -1]);
  // 简化: 直接用 index
  const unitStatuses = units.map((u, i) => ({
    name: u.filename,
    status: statuses[i],
  }));

  return (
    <main className="mx-auto max-w-6xl px-4 py-8 sm:py-12">
      <div className="mb-6">
        <Button variant="ghost" size="sm" asChild className="mb-3">
          <Link href="/dev/deploy">
            <ArrowLeft className="h-4 w-4 mr-1" />
            返回 /dev/deploy
          </Link>
        </Button>

        <div className="flex items-center gap-2 mb-2">
          <Settings className="h-7 w-7 text-primary" />
          <h1 className="text-3xl font-bold text-foreground">systemd Units</h1>
        </div>
        <p className="text-muted-foreground">
          3 对 service + timer 详情 (实时状态 + 配置). 借鉴自{" "}
          <a
            href="https://github.com/sales-ai/sales-ai/blob/main/web-next/src/app/(dashboard)/admin/night-tasks/page.tsx"
            className="text-primary hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            sales-ai /admin/night-tasks
          </a>
          .
        </p>
        <div className="mt-3 flex gap-2 flex-wrap">
          <Badge variant="outline">v0.1.4</Badge>
          <Badge variant="secondary">★ 借鉴 sales-ai</Badge>
          <Badge variant="secondary">systemctl --user</Badge>
        </div>
      </div>

      {/* service 列表 */}
      <section className="mb-8">
        <h2 className="text-lg font-semibold text-foreground mb-3 flex items-center gap-2">
          <Server className="h-5 w-5 text-primary" />
          Service ({services.length} 个)
        </h2>
        <div className="space-y-4">
          {services.map((s, i) => {
            const status = unitStatuses.find((us) => us.name === s.filename);
            return (
              <Card key={s.filename}>
                <CardHeader>
                  <div className="flex items-center justify-between flex-wrap gap-2">
                    <CardTitle className="text-base flex items-center gap-2">
                      <PlayCircle className="h-4 w-4 text-primary" />
                      {s.filename}
                    </CardTitle>
                    {statusBadge(status?.status ?? "unknown")}
                  </div>
                </CardHeader>
                <CardContent className="space-y-2 text-sm">
                  <p className="text-muted-foreground">{s.description}</p>
                  <div>
                    <p className="text-xs text-muted-foreground">ExecStart:</p>
                    <code className="text-xs bg-muted px-1.5 py-0.5 rounded font-mono break-all">
                      {s.execStart}
                    </code>
                  </div>
                  {s.after && (
                    <p className="text-xs">
                      <span className="text-muted-foreground">After:</span>{" "}
                      <code className="font-mono">{s.after}</code>
                    </p>
                  )}
                  <p className="text-xs text-muted-foreground">
                    📁 <code className="bg-muted px-1.5 py-0.5 rounded">deploy/systemd/{s.filename}</code>
                  </p>
                </CardContent>
              </Card>
            );
          })}
        </div>
      </section>

      {/* timer 列表 */}
      <section className="mb-8">
        <h2 className="text-lg font-semibold text-foreground mb-3 flex items-center gap-2">
          <Clock className="h-5 w-5 text-primary" />
          Timer ({timers.length} 个)
        </h2>
        <div className="space-y-4">
          {timers.map((t, i) => {
            const status = unitStatuses.find((us) => us.name === t.filename);
            return (
              <Card key={t.filename}>
                <CardHeader>
                  <div className="flex items-center justify-between flex-wrap gap-2">
                    <CardTitle className="text-base flex items-center gap-2">
                      <Clock className="h-4 w-4 text-primary" />
                      {t.filename}
                    </CardTitle>
                    {statusBadge(status?.status ?? "unknown")}
                  </div>
                </CardHeader>
                <CardContent className="space-y-2 text-sm">
                  <p className="text-muted-foreground">{t.description}</p>
                  {t.onCalendar && (
                    <div>
                      <p className="text-xs text-muted-foreground">OnCalendar:</p>
                      <code className="text-xs bg-muted px-1.5 py-0.5 rounded font-mono">
                        {t.onCalendar}
                      </code>
                    </div>
                  )}
                  <div className="flex flex-wrap gap-3 text-xs">
                    {t.persistent && (
                      <span>
                        <span className="text-muted-foreground">Persistent:</span>{" "}
                        <code className="font-mono">true</code>
                      </span>
                    )}
                    {t.randomizedDelay && (
                      <span>
                        <span className="text-muted-foreground">RandomizedDelaySec:</span>{" "}
                        <code className="font-mono">{t.randomizedDelay}</code>
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    📁 <code className="bg-muted px-1.5 py-0.5 rounded">deploy/systemd/{t.filename}</code>
                  </p>
                </CardContent>
              </Card>
            );
          })}
        </div>
      </section>

      {/* 操作 */}
      <section className="mb-8 p-4 bg-muted border border-primary/30 rounded-lg">
        <h3 className="font-semibold text-foreground mb-3">常用命令</h3>
        <div className="space-y-1 text-xs font-mono text-muted-foreground">
          <p>
            <code className="text-foreground">systemctl --user status nuankebao-*</code>
            <span className="ml-2"># 查看所有 unit 状态</span>
          </p>
          <p>
            <code className="text-foreground">systemctl --user list-timers nuankebao-*</code>
            <span className="ml-2"># 查看定时任务</span>
          </p>
          <p>
            <code className="text-foreground">systemctl --user restart nuankebao-nextjs.service</code>
            <span className="ml-2"># 重启 next.js</span>
          </p>
          <p>
            <code className="text-foreground">journalctl --user -u nuankebao-backup -n 30</code>
            <span className="ml-2"># 看备份日志</span>
          </p>
          <p>
            <code className="text-foreground">bash deploy/install-systemd.sh</code>
            <span className="ml-2"># 安装所有 unit (新机器部署)</span>
          </p>
        </div>
      </section>

      <footer className="text-xs text-muted-foreground border-t pt-4">
        <p>
          ⚙️ 模板位置:{" "}
          <code className="bg-muted px-1.5 py-0.5 rounded">deploy/systemd/</code>
          {" "}(git tracked)
        </p>
        <p className="mt-1">
          📋 实际安装位置:{" "}
          <code className="bg-muted px-1.5 py-0.5 rounded">
            ~/.config/systemd/user/
          </code>
          {" "}(gitignored, 用户级 systemd)
        </p>
      </footer>
    </main>
  );
}
