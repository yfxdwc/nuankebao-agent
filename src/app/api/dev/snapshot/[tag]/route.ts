// ============================================
// API route: /api/dev/snapshot/[tag]
//
// GET: 返回指定 tag 的 diff stat + commit 列表 (HEAD vs tag)
// POST: 触发 rollback (执行 scripts/task-snapshot.sh rollback <tag>)
//
// ⚠️ POST 是破坏性操作, 必须:
// - 主人手动在 UI 二次确认 (前端 confirm)
// - 未来主人可加 auth (当前 dev 工具简化, 不强制 auth)
// - 实际执行 git checkout + 重启 systemd (脚本已 fail-closed 兜底)
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import path from "node:path";

const execFileAsync = promisify(execFile);

const PROJECT_ROOT = process.cwd();

interface SnapshotCommit {
  sha: string;
  shortSha: string;
  date: string;
  subject: string;
}

async function getDiffStat(tag: string): Promise<string> {
  try {
    const { stdout } = await execFileAsync(
      "git",
      ["diff", "--stat", `${tag}..HEAD`],
      { cwd: PROJECT_ROOT, maxBuffer: 1024 * 1024 }
    );
    return stdout.trim();
  } catch (e) {
    return `(无法读取 diff: ${(e as Error).message})`;
  }
}

async function getCommitList(tag: string): Promise<SnapshotCommit[]> {
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
      { cwd: PROJECT_ROOT, maxBuffer: 1024 * 1024 }
    );
    return stdout
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const [sha, shortSha, date, subject] = line.split("|");
        return { sha, shortSha, date, subject };
      });
  } catch {
    return [];
  }
}

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ tag: string }> }
) {
  const { tag } = await params;

  // 防御: tag 必须以 pre- 开头 (避免任意命令注入)
  if (!/^pre-[a-zA-Z0-9._-]+$/.test(tag)) {
    return NextResponse.json(
      { error: `tag 格式非法: ${tag} (必须 pre-<name>)` },
      { status: 400 }
    );
  }

  const [diffStat, commits] = await Promise.all([
    getDiffStat(tag),
    getCommitList(tag),
  ]);

  return NextResponse.json({ tag, diffStat, commits });
}

export async function POST(
  _req: NextRequest,
  { params }: { params: Promise<{ tag: string }> }
) {
  const { tag } = await params;

  if (!/^pre-[a-zA-Z0-9._-]+$/.test(tag)) {
    return NextResponse.json(
      { error: `tag 格式非法: ${tag}` },
      { status: 400 }
    );
  }

  // 防御: 二次确认 (通过 query param ?confirm=yes)
  // 前端必须先 confirm 才能调此 API
  if (!_req.nextUrl.searchParams.get("confirm")) {
    return NextResponse.json(
      { error: "必须传 ?confirm=yes 二次确认" },
      { status: 400 }
    );
  }

  try {
    // 调 scripts/task-snapshot.sh rollback (而不是 git checkout 直接)
    // 脚本有 fail-closed 兜底 + systemd 重启 + dirty 备份
    const scriptPath = path.join(PROJECT_ROOT, "scripts/task-snapshot.sh");
    const { stdout, stderr } = await execFileAsync(
      "bash",
      [scriptPath, "rollback", tag],
      {
        cwd: PROJECT_ROOT,
        maxBuffer: 1024 * 1024,
        timeout: 30_000, // 30s timeout (systemd 重启可能慢)
      }
    );

    return NextResponse.json({
      ok: true,
      tag,
      stdout: stdout.trim(),
      stderr: stderr.trim(),
    });
  } catch (e: unknown) {
    const error = e as Error & {
      stdout?: string;
      stderr?: string;
      code?: number;
    };
    return NextResponse.json(
      {
        ok: false,
        tag,
        error: error.message,
        stdout: error.stdout?.trim(),
        stderr: error.stderr?.trim(),
        exitCode: error.code,
      },
      { status: 500 }
    );
  }
}
