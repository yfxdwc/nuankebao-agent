// ============================================
// /dev/deploy/night-tasks — 定时任务状态 (借鉴 sales-ai /admin/night-tasks/tasks)
//
// 列出 3 个 systemd timer:
//   - nuankebao-backup.timer (每日 03:00)
//   - nuankebao-code-snapshot.timer (每日 04:00)
//   - nuankebao-restore-verify.timer (月度第一周日 04:00)
//
// 数据源: child_process.execFile "systemctl --user list-timers"
// 主人 v0.1.4 拍板 C 选项 (借鉴 sales-ai)
// per docs/UI_STYLE_GUIDE.md: token 驱动, icon h-4 w-4
// ============================================

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
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
  Clock,
  Server,
  Database,
  GitBranch,
  ShieldCheck,
  Calendar,
  CheckCircle2,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "夜间任务 · 暖客宝开发工具",
  description: "3 个 systemd timer 状态 (backup / code-snapshot / restore-verify)",
};

const execFileAsync = promisify(execFile);

interface TimerInfo {
  unit: string;
  activates: string;
  next: string;
  left: string;
  last: string;
  passed: string;
  description: string;
  schedule: string; // 从 deploy/systemd/<timer>.timer 读 OnCalendar
  scriptPath: string; // 关联的 .service 执行的脚本
}

interface SystemdTimerConfig {
  schedule: string; // e.g. "*-*-* 03:00:00"
  persistent: boolean;
  randomizedDelaySec: string;
}

async function getSystemdTimerConfig(timerName: string): Promise<SystemdTimerConfig> {
  const path = path.join(process.cwd(), "deploy/systemd", `${timerName}.timer`);
  try {
    const content = await readFile(path, "utf-8");
    const schedule = content.match(/OnCalendar=(.+)/)?.[1].trim() ?? "";
    const persistent = content.includes("Persistent=true");
    const delayMatch = content.match(/RandomizedDelaySec=(\d+)/);
    const delay = delayMatch?.[1] ?? "0";
    return {
      schedule,
      persistent,
      randomizedDelaySec: delay,
    };
  } catch {
    return { schedule: "(未找到配置)", persistent: false, randomizedDelaySec: "0" };
  }
}

