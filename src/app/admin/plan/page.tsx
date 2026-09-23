// ============================================
// /admin/plan — 主人自用的项目计划中心
//
// v0.1.5 主人 2026-09-23 拍 (ask_user d3e7f2a1, 两轮):
//   第一轮: 「admin 端增加开发计划模块」— 静态路线图渲染 (W1-W6 + CHANGELOG + ADR)
//   第二轮: 「我需要能手动记录一个待开发的想法」— 增删改 / 勾选 / 丢弃
//
// (c) 升级方案 (主人拍板): 主页 = **待开发想法 CRUD** + 下方保留路线图 section
//   - 顶部 IdeaList (client component) = 主人日常用 (新增/勾选/丢弃)
//   - 下方路线图 (server-rendered)   = 大盘 (Phase 1 整体进度, 只读)
//
// 设计原则 (docs/ui-principles.md §1-§5):
//   - 密度: 列表紧凑, 一屏可见 (原则 1)
//   - 层级: 字重 + 颜色差, 字号 ≤ 5 档 (原则 2)
//   - 留白: 组内 8 / 组间 20 (原则 3)
//   - 容器: 列表不套 Card, 用 1px 分隔线 (原则 4) ★
//   - 颜色: 状态色只在有状态时出现 (原则 5)
//
// 不要做的 (per AGENTS §5 反模式):
//   - ❌ 卡片套卡片
//   - ❌ 给列表加卡片容器
//   - ❌ 一屏十种颜色
// ============================================

import Link from "next/link";
import { loadPlanData } from "./plan-loader";
import { Badge } from "@/components/ui/badge";
import { Section } from "@/components/ui/section";
import { PageHeader } from "@/components/ui/page-header";
import { IdeaList } from "@/components/admin/idea-list";

// SSR 强制 — 跟 /admin/dev 系列保持一致
export const dynamic = "force-dynamic";

export const metadata = {
  title: "开发计划 · 暖客宝 admin",
  description:
    "主人自用的项目计划: 待开发想法 CRUD + Phase 1 MVP 周里程碑 + 最近变更 + 最近 ADR 决策",
};

