"use client";

// ============================================
// 客户管理参数调节器 (web admin, 主人 2026-09-23 拍)
//
// 主人原话: 「在 admin 里增加管理、调节页面, 让评分规则及其他客户管理中的参数
//   可在管理页面进行调节」
//
// 数据源:
//   GET    /api/admin/insight-config          → 生效值 + 默认值 + 覆盖原文
//   PUT    /api/admin/insight-config          → 保存 (夹区间 + 版本 +1 + 审计)
//   DELETE /api/admin/insight-config          → 重置为默认 (删覆盖行)
//   POST   /api/admin/insight-config/impact   → 保存前预览: 抽样算一遍会动多少客户
//
// B3 重构 (2026-09-23): Card (有 bg-card) → Section (无 bg-card, 仅 gap-section-y 拉开; 反 vibe)
// ============================================

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  RotateCcw,
  Save,
  Users,
} from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/section";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import type { InsightConfig } from "@/lib/customer/insight-config";
import {
  INSIGHT_PARAM_GROUPS,
  INSIGHT_PARAM_META,
  flattenConfig,
  paramsOfGroup,
  writeParam,
} from "@/lib/customer/insight-param-meta";

interface ConfigView {
  config: InsightConfig;
  defaults: InsightConfig;
  override: unknown | null;
  isCustomized: boolean;
  updatedBy: string | null;
  updatedAt: string | null;
  versionBumped?: boolean;
}

interface Impact {
  sampled: number;
  sampledAll: boolean;
  sampleSize: number;
  changedScores: number;
  changedActions: number;
  examples: Array<{
    customerId: string;
    scoreBefore: number | null;
    scoreAfter: number | null;
    actionCountBefore: number;
    actionCountAfter: number;
  }>;
}

type Flat = Record<string, unknown>;
type Msg = { kind: "ok" | "err"; text: string } | null;

const PRIORITY_LABEL: Record<string, string> = {
  high: "高",
  medium: "中",
  low: "低",
};

