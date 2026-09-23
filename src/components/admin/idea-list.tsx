"use client";

// ============================================
// idea-list — 主人待开发想法 CRUD UI (client component)
//
// v0.1.5 主人 2026-09-23 拍 (ask_user d3e7f2a1 第二轮):
//   「我需要能手动记录一个待开发的想法, 有些备忘的意思, 可以增删改,
//    完成后勾选完成, 或丢弃」
//
// 设计 (docs/ui-principles.md):
//   - 列表不套 Card, 用 1px 分隔线分组 (原则 4) ★
//   - 状态色只在有状态时出现 (原则 5): done=success, discarded=muted, open=default
//   - 状态切换 = inline 3 个 toggle (当前状态高亮), 跟"勾选完成"语义贴
//   - 新增 = 顶部一行输入框 + 按钮, 不弹层 (主人快速记)
//   - description 折叠默认 (主人说"有些备忘的意思" → 一句话标题足够常见)
//   - 真删 = 二次确认 (alert 浏览器原生, 不引入 Dialog 依赖)
//
// 不要做的:
//   - ❌ 卡片套卡片
//   - ❌ 给列表加 Card 容器
//   - ❌ 弹层/Sheet (主人增删改高频, 弹层太重)
// ============================================

import { useEffect, useState, useTransition, type FormEvent } from "react";
import { Check, Circle, X, Trash2, ChevronDown, ChevronUp, Plus } from "lucide-react";
import { cn } from "@/lib/utils";

// ---------- 类型 ----------
type IdeaStatus = "open" | "done" | "discarded";

interface Idea {
  id: string;
  userId: string;
  title: string;
  description: string;
  status: IdeaStatus;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
}

// ---------- API helper ----------
async function apiIdeasList(status?: IdeaStatus): Promise<Idea[]> {
  const q = status ? `?status=${status}` : "";
  const res = await fetch(`/api/ideas${q}`, { cache: "no-store" });
  if (!res.ok) throw new Error(`列表拉取失败: ${res.status}`);
  const data = (await res.json()) as { items: Idea[] };
  return data.items;
}

async function apiIdeaCreate(title: string, description: string): Promise<Idea> {
  const res = await fetch("/api/ideas", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ title, description }),
  });
  if (!res.ok) {
    const e = await res.json().catch(() => ({}));
    throw new Error(e.error ?? `创建失败: ${res.status}`);
  }
  const data = (await res.json()) as { item: Idea };
  return data.item;
}

async function apiIdeaUpdate(
  id: string,
  patch: { title?: string; description?: string; status?: IdeaStatus }
): Promise<Idea> {
  const res = await fetch(`/api/ideas/${id}`, {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(patch),
  });
  if (!res.ok) {
    const e = await res.json().catch(() => ({}));
    throw new Error(e.error ?? `更新失败: ${res.status}`);
  }
  const data = (await res.json()) as { item: Idea };
  return data.item;
}

async function apiIdeaDelete(id: string): Promise<void> {
  const res = await fetch(`/api/ideas/${id}`, { method: "DELETE" });
  if (!res.ok) throw new Error(`删除失败: ${res.status}`);
}

// ---------- Tab ----------
type TabKey = "all" | IdeaStatus;

const TABS: { key: TabKey; label: string }[] = [
  { key: "all", label: "全部" },
  { key: "open", label: "待办" },
  { key: "done", label: "已完成" },
  { key: "discarded", label: "已丢弃" },
];