async function getSystemdTimerDescription(serviceName: string): Promise<string> {
  const path = path.join(process.cwd(), "deploy/systemd", `${serviceName}.service`);
  try {
    const content = await readFile(path, "utf-8");
    // 提取 Description=
    const desc = content.match(/^#\s*Description:\s*(.+)/m)?.[1].trim() ?? "";
    return desc;
  } catch {
    return "(未找到描述)";
  }
}

async function listTimers(): Promise<TimerInfo[]> {
  let stdout = "";
  try {
    const result = await execFileAsync(
      "systemctl",
      ["--user", "list-timers", "nuankebao-*", "--no-pager"],
      { timeout: 5000 }
    );
    stdout = result.stdout;
  } catch {
    return [];
  }

  const lines = stdout.split("\n").filter((l) => l.trim() && !l.includes("listed"));
  const timers: TimerInfo[] = [];
  // Skip header line
  for (const line of lines.slice(1)) {
    const parts = line.trim().split(/\s{2,}/);
    if (parts.length < 5) continue;
    const [next, left, last, passed, unitActivates] = parts;
    const [unit, activates] = unitActivates.split(/\s+/);
    const baseName = unit.replace(".timer", "");

    const [config, description] = await Promise.all([
      getSystemdTimerConfig(baseName),
      getSystemdTimerDescription(baseName),
    ]);

    timers.push({
      unit,
      activates,
      next,
      left,
      last,
      passed,
      description,
      schedule: config.schedule,
      scriptPath: `deploy/systemd/${baseName}.service`,
    });
  }
  return timers;
}

// 静态 task 描述 (从 deploy/README.md + 注释提取)
const TASK_META: Record<
  string,
  { icon: typeof Clock; scheduleDesc: string; color: string }
> = {
  "nuankebao-backup.timer": {
    icon: Database,
    scheduleDesc: "每日 03:00",
    color: "bg-primary/10 text-primary border-primary/30",
  },
  "nuankebao-code-snapshot.timer": {
    icon: GitBranch,
    scheduleDesc: "每日 04:00 (错开 backup 1h)",
    color: "bg-muted text-foreground border-foreground/30",
  },
  "nuankebao-restore-verify.timer": {
    icon: ShieldCheck,
    scheduleDesc: "月度第一周日 04:00",
    color: "bg-foreground/10 text-foreground border-foreground/30",
  },
};

export default async function NightTasksPage() {
  const timers = await listTimers();

  return (
    <main className="mx-auto max-w-6xl px-4 py-8 sm:py-12">
      <section className="mb-6">
        <Button variant="ghost" size="sm" asChild className="mb-3">
          <Link href="/dev/deploy">
            <ArrowLeft className="h-4 w-4 mr-1" />
            返回 /dev/deploy
          </Link>
        </Button>

        <div className="flex items-center gap-2 mb-2">
          <Clock className="h-7 w-7 text-primary" />
          <h1 className="text-3xl font-bold text-foreground">夜间任务</h1>
        </div>
        <p className="text-muted-foreground">
          3 个 systemd timer 实时状态 (备份 / 代码快照 / 还原演练).
          借鉴自{" "}
          <a
            href="https://github.com/sales-ai/sales-ai/blob/main/web-next/src/app/(dashboard)/admin/night-tasks/tasks/page.tsx"
            className="text-primary hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            sales-ai /admin/night-tasks/tasks
          </a>
          .
        </p>
        <div className="mt-3 flex gap-2 flex-wrap">
          <Badge variant="outline">v0.1.4</Badge>
          <Badge variant="secondary">★ 借鉴 sales-ai</Badge>
          <Badge variant="secondary">systemctl --user list-timers</Badge>
        </div>
      </section>

      {/* 任务列表 */}
      <section className="mb-8 space-y-4">
        {timers.length === 0 ? (
          <Card className="border-dashed">
            <CardContent className="pt-6 text-center text-muted-foreground">
              <Server className="h-8 w-8 mx-auto mb-2 opacity-50" />
              <p>无法读取 systemd timer 状态</p>
              <p className="text-xs mt-1">
                可能 systemd --user 不可用, 或 timer 未安装
              </p>
              <p className="text-xs mt-1">
                安装: bash deploy/install-systemd.sh
              </p>
            </CardContent>
          </Card>
        ) : (
          timers.map((t) => {
            const meta = TASK_META[t.unit] || {
              icon: Clock,
              scheduleDesc: "(未知)",
              color: "bg-muted",
            };
            const Icon = meta.icon;
            return (
              <Card key={t.unit}>
                <CardHeader>
                  <div className="flex items-center justify-between flex-wrap gap-2">
                    <CardTitle className="text-base flex items-center gap-2">
                      <Icon className={`h-5 w-5`} />
                      {t.unit.replace(".timer", "")}
                    </CardTitle>
                    <Badge variant="outline" className={`text-xs ${meta.color}`}>
                      {meta.scheduleDesc}
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent className="space-y-3">
                  <p className="text-sm text-muted-foreground">
                    {t.description || "(无描述)"}
                  </p>

                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                    <div>
                      <p className="text-xs text-muted-foreground">下次执行</p>
                      <p className="font-mono text-xs mt-0.5">{t.next}</p>
                      <p className="text-xs text-muted-foreground">({t.left})</p>
                    </div>
                    <div>
                      <p className="text-xs text-muted-foreground">上次执行</p>
                      <p className="font-mono text-xs mt-0.5">{t.last}</p>
                      <p className="text-xs text-muted-foreground">({t.passed})</p>
                    </div>
                    <div>
                      <p className="text-xs text-muted-foreground">激活服务</p>
                      <p className="font-mono text-xs mt-0.5">
                        {t.activates}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs text-muted-foreground">schedule</p>
                      <p className="font-mono text-xs mt-0.5">{t.schedule}</p>
                    </div>
                  </div>

                  <div className="pt-2 border-t">
                    <p className="text-xs text-muted-foreground mb-1">
                      配置: <code className="bg-muted px-1.5 py-0.5 rounded">{t.scriptPath}</code>
                    </p>
                    <p className="text-xs text-muted-foreground">
                      OnCalendar: <code className="font-mono">{t.schedule}</code>
                    </p>
                  </div>
                </CardContent>
              </Card>
            );
          })
        )}
      </section>

      {/* 调度总览 */}
      <section className="mb-8 p-4 bg-muted border border-primary/30 rounded-lg">
        <div className="flex items-start gap-3">
          <Calendar className="h-5 w-5 text-primary mt-0.5 shrink-0" />
          <div className="text-sm">
            <p className="font-semibold text-foreground mb-2">调度总览</p>
            <div className="space-y-1 text-muted-foreground text-xs">
              <p>
                <strong>03:00</strong> → backup (PG dump + Media tar + GPG)
              </p>
              <p>
                <strong>04:00</strong> → code-snapshot (dirty + untracked → 外置盘)
              </p>
              <p>
                <strong>月度第一周日 04:00</strong> → restore-verify
                (解密 → 临时 PG:5435 → 行数比对 → 清理)
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* 合规 */}
      <section className="mb-8 p-4 bg-muted border border-primary/30 rounded-lg">
        <div className="flex items-start gap-3">
          <CheckCircle2 className="h-5 w-5 text-primary mt-0.5 shrink-0" />
          <div className="text-sm">
            <p className="font-semibold text-foreground mb-1">AGENTS §3 红线 + deploy/README</p>
            <ul className="space-y-1 text-muted-foreground text-xs">
              <li>✅ Persistent=true (错过则下次启动补跑)</li>
              <li>✅ RandomizedDelaySec=300 (5min, 防多机同时跑)</li>
              <li>✅ 错开 backup 03:00 + code-snapshot 04:00 (1h 间隔)</li>
              <li>✅ restore-verify 用临时 PG 5435 (不污染主库)</li>
            </ul>
          </div>
        </div>
      </section>

      <footer className="text-xs text-muted-foreground border-t pt-4">
        <p>
          ⚙️ 实时数据: <code className="bg-muted px-1.5 py-0.5 rounded">systemctl --user list-timers
          nuankebao-*</code>
        </p>
        <p className="mt-1">
          📊 备份执行结果见{" "}
          <Link href="/dev/deploy" className="text-primary hover:underline">
            /dev/deploy
          </Link>{" "}
          (atomic JSON).
        </p>
      </footer>
    </main>
  );
}
