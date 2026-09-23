// ============================================
// /admin/dev 总览 tab — 开发工具门户首页
//
// v0.1.4 主人 2026-09-14 拍板 (master-decide, AGENTS §3 master-override):
// 开发工具子模块以"顶部 tab 导航 + 内容区"方式呈现, 替代原入口卡片.
// 当前页 = "总览" tab 内容 (其他 tab 在 components/dev/dev-tabs-nav.tsx).
//
// Tab 清单 (详见 components/dev/dev-tabs-nav.tsx):
// - 总览 (本页, /admin/dev)        — 模块卡片列表 + CLI 模块
// - 架构 (/admin/dev/architecture) — 架构图
// - 部署 (/admin/dev/deploy)       — 部署 + 备份状态
// - 快照 (/admin/dev/snapshot)     — 任务快照
//
// 顶部 tab 由 /admin/dev/layout.tsx 注入, 当前页只渲染内容区.
// ============================================

import Link from "next/link";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Network,
  Database,
  History,
  ArrowUpRight,
  Terminal,
  BookOpen,
  Package,
  ServerCog,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "开发工具 · 总览 · 暖客宝",
  description: "主人自用的开发工具门户 (总览 · 架构 · 部署 · 快照)",
};

// 3 个有 WEB UI 的子模块 — 顶部 tab 直接链到这些
const implementedModules = [
  {
    href: "/admin/dev/architecture",
    icon: Network,
    title: "架构图",
    description: "渲染 docs/CHARTER.md §4 文字版架构图为 mermaid SVG",
    color: "bg-graph-b-surface text-graph-b",
    badge: "★ v0.1.3",
  },
  {
    href: "/admin/dev/deploy",
    icon: Database,
    title: "部署 + 备份",
    description: "读取 data/backup-health/*.json 显示备份健康状态 + 最近日志",
    color: "bg-success-surface text-success",
    badge: null,
  },
  {
    href: "/admin/dev/snapshot",
    icon: History,
    title: "任务快照",
    description: "列出 git tag pre-* 历史 + diff 预览 + rollback 按钮",
    color: "bg-warning-surface text-warning",
    badge: "⚠ 危险操作",
  },
];

// 4 个仍走 CLI / 文件级的模块 (per v0.1.3 拍板)
const cliOnlyModules = [
  {
    icon: Terminal,
    title: "task-snapshot (CLI)",
    description: "bash scripts/task-snapshot.sh <start|list|find|diff|rollback>",
  },
  {
    icon: BookOpen,
    title: "references",
    description: "docs/references.md + 外部项目监控 SOP",
  },
  {
    icon: Package,
    title: "ui-kit",
    description: "src/components/ui/ shadcn 组件 (无独立页, 被其他页用)",
  },
  {
    icon: ServerCog,
    title: "project-skill",
    description: "AGENTS.md + .pi/settings.json + ~/.muse/skills/",
  },
];

export default function DevOverviewPage() {
  return (
    <div className="mx-auto max-w-5xl space-y-6 md:space-y-10">
      <section>
        <h2 className="text-base md:text-lg font-semibold text-foreground mb-3 md:mb-4">
          ✨ 子模块 (3 个 · 顶部 tab 进入)
        </h2>
        <div className="grid gap-3 md:gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
          {implementedModules.map((m) => {
            const Icon = m.icon;
            return (
              <Link key={m.href} href={m.href} className="group">
                <Card variant="outlined" className="h-full transition-colors hover:border-primary/50 hover:bg-surface-subtle">
                  <CardHeader>
                    <div className="flex items-center justify-between mb-1">
                      <div
                        className={`inline-flex p-2 rounded-lg ${m.color}`}
                      >
                        <Icon className="size-5" />
                      </div>
                      {m.badge && (
                        <Badge variant="outline" className="text-xs">
                          {m.badge}
                        </Badge>
                      )}
                    </div>
                    <CardTitle className="text-base flex items-center gap-1">
                      {m.title}
                      <ArrowUpRight className="size-4 text-muted-foreground transition-colors" />
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="text-sm text-muted-foreground">{m.description}</p>
                  </CardContent>
                </Card>
              </Link>
            );
          })}
        </div>
      </section>

      <section>
        <h2 className="text-base md:text-lg font-semibold text-foreground mb-3 md:mb-4">
          📂 CLI / 文件级 模块 (4 个)
        </h2>
        <p className="text-sm text-muted-foreground mb-3">
          主人 2026-09-13 拍板 key_modules_ui, 只给 3 个关键模块加 UI. 以下 4 个仍走 CLI / 文件级 / 自动触发.
        </p>
        <div className="grid gap-3 grid-cols-1 sm:grid-cols-2">
          {cliOnlyModules.map((m) => {
            const Icon = m.icon;
            return (
              <Card key={m.title} className="bg-muted/50">
                <CardContent className="pt-4 flex items-start gap-3">
                  <div className="inline-flex p-2 rounded-lg bg-muted text-muted-foreground shrink-0">
                    <Icon className="size-4" />
                  </div>
                  <div>
                    <h3 className="text-sm font-semibold text-foreground">
                      {m.title}
                    </h3>
                    <p className="text-xs text-muted-foreground mt-1 font-mono break-all">
                      {m.description}
                    </p>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      </section>

      <footer className="text-xs text-muted-foreground border-t pt-4">
        <p>
          完整架构说明见{" "}
          <Link
            href="/admin/dev/architecture"
            className="text-info hover:underline"
          >
            /admin/dev/architecture
          </Link>{" "}
          和{" "}
          <a
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/architecture/v0.1.3-final.md"
            className="text-info hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            docs/architecture/v0.1.3-final.md
          </a>
          .
        </p>
      </footer>
    </div>
  );
}