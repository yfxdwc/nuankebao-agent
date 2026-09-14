// ============================================
// /admin/dev/snapshot — 任务快照列表
//
// 主人 2026-09-13 拍板 key_modules_ui (3 个关键 UI 之三).
// 列出最近 10 个 pre-* git tag + diff/rollback 链接.
//
// 数据源: git for-each-ref refs/tags/ (调 /api/dev/snapshot)
// ============================================

import Link from "next/link";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import path from "node:path";
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
  History,
  ArrowUpRight,
  Terminal,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "任务快照 · 暖客宝开发工具",
};

interface SnapshotTag {
  name: string;
  shortName: string;
  createdAt: string;
  relative: string;
  subject: string;
  headSha: string;
}

// 同步 import (不用 dynamic import, Next.js dev mode dynamic import 在 server component
// 里偶尔卡住导致 30s+ 超时, per 2026-09-13 主人反馈 /admin/dev/snapshot 没渲染)
const execFileAsync = promisify(execFile);

async function fetchSnapshots(): Promise<SnapshotTag[]> {
  try {
    const { stdout } = await execFileAsync(
      "git",
      [
        "for-each-ref",
        "--sort=-creatordate",
        "--format=%(refname:short)|%(creatordate:format:%Y-%m-%d %H:%M)|%(creatordate:relative)|%(subject)|%(objectname:short)",
        "refs/tags/",
      ],
      {
        cwd: process.cwd(),
        maxBuffer: 1024 * 1024,
        timeout: 10000, // 10s timeout (git 在大仓库可能慢)
      }
    );
    return stdout
      .trim()
      .split("\n")
      .filter((line) => line.startsWith("pre-"))
      .slice(0, 10)
      .map((line) => {
        const [name, createdAt, relative, subject, headSha] = line.split("|");
        return {
          name,
          shortName: name.replace(/^pre-/, ""),
          createdAt,
          relative,
          subject,
          headSha,
        };
      });
  } catch {
    return [];
  }
}

export default async function SnapshotListPage() {
  const snapshots = await fetchSnapshots();

  return (
    <main className="mx-auto max-w-5xl">
      <div className="mb-6">
        <Button variant="ghost" size="sm" asChild className="mb-3">
          <Link href="/admin/dev">
            <ArrowLeft className="size-4 mr-1" />
            返回 /admin/dev
          </Link>
        </Button>

        <div className="flex items-center gap-2 mb-2">
          <History className="size-7 text-amber-700" />
          <h1 className="text-3xl font-bold text-foreground">
            任务快照 (Task Snapshot)
          </h1>
        </div>
        <p className="text-muted-foreground">
          最近 10 个 <code className="text-xs bg-muted px-1.5 py-0.5 rounded">pre-*</code>{" "}
          git tag. 点击查看 diff, 危险操作 (rollback) 需二次确认.
        </p>
        <div className="mt-3 flex gap-2 flex-wrap">
          <Badge variant="outline">git tag-based 快照</Badge>
          <Badge variant="secondary">.git/snapshots/ 脏状态兜底</Badge>
          <Badge variant="destructive">⚠ Rollback 是破坏性操作</Badge>
        </div>
      </div>

      {snapshots.length === 0 ? (
        <Card className="border-dashed">
          <CardContent className="pt-6 text-center text-muted-foreground">
            <p className="mb-2">无 snapshot tag</p>
            <p className="text-xs">
              创建第一个 snapshot:{" "}
              <code className="bg-muted px-1.5 py-0.5 rounded">
                bash scripts/task-snapshot.sh start &lt;name&gt;
              </code>
            </p>
          </CardContent>
        </Card>
      ) : (
        <section className="space-y-3">
          {snapshots.map((s) => (
            <Link
              key={s.name}
              href={`/admin/dev/snapshot/${encodeURIComponent(s.name)}`}
              className="block group"
            >
              <Card className="hover:shadow-md hover:border-border transition-all">
                <CardHeader className="pb-3">
                  <div className="flex items-center justify-between">
                    <CardTitle className="text-base font-mono flex items-center gap-2">
                      <History className="size-4 text-amber-600" />
                      {s.shortName}
                      <ArrowUpRight className="size-4 text-muted-foreground group-hover:text-muted-foreground transition-colors" />
                    </CardTitle>
                    <div className="text-xs text-muted-foreground">
                      {s.relative} ({s.createdAt})
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="pt-0">
                  <div className="flex items-center justify-between text-sm">
                    <div className="text-muted-foreground">
                      <span className="font-mono text-xs text-muted-foreground mr-2">
                        {s.headSha}
                      </span>
                      {s.subject}
                    </div>
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </section>
      )}

      <footer className="text-xs text-muted-foreground border-t pt-4 mt-8 space-y-1">
        <p>
          📋 完整 SOP 见{" "}
          <a
            href="https://github.com/tooyan/nuankebao-agent/blob/main/scripts/task-snapshot.sh"
            className="text-blue-600 hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            scripts/task-snapshot.sh
          </a>{" "}
          顶部注释, 借鉴自 sales-ai (per{" "}
          <a
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/admin/dev-modules/task-snapshot.md"
            className="text-blue-600 hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            dev-modules/task-snapshot.md
          </a>
          ).
        </p>
        <p>
          ⚙️ 5 个 action: <code>start / list / find / diff / rollback</code> — 前 4 个走 CLI,
          rollback 可在此页面触发.
        </p>
      </footer>
    </main>
  );
}