export function InsightConfigEditor() {
  const [view, setView] = useState<ConfigView | null>(null);
  /** 扁平草稿: path → 值 (只放被改过的? 不: 放全部, 保存时整体覆盖) */
  const [draft, setDraft] = useState<Flat>({});
  const [bands, setBands] = useState<InsightConfig["scoring"]["bands"]>([]);
  const [open, setOpen] = useState<Set<string>>(new Set(["actions"]));
  const [impact, setImpact] = useState<Impact | null>(null);
  const [busy, setBusy] = useState<null | "load" | "save" | "reset" | "impact">(
    "load"
  );
  const [msg, setMsg] = useState<Msg>(null);

  const applyView = useCallback((v: ConfigView) => {
    setView(v);
    setDraft(flattenConfig(v.config));
    setBands(v.config.scoring.bands.map((b) => ({ ...b })));
    setImpact(null);
  }, []);

  const load = useCallback(async () => {
    setBusy("load");
    try {
      const res = await fetch("/api/admin/insight-config", { cache: "no-store" });
      if (!res.ok) throw new Error(await readErr(res));
      applyView(await res.json());
      setMsg(null);
    } catch (e) {
      setMsg({ kind: "err", text: `读取失败: ${e}` });
    } finally {
      setBusy(null);
    }
  }, [applyView]);

  useEffect(() => {
    void load();
  }, [load]);

  const defaults = useMemo(
    () => (view ? flattenConfig(view.defaults) : {}),
    [view]
  );

  /** 被改过的参数 path (与默认值不同) */
  const changedPaths = useMemo(() => {
    const out = new Set<string>();
    for (const p of INSIGHT_PARAM_META) {
      if (!isSame(draft[p.path], defaults[p.path])) out.add(p.path);
    }
    if (view && !bandsEqual(bands, view.defaults.scoring.bands)) out.add("scoring.bands");
    return out;
  }, [draft, defaults, bands, view]);

  const draftObject = useMemo(() => {
    const base = Object.entries(draft).reduce<Record<string, unknown>>(
      (acc, [path, value]) => writeParam(acc, path, value),
      {}
    );
    return writeParam(base, "scoring.bands", bands);
  }, [draft, bands]);

  const onSave = async () => {
    setBusy("save");
    setMsg(null);
    try {
      const res = await fetch("/api/admin/insight-config", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(draftObject),
      });
      if (!res.ok) throw new Error(await readErr(res));
      const v: ConfigView = await res.json();
      applyView(v);
      setMsg({
        kind: "ok",
        text: v.versionBumped
          ? "已保存。参数版本已 +1，客户详情页会提示「评分规则已更新, 分数可能变化」。"
          : "已保存 (参数内容与原来一致，版本号未变)。",
      });
    } catch (e) {
      setMsg({ kind: "err", text: `保存失败: ${e}` });
    } finally {
      setBusy(null);
    }
  };

  const onReset = async () => {
    if (!confirm("确定重置为默认值？所有自定义参数会被清空（可以重新调，但这次改动会记入审计日志）。")) return;
    setBusy("reset");
    setMsg(null);
    try {
      const res = await fetch("/api/admin/insight-config", { method: "DELETE" });
      if (!res.ok) throw new Error(await readErr(res));
      applyView(await res.json());
      setMsg({ kind: "ok", text: "已重置为默认值。" });
    } catch (e) {
      setMsg({ kind: "err", text: `重置失败: ${e}` });
    } finally {
      setBusy(null);
    }
  };

  const onImpact = async () => {
    setBusy("impact");
    setMsg(null);
    try {
      const res = await fetch("/api/admin/insight-config/impact", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(draftObject),
      });
      if (!res.ok) throw new Error(await readErr(res));
      setImpact(await res.json());
    } catch (e) {
      setMsg({ kind: "err", text: `预估失败: ${e}` });
    } finally {
      setBusy(null);
    }
  };

  const toggle = (id: string) =>
    setOpen((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  if (!view && busy === "load") {
    return <div className="py-10 text-center text-content-secondary">加载中…</div>;
  }

  return (
    <div className="space-y-section-y max-w-4xl">
      {/* 头部 + 操作区 */}
      <Section
        title={
          <span className="flex flex-wrap items-center gap-2">
            客户管理参数
            {view?.isCustomized ? (
              <Badge variant="secondary" className="text-caption">已自定义</Badge>
            ) : (
              <Badge variant="outline" className="text-caption">使用系统默认</Badge>
            )}
            {view?.config.scoring.version && (
              <span className="text-caption font-normal text-content-tertiary tabular-nums">
                参数版本 {view.config.scoring.version} / {view.config.actions.version}
              </span>
            )}
          </span>
        }
        description="这里的参数决定「客户评分怎么算」和「什么时候提醒销售做什么」。改动会影响全店所有客户（参数不按门店区分），每次保存都会记入审计日志。"
      >
        {view?.updatedAt && (
          <p className="text-caption text-content-tertiary tabular-nums">
            最后修改：{new Date(view.updatedAt).toLocaleString("zh-CN")}
            {view.updatedBy ? `（用户 #${view.updatedBy}）` : ""}
          </p>
        )}

        <div className="space-y-3 pt-section-y border-t border-divider">
          {msg && (
            <div
              className={cn(
                "flex items-start gap-2 rounded-md p-3 text-body",
                msg.kind === "ok"
                  ? "bg-success-light text-success-foreground"
                  : "bg-danger-surface text-danger"
              )}
            >
              {msg.kind === "ok" ? (
                <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
              ) : (
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              )}
              <span>{msg.text}</span>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-2">
            <Button onClick={onImpact} disabled={busy !== null} variant="outline">
              <Users className="mr-1.5 h-4 w-4" />
              {busy === "impact" ? "预估中…" : "预估影响面"}
            </Button>
            <Button onClick={onSave} disabled={busy !== null}>
              <Save className="mr-1.5 h-4 w-4" />
              {busy === "save" ? "保存中…" : "保存"}
            </Button>
            <Button
              onClick={onReset}
              disabled={busy !== null || !view?.isCustomized}
              variant="ghost"
            >
              <RotateCcw className="mr-1.5 h-4 w-4" />
              重置为默认
            </Button>
            {changedPaths.size > 0 && (
              <span className="text-body-lg text-warning">
                已改动 {changedPaths.size} 项（未保存）
              </span>
            )}
          </div>

          {impact && <ImpactPanel impact={impact} />}
        </div>
      </Section>

      {/* 分档 (数组, 单独渲染) */}
      {view && (
        <Section
          title="分数分档"
          description="必须有一个档的下限是 0（否则低分客户没有档可落，系统会自动补一个「需关注」）。"
        >
          <ul className="divide-y divide-divider">
            {bands.map((b, i) => (
              <li key={b.band} className="py-2.5 flex items-center gap-2 flex-wrap">
                <span className="w-24 text-body text-content-secondary shrink-0">{b.band}</span>
                <span className="text-body text-content-tertiary shrink-0">≥</span>
                <Input
                  type="number"
                  className="w-24 min-h-control"
                  min={0}
                  max={100}
                  value={String(b.min)}
                  onChange={(e) =>
                    setBands((prev) =>
                      prev.map((x, j) =>
                        j === i ? { ...x, min: Number(e.target.value) } : x
                      )
                    )
                  }
                />
                <Input
                  className="w-40 min-h-control"
                  value={b.label}
                  maxLength={16}
                  onChange={(e) =>
                    setBands((prev) =>
                      prev.map((x, j) =>
                        j === i ? { ...x, label: e.target.value } : x
                      )
                    )
                  }
                />
                {!isSame(b.min, view.defaults.scoring.bands[i]?.min) && (
                  <Badge variant="secondary" className="text-caption">
                    已改（默认 {view.defaults.scoring.bands[i]?.min}）
                  </Badge>
                )}
              </li>
            ))}
          </ul>
        </Section>
      )}

      {/* 6 组可调参数 (Section + 可折叠) */}
      {INSIGHT_PARAM_GROUPS.map((g) => {
        const items = paramsOfGroup(g.id);
        const groupChanged = items.filter((p) => changedPaths.has(p.path)).length;
        const isOpen = open.has(g.id);
        return (
          <Section
            key={g.id}
            title={
              <span className="flex items-center gap-2">
                {isOpen ? (
                  <ChevronDown className="h-4 w-4 shrink-0" />
                ) : (
                  <ChevronRight className="h-4 w-4 shrink-0" />
                )}
                <span>{g.title}</span>
                <span className="text-caption text-content-tertiary tabular-nums">
                  {items.length} 项
                </span>
                {groupChanged > 0 && (
                  <Badge variant="secondary" className="text-caption">
                    改 {groupChanged} 项
                  </Badge>
                )}
              </span>
            }
            description={g.desc}
            action={
              <Button
                size="sm"
                variant="ghost"
                onClick={() => toggle(g.id)}
                className="text-caption"
              >
                {isOpen ? "收起" : "展开"}
              </Button>
            }
          >
            {isOpen && (
              <div className="divide-y divide-divider">
                {items.map((p) => (
                  <ParamRow
                    key={p.path}
                    meta={p}
                    value={draft[p.path]}
                    defaultValue={defaults[p.path]}
                    changed={changedPaths.has(p.path)}
                    onChange={(v) =>
                      setDraft((prev) => writeParam(prev, p.path, v))
                    }
                    onRevert={() =>
                      setDraft((prev) => writeParam(prev, p.path, defaults[p.path]))
                    }
                  />
                ))}
              </div>
            )}
          </Section>
        );
      })}
    </div>
  );
}

function ParamRow({
  meta,
  value,
  defaultValue,
  changed,
  onChange,
  onRevert,
}: {
  meta: (typeof INSIGHT_PARAM_META)[number];
  value: unknown;
  defaultValue: unknown;
  changed: boolean;
  onChange: (v: unknown) => void;
  onRevert: () => void;
}) {
  return (
    <div
      className={cn(
        "flex flex-wrap items-center gap-3 py-3",
        changed && "bg-warning-surface/40 -mx-2 px-2 rounded"
      )}
    >
      <div className="min-w-64 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-body-lg font-medium text-content-primary">
            {meta.label}
          </span>
          {meta.unit && (
            <span className="text-caption text-content-tertiary">（{meta.unit}）</span>
          )}
        </div>
        {meta.hint && (
          <p className="mt-0.5 text-caption text-content-secondary">{meta.hint}</p>
        )}
        <p className="mt-0.5 text-caption text-content-tertiary tabular-nums">
          默认 {String(defaultValue)}
          {meta.type === "number" && ` ｜ 可填 ${meta.min} ~ ${meta.max}`}
        </p>
      </div>

      {meta.type === "number" ? (
        <Input
          type="number"
          className="w-28 min-h-control"
          min={meta.min}
          max={meta.max}
          step={meta.step}
          value={value === undefined || value === null ? "" : String(value)}
          onChange={(e) => {
            const raw = e.target.value;
            onChange(raw === "" ? defaultValue : Number(raw));
          }}
        />
      ) : (
        <Select
          className="w-28 min-h-control"
          value={String(value ?? "medium")}
          onChange={(e) => onChange(e.target.value)}
        >
          {["high", "medium", "low"].map((k) => (
            <option key={k} value={k}>
              {PRIORITY_LABEL[k]}
            </option>
          ))}
        </Select>
      )}

      {changed && (
        <Button size="sm" variant="ghost" onClick={onRevert}>
          还原
        </Button>
      )}
    </div>
  );
}

function ImpactPanel({ impact }: { impact: Impact }) {
  const nothing =
    impact.changedScores === 0 && impact.changedActions === 0;
  return (
    <div className="rounded-md border border-divider bg-surface-subtle p-3 text-body-lg">
      <div className="mb-1 font-medium">影响面预估</div>
      {nothing ? (
        <p className="text-content-secondary">
          抽样 {impact.sampled} 位客户，<strong>没有一位客户的分数或行动会变</strong>
          。（说明这次改的参数对现有数据没实际影响，或改的是当前用不到的项）
        </p>
      ) : (
        <p>
          抽样 <strong>{impact.sampled}</strong> 位客户中：
          <strong className="text-warning"> {impact.changedScores} 位分数会变</strong>
          、
          <strong className="text-warning">
            {" "}
            {impact.changedActions} 位的「该做的事」会变
          </strong>
          。
        </p>
      )}
      <p className="mt-1 text-caption text-content-secondary">
        ⚠ 这是<strong>抽样估算</strong>（最多 {impact.sampleSize} 位
        {impact.sampledAll ? "，本页已覆盖全部客户" : "，按最近更新排序取前若干"}），
        不是全量重算。
      </p>
      {impact.examples.length > 0 && (
        <ul className="mt-2 space-y-0.5 text-caption text-content-secondary tabular-nums">
          {impact.examples.map((e) => (
            <li key={e.customerId}>
              客户 #{e.customerId}：分数 {e.scoreBefore ?? "—"} →{" "}
              {e.scoreAfter ?? "—"}；行动 {e.actionCountBefore} 条 →{" "}
              {e.actionCountAfter} 条
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function isSame(a: unknown, b: unknown): boolean {
  if (typeof a === "number" && typeof b === "number") return Math.abs(a - b) < 1e-9;
  return a === b;
}

function bandsEqual(
  a: InsightConfig["scoring"]["bands"],
  b: InsightConfig["scoring"]["bands"]
): boolean {
  if (a.length !== b.length) return false;
  return a.every((x, i) => x.band === b[i].band && isSame(x.min, b[i].min) && x.label === b[i].label);
}

async function readErr(res: Response): Promise<string> {
  try {
    const j = await res.json();
    return j?.error ?? `HTTP ${res.status}`;
  } catch {
    return `HTTP ${res.status}`;
  }
}