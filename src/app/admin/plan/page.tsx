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
    <div className="mx-auto max-w-5xl space-y-8 md:space-y-10">
      {/* ========== 1. Header (页面标题 + 总进度) ========== */}
      <header className="space-y-3">
        <div className="flex items-baseline justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-xl md:text-2xl font-semibold text-foreground">
              开发计划
            </h1>
            <p className="text-sm text-muted-foreground mt-1">
              主人自用的项目计划 · {data.meta.phase} · 当前{" "}
              <span className="font-mono">{data.meta.version}</span>
            </p>
          </div>
          {/* 总进度 (用 div 模拟进度条, 不依赖 shadcn Progress 组件) */}
          <div className="text-right">
            <div className="text-xs text-muted-foreground">路线图进度</div>
            <div className="text-2xl font-semibold tabular-nums text-primary">
              {overallPct}%
            </div>
          </div>
        </div>

        {/* 进度条 (原则 5: 状态色只在有状态时出现 — 用 success 色做"已完成"语义) */}
        <div className="h-1.5 w-full rounded-full bg-muted overflow-hidden">
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
        <div className="text-xs text-muted-foreground">
          {totalDone} / {totalTasks} 路线图任务已完成 ·{" "}
          <span className="font-mono">
            {data.meta.fetchedAt.slice(0, 16).replace("T", " ")}
          </span>{" "}
          刷新
        </div>
      </header>

      {/* ========== Warnings (解析失败的提示块) ========== */}
      {data.meta.warnings.length > 0 && (
        <div className="rounded-md border border-warning/40 bg-warning-surface p-3 text-sm">
          <div className="font-medium text-warning-foreground mb-1">
            ⚠ 路线图数据源读取失败:
          </div>
          <ul className="list-disc pl-5 text-muted-foreground">
            {data.meta.warnings.map((w, i) => (
              <li key={i}>{w}</li>
            ))}
          </ul>
        </div>
      )}

      {/* ========== 2. 待开发想法 (主人日常用, client CRUD) ========== */}
      <section>
        <h2 className="text-lg font-semibold text-foreground mb-3">
          待开发想法
        </h2>
        <p className="text-xs text-muted-foreground mb-4">
          主人手动记录的待办 / 备忘 — 顶部一行新增, 状态三选 (待办/完成/丢弃), 真删需二次确认。
        </p>
        <IdeaList />
      </section>

      {/* ========== 3. 周里程碑 (Phase 1 大盘, 只读) ========== */}
      <section>
        <h2 className="text-lg font-semibold text-foreground mb-3">
          路线图 · Phase 1 MVP (6 周)
        </h2>
        <p className="text-xs text-muted-foreground mb-4">
          数据来源:{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/phase-1-mvp.md"
            className="text-info hover:underline font-mono"
            target="_blank"
            rel="noreferrer"
          >
            docs/phase-1-mvp.md
          </Link>{" "}
          · 主人每周拍板, 任务勾选 = CHANGELOG 反映
        </p>

        {/* ★ 列表页不套 Card (原则 4), 用 1px 分隔线分组 */}
        <ul className="divide-y divide-border border-y border-border">
          {data.weeks.length === 0 ? (
            <li className="py-4 text-sm text-muted-foreground">
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
                      <span className="font-mono text-sm font-semibold text-primary shrink-0">
                        {w.code}
                      </span>
                      <h3 className="text-base font-medium text-foreground truncate">
                        {w.title}
                      </h3>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <span className="text-xs tabular-nums text-muted-foreground">
                        {w.done}/{w.total}
                      </span>
                      <Badge
                        variant={pct === 100 ? "default" : "outline"}
                        className="text-xs tabular-nums"
                      >
                        {pct}%
                      </Badge>
                    </div>
                  </div>

                  {/* 行内进度条 (迷你版, h-1) */}
                  <div className="h-1 w-full rounded-full bg-muted overflow-hidden">
                    <div
                      className={
                        pct === 100
                          ? "h-full bg-success"
                          : pct > 0
                          ? "h-full bg-primary"
                          : "h-full bg-transparent"
                      }
                      style={{ width: `${pct}%` }}
                    />
                  </div>

                  {/* 任务列表 (默认折叠前 3 条, 多了有溢出感)
                      这里简化为全展开, 因为任务数都不大 (<20) */}
                  {w.tasks.length > 0 && (
                    <details className="text-sm">
                      <summary className="cursor-pointer text-xs text-muted-foreground hover:text-foreground select-none">
                        {w.tasks.length} 个任务
                      </summary>
                      <ul className="mt-2 space-y-1 pl-1">
                        {w.tasks.map((t, i) => (
                          <li
                            key={i}
                            className="flex items-start gap-2 text-sm"
                          >
                            <span
                              className={
                                t.done
                                  ? "text-success shrink-0"
                                  : "text-muted-foreground shrink-0"
                              }
                              aria-hidden="true"
                            >
                              {t.done ? "✓" : "○"}
                            </span>
                            <span
                              className={
                                t.done
                                  ? "text-muted-foreground line-through"
                                  : "text-foreground"
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
      </section>

      {/* ========== 4. 最近变更 (CHANGELOG 头部) ========== */}
      <section>
        <h2 className="text-lg font-semibold text-foreground mb-3">最近变更</h2>
        <p className="text-xs text-muted-foreground mb-4">
          数据来源:{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/CHANGELOG.md"
            className="text-info hover:underline font-mono"
            target="_blank"
            rel="noreferrer"
          >
            CHANGELOG.md
          </Link>{" "}
          · 仅展示最近 8 条
        </p>

        {/* ★ 同样不套 Card, 用分隔线 */}
        <ul className="divide-y divide-border border-y border-border">
          {data.changes.length === 0 ? (
            <li className="py-4 text-sm text-muted-foreground">
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
                      : "mt-1.5 h-2 w-2 rounded-full bg-muted-foreground shrink-0"
                  }
                  aria-hidden="true"
                />
                <div className="flex-1 min-w-0">
                  <div className="flex items-baseline justify-between gap-2 flex-wrap">
                    <p className="text-sm text-foreground">{c.title}</p>
                    <span className="text-xs text-muted-foreground tabular-nums shrink-0">
                      {c.date ?? "—"}
                    </span>
                  </div>
                  {/* Tag: unreleased = 黄牌 "进行中", versioned = 灰底 "vX.Y.Z" */}
                  {c.kind === "unreleased" ? (
                    <Badge
                      variant="outline"
                      className="mt-1 text-xs border-warning/50 text-warning-foreground"
                    >
                      Unreleased · 待发版
                    </Badge>
                  ) : (
                    <span className="mt-1 inline-block text-xs font-mono text-muted-foreground">
                      {c.tag}
                    </span>
                  )}
                </div>
              </li>
            ))
          )}
        </ul>
      </section>

      {/* ========== 5. 最近 ADR (决策时间线) ========== */}
      <section>
        <h2 className="text-lg font-semibold text-foreground mb-3">
          最近 ADR 决策
        </h2>
        <p className="text-xs text-muted-foreground mb-4">
          数据来源:{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/adr/INDEX.md"
            className="text-info hover:underline font-mono"
            target="_blank"
            rel="noreferrer"
          >
            docs/adr/INDEX.md
          </Link>{" "}
          · 仅展示最近 10 条 · 跳 GitHub 阅读完整内容
        </p>

        <ul className="divide-y divide-border border-y border-border">
          {data.adrs.length === 0 ? (
            <li className="py-4 text-sm text-muted-foreground">
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
                  {/* ADR id (等宽, 偏深色, 像 commit short-sha 视觉) */}
                  <span className="font-mono text-xs font-semibold text-primary shrink-0 mt-0.5">
                    {a.id}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-foreground group-hover:text-primary transition-colors">
                      {a.title}
                    </p>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="text-xs text-muted-foreground">
                        {a.status}
                      </span>
                      <span className="text-xs text-muted-foreground">·</span>
                      <span className="text-xs text-muted-foreground tabular-nums">
                        {a.date}
                      </span>
                    </div>
                  </div>
                </Link>
              </li>
            ))
          )}
        </ul>
      </section>

      {/* ========== 6. Footer (数据来源说明 + 渲染时间) ========== */}
      <footer className="text-xs text-muted-foreground border-t pt-4 space-y-1">
        <p>
          完整路线图见{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/phase-1-mvp.md"
            className="text-info hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            docs/phase-1-mvp.md
          </Link>{" "}
          +{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/CHANGELOG.md"
            className="text-info hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            CHANGELOG.md
          </Link>{" "}
          +{" "}
          <Link
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/adr/INDEX.md"
            className="text-info hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            docs/adr/INDEX.md
          </Link>
        </p>
        <p className="font-mono">
          数据刷新于 {data.meta.fetchedAt.replace("T", " ").slice(0, 19)} UTC
        </p>
      </footer>
    </div>
  );
}