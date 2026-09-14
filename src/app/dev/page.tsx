// ============================================
// /dev 总入口 — 开发工具门户 (WEB 域脚手架 UI)
//
// v0.1.3 主人 ask_user 拍板 key_modules_ui (2026-09-13):
// 3 个关键 UI: architecture / deploy / task-snapshot.
//
// 位置: src/app/dev/ (与 src/app/admin/ 区分)
// - admin/ = 销售员产品 (CHARTER §4.4 v0.1.2 冻结, 仅 P0 fix)
// - dev/   = 主人开发工具 UI (无冻结, 因不冲突产品 admin)
//
// 关联: docs/architecture/v0.1.3-final.md §5.2 WEB 域模块清单
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
  Eye,
  ServerCog,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "开发工具 · 暖客宝",
  description: "主人自用的开发工具门户 (architecture / deploy / task-snapshot)",
};

// 3 个有 UI 的模块
const implementedModules = [
  {
    href: "/dev/architecture",
    icon: Network,
    title: "架构图 (Architecture)",
    description: "渲染 docs/CHARTER.md §4 文字版架构图为 mermaid SVG",
    color: "bg-purple-50 text-purple-700",
    badge: "★ v0.1.3",
  },
  {
    href: "/dev/deploy",
    icon: Database,
    title: "部署 + 备份 (Deploy)",
    description: "读取 data/backup-health/*.json 显示备份健康状态 + 最近日志",
    color: "bg-green-50 text-green-700",
    badge: null,
  },
  {
    href: "/dev/snapshot",
    icon: History,
    title: "任务快照 (Task Snapshot)",
    description: "列出 git tag pre-* 历史 + diff 预览 + rollback 按钮",
    color: "bg-amber-50 text-amber-700",
    badge: "⚠ 危险操作",
  },
];

// 4 个仍走 CLI / 文件级的模块 (per v0.1.3 拍板)
const cliOnlyModules = [
  {
    icon: Terminal,
    title: "task-snapshot (CLI)",
    description: "bash scripts/task-snapshot.sh <start|list|find|diff|rollback>",
    color: "bg-muted text-muted-foreground",
  },
  {
    icon: BookOpen,
    title: "references",
    description: "docs/references.md + 外部项目监控 SOP",
    color: "bg-muted text-muted-foreground",
  },
  {
    icon: Package,
    title: "ui-kit",
    description: "src/components/ui/ shadcn 组件 (无独立页, 被其他页用)",
    color: "bg-muted text-muted-foreground",
  },
  {
    icon: ServerCog,
    title: "project-skill",
    description: "AGENTS.md + .pi/settings.json + ~/.muse/skills/",
    color: "bg-muted text-muted-foreground",
  },
];

export default function DevHomePage() {
  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-8">
        <div className="flex items-center gap-2 mb-2">
          <Eye className="size-7 text-muted-foreground" />
          <h1 className="text-3xl font-bold text-foreground">开发工具门户</h1>
        </div>
        <p className="text-muted-foreground">
          暖客宝 WEB 域 (脚手架) 的可视化入口. 仅主人/agent 使用, 不给销售员.
        </p>
        <div className="mt-3 flex gap-2 flex-wrap">
          <Badge variant="outline">v0.1.3 架构重构 (2026-09-13)</Badge>
          <Badge variant="secondary">CHARTER §4 双域</Badge>
          <Badge variant="secondary">AGENTS §4.5 模块化</Badge>
        </div>
      </header>

      <section className="mb-10">
        <h2 className="text-lg font-semibold text-foreground mb-4">
          ✨ 有 WEB UI 的模块 (3 个)
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {implementedModules.map((m) => {
            const Icon = m.icon;
            return (
              <Link key={m.href} href={m.href} className="group">
                <Card className="h-full transition-all hover:shadow-md hover:border-border">
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
                      <ArrowUpRight className="size-4 text-muted-foreground group-hover:text-muted-foreground transition-colors" />
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

      <section className="mb-10">
        <h2 className="text-lg font-semibold text-foreground mb-4">
          📂 CLI / 文件级 模块 (4 个)
        </h2>
        <p className="text-sm text-muted-foreground mb-4">
          主人 2026-09-13 拍板 key_modules_ui, 只给 3 个关键模块加 UI. 以下 4 个仍走 CLI / 文件级 / 自动触发.
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          {cliOnlyModules.map((m) => {
            const Icon = m.icon;
            return (
              <Card key={m.title} className="bg-muted/50">
                <CardContent className="pt-4 flex items-start gap-3">
                  <div className={`inline-flex p-2 rounded-lg ${m.color} shrink-0`}>
                    <Icon className="size-4" />
                  </div>
                  <div>
                    <h3 className="text-sm font-semibold text-foreground">
                      {m.title}
                    </h3>
                    <p className="text-xs text-muted-foreground mt-1 font-mono">
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
            href="/dev/architecture"
            className="text-blue-600 hover:underline"
          >
            /dev/architecture
          </Link>{" "}
          和{" "}
          <a
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/architecture/v0.1.3-final.md"
            className="text-blue-600 hover:underline"
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