// ---------- 组件 ----------
export function IdeaList() {
  const [tab, setTab] = useState<TabKey>("open");
  const [items, setItems] = useState<Idea[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  // 新增 form state
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [expanded, setExpanded] = useState(false);
  const [creating, setCreating] = useState(false);

  // description 展开哪些行 (按 idea.id 存 set)
  const [expandedDesc, setExpandedDesc] = useState<Set<string>>(new Set());

  // 加载列表
  useEffect(() => {
    setLoading(true);
    setError(null);
    apiIdeasList(tab === "all" ? undefined : tab)
      .then(setItems)
      .catch((e) => setError(String(e.message ?? e)))
      .finally(() => setLoading(false));
  }, [tab]);

  // ---------- 事件 ----------
  function submitNew(e: FormEvent) {
    e.preventDefault();
    const t = title.trim();
    if (!t) return;
    setCreating(true);
    startTransition(async () => {
      try {
        await apiIdeaCreate(t, description.trim());
        setTitle("");
        setDescription("");
        setExpanded(false);
        // 刷新列表 (无论哪个 tab, 因为新建默认 open, 切到 open 看)
        const list = await apiIdeasList(tab === "all" ? undefined : tab);
        setItems(list);
      } catch (e) {
        setError(String((e as Error).message ?? e));
      } finally {
        setCreating(false);
      }
    });
  }

  async function changeStatus(id: string, status: IdeaStatus) {
    try {
      await apiIdeaUpdate(id, { status });
      setItems((prev) =>
        prev.map((it) =>
          it.id === id
            ? {
                ...it,
                status,
                completedAt:
                  status === "done"
                    ? new Date().toISOString()
                    : null,
                updatedAt: new Date().toISOString(),
              }
            : it
        )
      );
      // 切换了 tab 过滤后, 状态跟 tab 不符就该消失; 这里乐观更新后, 实际再 refresh
      if (tab !== status) {
        const list = await apiIdeasList(tab === "all" ? undefined : tab);
        setItems(list);
      }
    } catch (e) {
      setError(String((e as Error).message ?? e));
    }
  }

  async function deleteOne(id: string) {
    if (!window.confirm("真删这条想法? (audit_log 会留痕, 但想法本身不可恢复)")) {
      return;
    }
    try {
      await apiIdeaDelete(id);
      setItems((prev) => prev.filter((it) => it.id !== id));
    } catch (e) {
      setError(String((e as Error).message ?? e));
    }
  }

  function toggleDescExpand(id: string) {
    setExpandedDesc((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  // ---------- 渲染 ----------
  return (
    <div className="space-y-4">
      {/* ===== 新增表单 (顶部, 不弹层) ===== */}
      <form onSubmit={submitNew} className="space-y-2">
        <div className="flex items-stretch gap-2">
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="一句话记一下这个想法..."
            className="flex-1 h-10 px-3 rounded-md border border-border bg-background text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
            disabled={creating}
            maxLength={200}
          />
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            className="h-10 px-3 rounded-md border border-border bg-background text-sm text-muted-foreground hover:bg-muted transition-colors"
            aria-label={expanded ? "收起描述" : "展开描述"}
            disabled={creating}
          >
            {expanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>
          <button
            type="submit"
            disabled={creating || !title.trim()}
            className="h-10 px-4 rounded-md bg-primary text-primary-foreground text-sm font-medium hover:bg-primary/90 transition-colors disabled:opacity-50 inline-flex items-center gap-1.5"
          >
            <Plus className="h-4 w-4" />
            新增
          </button>
        </div>
        {expanded && (
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="详细描述 (可空)"
            rows={3}
            maxLength={5000}
            className="w-full px-3 py-2 rounded-md border border-border bg-background text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring resize-none"
            disabled={creating}
          />
        )}
      </form>

      {/* ===== Tabs (状态切换) ===== */}
      <div className="flex gap-1 border-b border-border overflow-x-auto" role="tablist">
        {TABS.map((t) => {
          const active = tab === t.key;
          return (
            <button
              key={t.key}
              role="tab"
              aria-selected={active}
              onClick={() => setTab(t.key)}
              className={cn(
                "px-3 py-1.5 text-sm font-medium rounded-t-md transition-colors",
                active
                  ? "bg-primary/10 text-primary"
                  : "text-muted-foreground hover:text-foreground hover:bg-muted"
              )}
            >
              {t.label}
            </button>
          );
        })}
      </div>

      {/* ===== 错误提示 ===== */}
      {error && (
        <div className="rounded-md border border-warning/40 bg-warning-surface p-3 text-sm">
          <div className="font-medium text-warning-foreground">⚠ {error}</div>
        </div>
      )}

      {/* ===== 列表 (1px 分隔线分组, 不套 Card) ===== */}
      {loading ? (
        <p className="text-sm text-muted-foreground py-4">加载中...</p>
      ) : items.length === 0 ? (
        <p className="text-sm text-muted-foreground py-4">
          {tab === "open"
            ? "还没有待办的想法 — 上方记一条?"
            : tab === "done"
            ? "还没有已完成的想法"
            : tab === "discarded"
            ? "没有丢弃的想法"
            : "空 — 上方记第一条吧"}
        </p>
      ) : (
        <ul className="divide-y divide-border border-y border-border">
          {items.map((it) => {
            const isOpen = it.status === "open";
            const isDone = it.status === "done";
            const isDiscarded = it.status === "discarded";
            const descShown =
              expandedDesc.has(it.id) || (isOpen && it.description.length === 0 && false);
            return (
              <li key={it.id} className="py-3 space-y-2">
                {/* 行头: title (左) + 状态切换 + 删除 (右) */}
                <div className="flex items-start gap-3 flex-wrap">
                  <p
                    className={cn(
                      "flex-1 min-w-0 text-sm font-medium",
                      isDone
                        ? "text-muted-foreground line-through"
                        : isDiscarded
                        ? "text-muted-foreground line-through"
                        : "text-foreground"
                    )}
                  >
                    {it.title}
                  </p>

                  {/* 状态 toggle (3 个按钮, 当前高亮) */}
                  <div className="flex items-center gap-1 shrink-0">
                    <StatusBtn
                      active={isOpen}
                      label="待办"
                      onClick={() => changeStatus(it.id, "open")}
                      variant="outline"
                    >
                      <Circle className="h-3.5 w-3.5" />
                    </StatusBtn>
                    <StatusBtn
                      active={isDone}
                      label="完成"
                      onClick={() => changeStatus(it.id, "done")}
                      variant="success"
                    >
                      <Check className="h-3.5 w-3.5" />
                    </StatusBtn>
                    <StatusBtn
                      active={isDiscarded}
                      label="丢弃"
                      onClick={() => changeStatus(it.id, "discarded")}
                      variant="muted"
                    >
                      <X className="h-3.5 w-3.5" />
                    </StatusBtn>
                  </div>

                  {/* 删除 (右, 危险操作) */}
                  <button
                    type="button"
                    onClick={() => deleteOne(it.id)}
                    className="p-1.5 rounded-md text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors shrink-0"
                    aria-label="删除"
                    title="真删这条想法"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>

                {/* description 区域 (折叠) */}
                {it.description && (
                  <div className="pl-1">
                    {descShown ? (
                      <p className="text-sm text-muted-foreground whitespace-pre-wrap">
                        {it.description}
                      </p>
                    ) : null}
                    <button
                      type="button"
                      onClick={() => toggleDescExpand(it.id)}
                      className="text-xs text-info hover:underline mt-1"
                    >
                      {descShown ? "收起描述" : "展开描述"}
                    </button>
                  </div>
                )}

                {/* 元信息 */}
                <div className="text-xs text-muted-foreground tabular-nums pl-1">
                  {isDone && it.completedAt
                    ? `完成于 ${it.completedAt.slice(0, 16).replace("T", " ")}`
                    : `更新于 ${it.updatedAt.slice(0, 16).replace("T", " ")}`}
                </div>
              </li>
            );
          })}
        </ul>
      )}

      {isPending && (
        <p className="text-xs text-muted-foreground">操作中...</p>
      )}
    </div>
  );
}

// ---------- 内部小组件: 状态按钮 ----------
function StatusBtn({
  active,
  label,
  onClick,
  variant,
  children,
}: {
  active: boolean;
  label: string;
  onClick: () => void;
  variant: "outline" | "success" | "muted";
  children: React.ReactNode;
}) {
  const activeClass =
    variant === "success"
      ? "bg-success text-success-foreground border-success"
      : variant === "muted"
      ? "bg-muted-foreground text-background border-muted-foreground"
      : "bg-primary text-primary-foreground border-primary";
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      title={label}
      className={cn(
        "inline-flex items-center justify-center h-7 min-w-7 px-1.5 rounded-md border text-xs transition-colors",
        active
          ? activeClass
          : "border-border bg-background text-muted-foreground hover:bg-muted"
      )}
    >
      {children}
    </button>
  );
}