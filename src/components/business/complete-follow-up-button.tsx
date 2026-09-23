"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";

export function CompleteFollowUpButton({ taskId }: { taskId: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [notes, setNotes] = useState("");
  const [loading, setLoading] = useState(false);

  async function complete() {
    setLoading(true);
    await fetch(`/api/follow-ups/${taskId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "complete", notes: notes || undefined }),
    });
    router.refresh();
    setLoading(false);
    setOpen(false);
  }

  async function cancel() {
    setLoading(true);
    await fetch(`/api/follow-ups/${taskId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "cancel" }),
    });
    router.refresh();
    setLoading(false);
    setOpen(false);
  }

  if (!open) {
    return (
      <div className="flex gap-2 pt-1">
        <Button size="sm" onClick={() => setOpen(true)} disabled={loading}>
          完成 / 取消
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-2 pt-2 border-t border-divider">
      <Textarea
        placeholder="完成备注 (可选)"
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        rows={2}
      />
      <div className="flex gap-2">
        <Button size="sm" onClick={complete} disabled={loading}>
          ✓ 完成
        </Button>
        <Button size="sm" variant="outline" onClick={cancel} disabled={loading}>
          ✗ 取消
        </Button>
        <Button size="sm" variant="ghost" onClick={() => setOpen(false)} disabled={loading}>
          收起
        </Button>
      </div>
    </div>
  );
}