export default async function PlanPage() {
  const data = await loadPlanData();

  // 整页进度 = 所有周任务 done / total
  const totalDone = data.weeks.reduce((s, w) => s + w.done, 0);
  const totalTasks = data.weeks.reduce((s, w) => s + w.total, 0);
  const overallPct = totalTasks > 0 ? Math.round((totalDone / totalTasks) * 100) : 0;

  return (
    <div className="mx-auto max-w-5xl space-y-section-y">
      {/* ========== 1. Header (PageHeader + 总进度) ========== */}
      <PageHeader
        title="开发计划"
        description={`主人自用的项目计划 · ${data.meta.phase} · 当前 ${data.meta.version}`}
        actions={
          <div className="text-right">
            <div className="text-caption text-content-tertiary">路线图进度</div>
            <div className="text-title-sm font-semibold tabular-nums text-brand">
              {overallPct}%
            </div>
          </div>
        }
      >
        {/* 进度条 (原则 5: 状态色只在有状态时出现) */}
        <div className="h-1.5 w-full rounded-full bg-surface-sunken overflow-hidden">
          <div
            className="h-full bg-success transition-all"
            style={{ width: `${overallPct}%` }}
            role="progressbar"
            aria-valuenow={overallPct}
            aria-valuemin={0}
            aria-valuemax={100}
            aria-label="Phase 1 MVP 路线图总进度"
          />
        </div>
        <div className="text-caption text-content-tertiary tabular-nums">
          {totalDone} / {totalTasks} 路线图任务已完成 ·{" "}
          <span className="font-mono">
            {data.meta.fetchedAt.slice(0, 16).replace("T", " ")}
          </span>{" "}
          刷新
        </div>
      </PageHeader>

      {/* ========== Warnings (解析失败的提示块) ========== */}
      {data.meta.warnings.length > 0 && (
        <div className="rounded-md border border-warning/40 bg-warning-surface p-3 text-body">
          <div className="font-medium text-warning mb-1">
            ⚠ 路线图数据源读取失败:
          </div>
          <ul className="list-disc pl-5 text-content-secondary">
            {data.meta.warnings.map((w, i) => (
              <li key={i}>{w}</li>
            ))}
          </ul>
        </div>
      )}

      {/* ========== 2. 待开发想法 (主人日常用, client CRUD) ========== */}
      <Section
        title="待开发想法"
        description="主人手动记录的待办 / 备忘 — 顶部一行新增, 状态三选 (待办/完成/丢弃), 真删需二次确认。"
      >
        <IdeaList />
      </Section>

      {/* ========== 3. 周里程碑 (Phase 1 大盘, 只读) ========== */}
      <Section
        title="路线图 · Phase 1 MVP (6 周)"
        description={
          <>
            数据来源:{" "}
            <Link
              href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/phase-1-mvp.md"
              className="text-brand hover:underline font-mono"
              target="_blank"
              rel="noreferrer"
            >
              docs/phase-1-mvp.md
            </Link>{" "}
            · 主人每周拍板, 任务勾选 = CHANGELOG 反映
          </>
        }
      >
        {/* ★ 列表页不套 Card (原则 4), 用 1px 分隔线分组 */}
        <ul className="divide-y divide-divider">
          {data.weeks.length === 0 ? (
            <li className="py-4 text-body text-content-secondary">
              暂无周计划数据
            </li>
          ) : (
            data.weeks.map((w) => {
              const pct = w.total > 0 ? Math.round((w.done / w.total) * 100) : 0;
              return (
                <li key={w.code} className="py-4 space-y-2">
                  {/* 行头: code (等宽) + 标题 + 完成度 (右对齐数字) */}
                  <div className="flex items-baseline justify-between gap-3 flex-wrap">
                    <div className="flex items-baseline gap-3 min-w-0">
                      <span className="font-mono text-body font-semibold text-brand shrink-0">
                        {w.code}
                      </span>
                      <h3 className="text-body-lg font-medium text-content-primary truncate">
                        {w.title}
                      </h3>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <span className="text-caption tabular-nums text-content-tertiary">
                        {w.done}/{w.total}
                      </span>
                      <Badge
                        variant={pct === 100 ? "default" : "outline"}
                        className="text-caption tabular-nums"
                      >
                        {pct}%
                      </Badge>
                    </div>
                  </div>

                  {/* 行内进度条 (迷你版, h-1) */}
                  <div className="h-1 w-full rounded-full bg-surface-sunken overflow-hidden">
                    <div
                      className={
                        pct === 100
                          ? "h-full bg-success"
                          : pct > 0
                          ? "h-full bg-brand"
                          : "h-full bg-transparent"
                      }
                      style={{ width: `${pct}%` }}
                    />
                  </div>

                  {/* 任务列表 */}
                  {w.tasks.length > 0 && (
                    <details className="text-body">
                      <summary className="cursor-pointer text-caption text-content-tertiary hover:text-content-primary select-none">
                        {w.tasks.length} 个任务
                      </summary>
                      <ul className="mt-2 space-y-1 pl-1">
                        {w.tasks.map((t, i) => (
                          <li
                            key={i}
                            className="flex items-start gap-2 text-body"
                          >
                            <span
                              className={
                                t.done
                                  ? "text-success shrink-0"
                                  : "text-content-tertiary shrink-0"
                              }
                              aria-hidden="true"
                            >
                              {t.done ? "✓" : "○"}
                            </span>
                            <span
                              className={
                                t.done
                                  ? "text-content-secondary line-through"
                                  : "text-content-primary"
                              }
                            >
                              {t.text}
                            </span>
                          </li>
                        ))}
                      </ul>
                    </details>
                  )}
                </li>
              );
            })
          )}
        </ul>
      </Section>

      {/* ========== 4. 最近变更 (CHANGELOG 头部) ========== */}
      <Section
        title="最近变更"
        description={
          <>
            数据来源:{" "}
            <Link
              href="https://github.com/tooyan/nuankebao-agent/blob/main/CHANGELOG.md"
              className="text-brand hover:underline font-mono"
              target="_blank"
              rel="noreferrer"
            >
              CHANGELOG.md
            </Link>{" "}
            · 仅展示最近 8 条
          </>
        }
      >
        <ul className="divide-y divide-divider">
          {data.changes.length === 0 ? (
            <li className="py-4 text-body text-content-secondary">
              暂无变更数据
            </li>
          ) : (
            data.changes.map((c, i) => (
              <li key={i} className="py-3 flex items-start gap-3">
                {/* 状态点 (颜色只在有状态时出现 — 原则 5) */}
                <span
                  className={
                    c.kind === "unreleased"
                      ? "mt-1.5 h-2 w-2 rounded-full bg-warning shrink-0"
                      : "mt-1.5 h-2 w-2 rounded-full bg-content-tertiary shrink-0"
                  }
                  aria-hidden="true"
                />
                <div className="flex-1 min-w-0">
                  <div className="flex items-baseline justify-between gap-2 flex-wrap">
                    <p className="text-body-lg text-content-primary">{c.title}</p>
                    <span className="text-caption text-content-tertiary tabular-nums shrink-0">
                      {c.date ?? "—"}
                    </span>
                  </div>
                  {c.kind === "unreleased" ? (
                    <Badge
                      variant="outline"
                      className="mt-1 text-caption border-warning/50 text-warning"
                    >
                      Unreleased · 待发版
                    </Badge>
                  ) : (
                    <span className="mt-1 inline-block text-caption font-mono text-content-tertiary">
                      {c.tag}
                    </span>
                  )}
                </div>
              </li>
            ))
          )}
        </ul>
      </Section>

      {/* ========== 5. 最近 ADR (决策时间线) ========== */}
      <Section
        title="最近 ADR 决策"
        description={
          <>
            数据来源:{" "}
            <Link
              href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/adr/INDEX.md"
              className="text-brand hover:underline font-mono"
              target="_blank"
              rel="noreferrer"
            >
              docs/adr/INDEX.md
            </Link>{" "}
            · 仅展示最近 10 条 · 跳 GitHub 阅读完整内容
          </>
        }
      >
        <ul className="divide-y divide-divider">
          {data.adrs.length === 0 ? (
            <li className="py-4 text-body text-content-secondary">
              暂无 ADR 数据
            </li>
          ) : (
            data.adrs.map((a) => (
              <li key={a.id} className="py-3">
                <Link
                  href={a.githubPath}
                  target="_blank"
                  rel="noreferrer"
                  className="group flex items-start gap-3"
                >
                  <span className="font-mono text-caption font-semibold text-brand shrink-0 mt-0.5">
                    {a.id}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className="text-body-lg text-content-primary group-hover:text-brand transition-colors">
                      {a.title}
                    </p>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="text-caption text-content-secondary">
                        {a.status}
                      </span>
                      <span className="text-caption text-content-tertiary">·</span>
                      <span className="text-caption text-content-tertiary tabular-nums">
                        {a.date}
                      </span>
                    </div>
                  </div>
                </Link>
              </li>
            ))
          )}
        </ul>
      </Section>

      {/* ========== 6. Footer (数据来源说明 + 渲染时间) ========== */}
      <footer className="text-caption text-content-secondary border-t border-divider pt-section-y space-y-1">
        <p>
          完整路线图见{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/phase-1-mvp.md"
            className="text-brand hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            docs/phase-1-mvp.md
          </Link>{" "}
          +{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/CHANGELOG.md"
            className="text-brand hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            CHANGELOG.md
          </Link>{" "}
          +{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/adr/INDEX.md"
            className="text-brand hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            docs/adr/INDEX.md
          </Link>
        </p>
        <p className="font-mono tabular-nums">
          数据刷新于 {data.meta.fetchedAt.replace("T", " ").slice(0, 19)} UTC
        </p>
      </footer>
    </div>
  );
}