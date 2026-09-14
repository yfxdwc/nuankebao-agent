// ============================================
// /admin/dev/architecture — 渲染 CHARTER §4.1 ASCII 文字图为 mermaid SVG
//
// ★ v0.1.3 架构重点: 主人 2026-09-13 拍板 key_modules_ui
// 这里把当前 docs/CHARTER.md §4.1 ASCII 架构图渲染成可视化的 mermaid SVG.
//
// 未来: 升级为 docs/architecture/architecture.mmd 单文件 (per 待办 §8.4)
// 当前: 内联 mermaid 代码 (匹配 CHARTER §4.1)
// ============================================

import Link from "next/link";
import { MermaidRenderer } from "@/components/dev/mermaid-renderer";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ArrowLeft, Network } from "lucide-react";

export const metadata = {
  title: "架构图 · 暖客宝开发工具",
  description: "渲染 CHARTER §4.1 v0.1.3 架构图为 mermaid SVG",
};

// CHARTER §4.1 双域 + 底座 + 模块化插件 架构图 (mermaid 语法)
const ARCHITECTURE_DIAGRAM = `
flowchart TB
  subgraph APK["📱 APK 域 (主产品 — 销售员移动端)"]
    direction TB
    subgraph CORE["APK 底座 (flutter_app/lib/core/)<br/>不可替换"]
      CORE_R["router / providers"]
      CORE_H["http / theme"]
      CORE_M["models / widgets"]
    end
    subgraph MODS["业务模块 (flutter_app/lib/modules/)<br/>可独立替换/改进"]
      M_AUTH["auth<br/>登录"]
      M_CUST["customer<br/>客户档案"]
      M_WELL["wellness<br/>养生记录"]
      M_FU["follow_up<br/>跟进 (占位)"]
      M_PRES["presentation<br/>graph + list 合并"]
      M_REL["relation ★<br/>客户/加盟关系<br/>接口 + 默认实现"]
      M_MEET["meeting<br/>会议 (占位)"]
    end
  end

  subgraph WEB["🛠️ WEB 域 (开发项目 APK 的脚手架)"]
    direction TB
    subgraph WCORE["WEB 底座<br/>Next.js + shadcn + Tailwind"]
      WCORE_R["App Router"]
      WCORE_S["shadcn/ui + Tailwind"]
      WCORE_A["Drizzle API + Auth.js"]
    end
    subgraph WDEVS["开发域模块 (docs/admin/dev-modules/)<br/>文档化视图"]
      W_TASK["task-snapshot"]
      W_REFS["references"]
      W_UI["ui-kit"]
      W_PSK["project-skill"]
      W_ARCH["architecture"]
      W_PREV["flutter-preview"]
      W_DEPLOY["deploy"]
    end
    WDEVS_UI["/admin/dev/<br/>3 个 UI 入口<br/>(架构/部署/快照)"]
  end

  subgraph SHARED["共享基础设施 (后端 API + DB)"]
    SH_D["Drizzle schema<br/>13 表"]
    SH_A["Auth.js v5"]
    SH_C["pgcrypto 加密"]
    SH_L["audit 5 触发器"]
  end

  APK -.调用 API.-> SHARED
  WEB -.提供脚手架.-> APK
  APK -.依赖 Flutter web 预览.-> WEB

  classDef baseStyle fill:#e0f2e9,stroke:#2D5F3F,color:#1a3d27
  classDef moduleStyle fill:#fef3c7,stroke:#d97706,color:#78350f
  classDef devStyle fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
  classDef starStyle fill:#fce7f3,stroke:#be185d,color:#831843,stroke-width:3px
  classDef sharedStyle fill:#f3e8ff,stroke:#7c3aed,color:#4c1d95

  class CORE_R,CORE_H,CORE_M,WCORE_R,WCORE_S,WCORE_A baseStyle
  class M_AUTH,M_CUST,M_WELL,M_FU,M_PRES,M_MEET,W_TASK,W_REFS,W_UI,W_PSK,W_ARCH,W_PREV,W_DEPLOY moduleStyle
  class M_REL starStyle
  class SH_D,SH_A,SH_C,SH_L sharedStyle
`;

