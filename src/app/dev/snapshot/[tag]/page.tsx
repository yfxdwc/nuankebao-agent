// ============================================
// /dev/snapshot/[tag] — 单个 snapshot 详情 + rollback 按钮
// ============================================

import Link from "next/link";
import { notFound } from "next/navigation";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
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
  GitCommit,
  AlertTriangle,
} from "lucide-react";
import { RollbackButton } from "@/components/dev/rollback-button";

export const dynamic = "force-dynamic";

interface PageProps {
  params: Promise<{ tag: string }>;
}

interface CommitInfo {
  sha: string;
  shortSha: string;
  date: string;
  subject: string;
}

async function fetchSnapshotDetail(tag: string) {
  if (!/^pre-[a-zA-Z0-9._-]+$/.test(tag)) {
    return null;
  }

  const execFileAsync = promisify(execFile);

  let diffStat = "";
  let commits: CommitInfo[] = [];

  try {
    const { stdout } = await execFileAsync(
      "git",
      ["diff", "--stat", `${tag}..HEAD`],
      { maxBuffer: 1024 * 1024 }
    );
    diffStat = stdout.trim();
  } catch {
    diffStat = "(无法读取 diff stat)";
  }

  try {
    const { stdout } = await execFileAsync(
      "git",
      [
        "log",
        "--oneline",
        "--pretty=format:%H|%h|%ad|%s",
        "--date=short",
        `${tag}..HEAD`,
      ],
      { maxBuffer: 1024 * 1024 }
    );
    commits = stdout
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const [sha, shortSha, date, subject] = line.split("|");
        return { sha, shortSha, date, subject };
      });
  } catch {
    commits = [];
  }

  return { tag, diffStat, commits };
}

export default async function SnapshotDetailPage({ params }: PageProps) {
  const { tag } = await params;
  const detail = await fetchSnapshotDetail(tag);

  if (!detail) {
    notFound();
  }

  return (
    <main className="mx-auto max-w-5xl px-4 py-8 sm:py-12">
      <div className="mb-6">
        <Button variant="ghost" size="sm" asChild className="mb-3">
          <Link href="/dev/snapshot">
            <ArrowLeft className="size-4 mr-1" />
            返回 /dev/snapshot
          </Link>
        </Button>

        <div className="flex items-center gap-2 mb-2">
          <History className="size-7 text-amber-700" />
          <h1 className="text-3xl font-bold text-slate-900 font-mono break-all">
            {detail.tag}
          </h1>
        </div>
        <p className="text-slate-600">
          snapshot 详情 + diff stat + commit 列表 + ⚠ rollback 按钮
        </p>
      </div>

      {/* Rollback 警告区 */}
      <Card className="mb-6 border-red-300 bg-red-50">
        <CardHeader>
          <CardTitle className="text-base text-red-800 flex items-center gap-2">
            <AlertTriangle className="size-5" />
            Rollback 危险操作
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-red-700 mb-4">
            ⚠️ 回滚到 <code className="font-mono">{detail.tag}</code> 会:
            <br />
            1. stash 当前未提交状态 (含 untracked)
            <br />
            2. <code>git checkout {detail.tag}</code>
            <br />
            3. 应用 <code>.git/snapshots/{detail.tag}.diff</code> 兜底
            <br />
            4. 重启 <code>nuankebao-*.service</code> systemd units
          </p>
          <RollbackButton tag={detail.tag} shortName={detail.tag.replace(/^pre-/, "")} />
        </CardContent>
      </Card>

      {/* Diff stat */}
      <section className="mb-6">
        <h2 className="text-lg font-semibold text-slate-900 mb-3">Diff stat</h2>
        <Card>
          <CardContent className="pt-4">
            <pre className="text-xs font-mono whitespace-pre overflow-x-auto bg-slate-50 p-3 rounded max-h-96 overflow-y-auto">
              {detail.diffStat || "(无变更)"}
            </pre>
          </CardContent>
        </Card>
      </section>

      {/* Commits */}
      <section className="mb-6">
        <h2 className="text-lg font-semibold text-slate-900 mb-3">
          Commits ({detail.commits.length} 个)
        </h2>
        {detail.commits.length === 0 ? (
          <Card className="border-dashed">
            <CardContent className="pt-4 text-center text-slate-500">
              无 commits (snapshot 与 HEAD 相同)
            </CardContent>
          </Card>
        ) : (
          <Card>
            <CardContent className="pt-4">
              <ol className="space-y-2">
                {detail.commits.map((c) => (
                  <li key={c.sha} className="flex items-start gap-3 text-sm">
                    <GitCommit className="size-4 text-slate-400 mt-0.5 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <code className="text-xs text-slate-500 mr-2">
                        {c.shortSha}
                      </code>
                      <span className="text-slate-700">{c.subject}</span>
                    </div>
                    <span className="text-xs text-slate-500 shrink-0">
                      {c.date}
                    </span>
                  </li>
                ))}
              </ol>
            </CardContent>
          </Card>
        )}
      </section>

      <footer className="text-xs text-slate-500 border-t pt-4">
        <p>
          API:{" "}
          <code className="bg-slate-100 px-1.5 py-0.5 rounded">
            GET /api/dev/snapshot/{detail.tag}
          </code>{" "}
          |{" "}
          <code className="bg-slate-100 px-1.5 py-0.5 rounded">
            POST /api/dev/snapshot/{detail.tag}?confirm=yes
          </code>
        </p>
      </footer>
    </main>
  );
}
