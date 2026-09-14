// ============================================
// /admin/dev/architecture/c4 — C4 模型架构图 (借鉴 sales-ai /admin/dev-architecture/c4)
//
// C4 4 层:
// 1. System Context (外部用户/系统)
// 2. Container (应用容器)
// 3. Component (主要组件)
// 4. Code (代码结构)
//
// 主人 v0.1.4 拍板 key_modules_ui + C 选项 (借鉴 sales-ai)
// per docs/UI_STYLE_GUIDE.md: 颜色走 token, icon h-4 w-4, shadcn 手写
// ============================================

import Link from "next/link";
import { MermaidRenderer } from "@/components/dev/mermaid-renderer";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Layers, Users, Server, Code2, Network } from "lucide-react";
import { DevPageHeader } from "@/components/dev/dev-page-header";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "C4 架构图 · 暖客宝开发工具",
  description: "System Context + Container + Component + Code 4 层",
};

// C4 第 1 层: System Context
const C4_SYSTEM_CONTEXT = `
flowchart LR
  subgraph EXTERNAL["外部用户 / 系统"]
    SALES["销售员<br/>(中年女性)<br/>移动端"]
    OWNER["主人<br/>(开发/监控)<br/>浏览器"]
    OFFSITE["异地盘<br/>(外置)<br/>3-2-1 备份"]
  end

  subgraph SYSTEM["暖客宝 NuankeBao (主人机器 tc)"]
    APK["移动端 APK<br/>Flutter app"]
    WEB["WEB 端<br/>Next.js 脚手架"]
    API["共享后端 API<br/>Drizzle + pgcrypto"]
  end

  SALES -->|"扫码装机"| APK
  OWNER -->|"浏览器访问"| WEB
  APK -->|"HTTPS API"| API
  WEB -->|"HTTPS API"| API
  API -->|"GPG AES256"| OFFSITE

  classDef personStyle fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
  classDef systemStyle fill:#dcfce7,stroke:#16a34a,color:#15803d
  classDef extStyle fill:#fef3c7,stroke:#d97706,color:#78350f
  class SALES,OWNER personStyle
  class APK,WEB,API systemStyle
  class OFFSITE extStyle
`;

// C4 第 2 层: Container
const C4_CONTAINER = `
flowchart TB
  subgraph TC["主人机器 (tc) — Ubuntu"]
    subgraph APK_CONTAINER["APK 域 (生产域 = 销售员 Flutter app)"]
      FLUTTER["Flutter 3.24+<br/>flutter_app/lib/{core,modules}"]
    end

    subgraph WEB_CONTAINER["WEB 域 (开发域 = 主人自用脚手架)"]
      NEXTJS["Next.js 15<br/>src/app/{api,admin,dev,app-preview}"]
    end

    subgraph SHARED["共享后端 (真理源)"]
      ROUTE["Route Handlers<br/>src/app/api/**/route.ts"]
      DB[("PostgreSQL 16<br/>Drizzle schema 13 表<br/>pgcrypto + 5 触发器")]
    end

    subgraph DEPLOY["部署 + 监控"]
      SYSTEMD["systemd units<br/>(nuankebao-* 6 个)"]
      BACKUP["deploy/*.sh<br/>(PG + Media + Snapshot)"]
      TUNNEL["cloudflared<br/>(nuankebao.tooyang.top)"]
    end
  end

  FLUTTER -. "HTTP API + Auth.js cookie" .-> ROUTE
  NEXTJS -. "HTTP API + Auth.js cookie" .-> ROUTE
  ROUTE -->|"Drizzle ORM"| DB
  SYSTEMD -->|"next start -p 3003"| NEXTJS
  BACKUP -->|"pg_dump + tar + GPG"| DB
  TUNNEL -->|"HTTP 3003"| NEXTJS

  classDef apkStyle fill:#dcfce7,stroke:#16a34a,color:#15803d
  classDef webStyle fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
  classDef sharedStyle fill:#fce7f3,stroke:#be185d,color:#831843
  classDef deployStyle fill:#f3e8ff,stroke:#7c3aed,color:#4c1d95
  class FLUTTER apkStyle
  class NEXTJS webStyle
  class ROUTE,DB sharedStyle
  class SYSTEMD,BACKUP,TUNNEL deployStyle
`;

