// ============================================
// API route: /api/dev/snapshot (列表)
// GET: 返回最近 N 个 pre-* tag (按 creatordate 倒序)
//
// 数据源: git tag -l "pre-*" (git for-each-ref refs/tags/)
// ============================================

import { NextResponse } from "next/server";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const PROJECT_ROOT = process.cwd();

interface SnapshotTag {
  name: string;
  shortName: string;
  createdAt: string;
  relative: string;
  subject: string;
  headSha: string;
}

async function listSnapshots(): Promise<SnapshotTag[]> {
  try {
    const { stdout } = await execFileAsync(
      "git",
      [
        "for-each-ref",
        "--sort=-creatordate",
        "--format=%(refname:short)|%(creatordate:format:%Y-%m-%d %H:%M)|%(creatordate:relative)|%(subject)|%(objectname:short)",
        "refs/tags/",
      ],
      { cwd: PROJECT_ROOT, maxBuffer: 1024 * 1024 }
    );
    return stdout
      .trim()
      .split("\n")
      .filter((line) => line.startsWith("pre-"))
      .slice(0, 10) // 最近 10 个
      .map((line) => {
        const [name, createdAt, relative, subject, headSha] = line.split("|");
        return { name, shortName: name.replace(/^pre-/, ""), createdAt, relative, subject, headSha };
      });
  } catch {
    return [];
  }
}

export async function GET() {
  const snapshots = await listSnapshots();
  return NextResponse.json({ snapshots });
}