// Phase 8 文档化视图说明
const documentationPages = [
  {
    href: "/docs/admin/dev-modules/README.md",
    title: "WEB 域 7 模块 README 索引",
    desc: "总入口 + 模块清单 + 维护 SOP",
  },
  {
    href: "/docs/adr/0007-modular-architecture.md",
    title: "ADR-0007 完整决策记录",
    desc: "底座 + 模块化插件架构 (510 行)",
  },
  {
    href: "/docs/architecture/v0.1.3-final.md",
    title: "v0.1.3 架构重构最终总结",
    desc: "一站式 review 文档 (12 节, 367 行)",
  },
  {
    href: "/docs/CHARTER.md#41-总体架构图-apk-域--web-域",
    title: "CHARTER.md §4.1 文字版架构图",
    desc: "v0.1.3 元宪法 (权威源)",
  },
];

export default function ArchitecturePage() {
  return (
    <main className="mx-auto max-w-6xl px-4 py-8 sm:py-12">
      <div className="mb-6">
        <Button variant="ghost" size="sm" asChild className="mb-3">
          <Link href="/admin/dev">
            <ArrowLeft className="size-4 mr-1" />
            返回 /admin/dev
          </Link>
        </Button>

        <div className="flex items-center gap-2 mb-2">
          <Network className="size-7 text-purple-700" />
          <h1 className="text-3xl font-bold text-foreground">
            架构图 (Architecture)
          </h1>
        </div>
        <p className="text-muted-foreground">
          渲染{" "}
          <a
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/CHARTER.md#41-总体架构图-apk-域--web-域"
            className="text-blue-600 hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            CHARTER.md §4.1
          </a>{" "}
          v0.1.3 架构图为可视化的 mermaid SVG.
        </p>
        <div className="mt-3 flex gap-2 flex-wrap">
          <Badge variant="outline">v0.1.3</Badge>
          <Badge variant="secondary">★ 双域 + 底座 + 模块化插件</Badge>
        </div>
      </div>

      <section className="mb-10 p-6 bg-white border rounded-lg shadow-sm overflow-x-auto">
        <h2 className="text-lg font-semibold text-foreground mb-4">
          总架构图 (CHARTER §4.1 mermaid 渲染)
        </h2>
        <MermaidRenderer chart={ARCHITECTURE_DIAGRAM} />
      </section>

      <section className="mb-10">
        <h2 className="text-lg font-semibold text-foreground mb-4">
          关联文档 (4 个)
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {documentationPages.map((d) => (
            <a
              key={d.href}
              href={`https://github.com/tooyan/nuankebao-agent/blob/main/${d.href}`}
              target="_blank"
              rel="noreferrer"
              className="block p-4 bg-white border rounded-lg hover:shadow-md hover:border-border transition-all"
            >
              <h3 className="text-sm font-semibold text-foreground">
                {d.title}
              </h3>
              <p className="text-xs text-muted-foreground mt-1 font-mono">{d.href}</p>
              <p className="text-xs text-muted-foreground mt-2">{d.desc}</p>
            </a>
          ))}
        </div>
      </section>

      <section className="text-xs text-muted-foreground border-t pt-4">
        <p>
          ⚠️ 这是 mermaid 渲染版本. 文字版 (ASCII) 见{" "}
          <a
            href="https://github.com/tooyan/nuankebao-agent/blob/main/docs/CHARTER.md"
            className="text-blue-600 hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            CHARTER.md
          </a>
          .
        </p>
        <p className="mt-1">
          📋 待办 (per ARCHITECTURE_FINAL §8.4): 升级为{" "}
          <code>docs/architecture/architecture.mmd</code> 单文件 + 数据流图 (客户录入 / 养生 / 加盟查询).
        </p>
      </section>
    </main>
  );
}