// C4 第 3 层: Component (按域细分)
const C4_COMPONENT = `
flowchart TB
  subgraph SHARED_API["共享后端 API 组件 (src/app/api/)"]
    AUTH_API["/api/auth/*<br/>(手机号验证码)"]
    CUST_API["/api/customers/*"]
    WELL_API["/api/wellness-records/*"]
    REL_API["/api/relations/*"]
    AI_API["/api/ai/*"]
  end

  subgraph APK_COMP["APK 域 7 模块 (flutter_app/lib/modules/)"]
    AUTH_MOD["auth<br/>(登录)"]
    CUST_MOD["customer<br/>(客户档案)"]
    WELL_MOD["wellness<br/>(养生记录)"]
    REL_MOD["relation ★<br/>(客户/加盟关系)"]
    PRES_MOD["presentation<br/>(graph+list)"]
  end

  subgraph WEB_COMP["WEB 域 7 模块 (docs/admin/dev-modules/)"]
    TASK_MOD["task-snapshot"]
    REF_MOD["references"]
    UI_MOD["ui-kit"]
    SKILL_MOD["project-skill"]
    ARCH_MOD["architecture"]
  end

  subgraph CORE_SHARED["APK 域共享底座 (flutter_app/lib/core/)"]
    ROUTER_C["router (go_router)"]
    HTTP_C["http (dio + 拦截器)"]
    THEME_C["theme (Material 3)"]
    MODELS_C["models (freezed)"]
  end

  AUTH_MOD -->|"调 API"| AUTH_API
  CUST_MOD -->|"调 API"| CUST_API
  WELL_MOD -->|"调 API"| WELL_API
  REL_MOD -->|"调 API"| REL_API

  AUTH_MOD --> ROUTER_C
  CUST_MOD --> HTTP_C
  WELL_MOD --> THEME_C
  REL_MOD --> MODELS_C

  classDef modStyle fill:#dcfce7,stroke:#16a34a
  classDef apiStyle fill:#fce7f3,stroke:#be185d
  classDef coreStyle fill:#e0f2fe,stroke:#0284c7
  classDef devStyle fill:#fef3c7,stroke:#d97706
  class AUTH_MOD,CUST_MOD,WELL_MOD,REL_MOD,PRES_MOD modStyle
  class AUTH_API,CUST_API,WELL_API,REL_API,AI_API apiStyle
  class ROUTER_C,HTTP_C,THEME_C,MODELS_C coreStyle
  class TASK_MOD,REF_MOD,UI_MOD,SKILL_MOD,ARCH_MOD devStyle
`;

// C4 第 4 层: Code (物理目录)
const C4_CODE = `
flowchart LR
  subgraph ROOT["nuankebao-agent/"]
    direction TB
    FLUTTER_APP["flutter_app/<br/>lib/{core, modules}"]
    SRC["src/<br/>{app, components, lib}"]
    DEPLOY["deploy/<br/>{backup.sh, code_snapshot.sh, restore_verify.sh}"]
    TOOLS["tools/<br/>{check-port.sh, check-ui-style.sh, fix-nuankebao-deploy.sh}"]
    DOCS["docs/<br/>{CHARTER, AGENTS, ADR, dev-modules, UI_STYLE_GUIDE}"]
    SCRIPTS["scripts/<br/>task-snapshot.sh"]
  end

  FLUTTER_APP -->|"pnpm"| SRC
  FLUTTER_APP -->|"flutter build apk"| DEPLOY
  SRC -->|"Next.js build"| DEPLOY
  TOOLS -->|"operate"| DEPLOY
  SCRIPTS -->|"rollback"| TOOLS
  DOCS -->|"reference"| SRC
  DOCS -->|"reference"| FLUTTER_APP

  classDef codeStyle fill:#f3f4f6,stroke:#6b7280,color:#1f2937
  class FLUTTER_APP,SRC,DEPLOY,TOOLS,DOCS,SCRIPTS codeStyle
`;

