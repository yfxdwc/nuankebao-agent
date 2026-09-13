"use client";

// ============================================
// Rollback 按钮 (client component)
// 危险操作: 调 POST /api/dev/snapshot/[tag]?confirm=yes
// 二次确认 + loading + 错误显示 + 成功后跳转
// ============================================

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Undo2, Loader2 } from "lucide-react";

interface RollbackButtonProps {
  tag: string;
  shortName: string;
}

export function RollbackButton({ tag, shortName }: RollbackButtonProps) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleRollback() {
    // 三重确认
    const ok1 = window.confirm(
      `⚠️ 危险操作: 回滚到 ${tag}\n\n` +
        `这会:\n` +
        `1. stash 当前未提交状态\n` +
        `2. git checkout 到 ${tag}\n` +
        `3. 重启 nuankebao-* systemd service\n\n` +
        `继续?`
    );
    if (!ok1) return;

    const ok2 = window.confirm(
      `再次确认: 回滚到 ${tag}?\n\n` +
        `如果当前有 WIP (work in progress), 先 commit 或 rollback 到其他 tag.`
    );
    if (!ok2) return;

    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/dev/snapshot/${encodeURIComponent(tag)}?confirm=yes`,
        { method: "POST" }
      );
      const data = await res.json();
      if (!res.ok || !data.ok) {
        throw new Error(data.stderr || data.error || `HTTP ${res.status}`);
      }
      alert(`✅ 回滚成功\n\nstdout:\n${data.stdout}\n\nstderr:\n${data.stderr}`);
      router.push("/dev/snapshot");
      router.refresh();
    } catch (e) {
      setError((e as Error).message);
      setLoading(false);
    }
  }

  return (
    <div className="flex flex-col gap-2">
      <Button
        variant="destructive"
        onClick={handleRollback}
        disabled={loading}
      >
        {loading ? (
          <>
            <Loader2 className="size-4 mr-1 animate-spin" />
            回滚中...
          </>
        ) : (
          <>
            <Undo2 className="size-4 mr-1" />
            回滚到此 snapshot
          </>
        )}
      </Button>
      {error && (
        <div className="text-xs text-red-600 bg-red-50 p-2 rounded border border-red-200">
          <strong>错误:</strong> {error}
        </div>
      )}
      <p className="text-xs text-slate-500">
        snapshot: <code className="bg-slate-100 px-1.5 py-0.5 rounded">{shortName}</code>
      </p>
    </div>
  );
}