const layers = [
  {
    level: 1,
    title: "System Context",
    subtitle: "外部用户 / 系统",
    description: "谁用? 谁依赖?",
    chart: C4_SYSTEM_CONTEXT,
    icon: Users,
  },
  {
    level: 2,
    title: "Container",
    subtitle: "应用容器",
    description: "跑什么? 容器如何通信?",
    chart: C4_CONTAINER,
    icon: Server,
  },
  {
    level: 3,
    title: "Component",
    subtitle: "主要组件",
    description: "每个容器内部的关键模块?",
    chart: C4_COMPONENT,
    icon: Layers,
  },
  {
    level: 4,
    title: "Code",
    subtitle: "代码结构",
    description: "物理文件 / 目录",
    chart: C4_CODE,
    icon: Code2,
  },
];

export default function C4ArchitecturePage() {
  return (
    <main className="mx-auto max-w-5xl">
      <DevPageHeader
        backHref="/admin/dev/architecture"
        backLabel="返回 /admin/dev/architecture"
        icon={Network}
        title="C4 架构图"
        description={
          <>
            C4 模型 4 层架构图 (System Context → Container → Component → Code). 借鉴自{" "}
            <a
              href="https://github.com/sales-ai/sales-ai/blob/main/web-next/src/app/(dashboard)/admin/dev-architecture/c4/page.tsx"
              className="text-primary hover:underline"
              target="_blank"
              rel="noreferrer"
            >
              sales-ai /admin/dev-architecture/c4
            </a>
            .
          </>
        }
        badges={[
          { label: "v0.1.4", variant: "outline" },
          { label: "★ 借鉴 sales-ai" },
          { label: "mermaid 渲染" },
        ]}
      />

      <section className="mb-6 p-4 bg-muted border border-primary/30 rounded-lg">
        <p className="text-sm text-foreground">
          <strong>关于 C4 模型</strong>:{" "}
          <a
            href="https://c4model.com/"
            className="text-primary hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            c4model.com
          </a>{" "}
          是 Simon Brown 提出的轻量级架构描述方法, 用 4 层递进 (Context → Container → Component → Code) 描述系统.
          本页 nuankebao 自有实现 (不是 sales-ai 复制).
        </p>
      </section>

      {layers.map((layer) => {
        const Icon = layer.icon;
        return (
          <section key={layer.level} className="mb-8">
            <Card>
              <CardHeader>
                <CardTitle className="text-base flex items-center gap-2">
                  <Icon className="h-5 w-5 text-primary" />
                  Level {layer.level}: {layer.title}{" "}
                  <span className="text-muted-foreground font-normal">
                    ({layer.subtitle})
                  </span>
                </CardTitle>
                <p className="text-sm text-muted-foreground mt-1">
                  {layer.description}
                </p>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto p-4 bg-muted rounded-lg">
                  <MermaidRenderer chart={layer.chart} />
                </div>
              </CardContent>
            </Card>
          </section>
        );
      })}

      <footer className="text-xs text-muted-foreground border-t pt-4">
        <p>
          ⚠️ 这是 mermaid 渲染版本. 文字版见{" "}
          <Link
            href="/admin/dev/architecture"
            className="text-primary hover:underline"
          >
            /admin/dev/architecture
          </Link>{" "}
          (CHARTER §4.1 总架构图).
        </p>
        <p className="mt-1">
          📋 待办: 自动从代码生成 C4 图 (per ARCHITECTURE_FINAL §8.4 架构图升级)
        </p>
      </footer>
    </main>
  );
}
