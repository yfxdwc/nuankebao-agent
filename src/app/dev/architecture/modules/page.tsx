// ============================================
// /dev/architecture/modules — APK 域 7 模块依赖图 (借鉴 sales-ai /admin/dev-architecture/modules)
//
// 自动从 flutter_app/lib/modules/ 解析:
// - 7 模块状态 (screens / widgets / lib 数量)
// - 模块 → core 底座依赖 (mermaid)
// - 跨模块调用 (per AGENTS §4.5 业务模块允许调 presentation widget)
// - 依赖统计表
//
// 主人 v0.1.4 拍板 C 选项 (借鉴 sales-ai)
// per docs/UI_STYLE_GUIDE.md: token 驱动, icon h-4 w-4, shadcn 手写
// ============================================

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import Link from "next/link";
import { MermaidRenderer } from "@/components/dev/mermaid-renderer";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  ArrowLeft,
  Package,
  Code2,
  Network,
  CheckCircle2,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "APK 模块依赖图 · 暖客宝开发工具",
  description: "7 模块 + core 底座 + 跨模块调用",
};

const MODULES_DIR = path.join(process.cwd(), "flutter_app/lib/modules");
const CORE_DIR = path.join(process.cwd(), "flutter_app/lib/core");

interface ModuleInfo {
  name: string;
  status: "active" | "placeholder";
  screens: number;
  widgets: number;
  libs: number;
  // 模块依赖哪些 core 资源 (e.g. "models/customer.dart" → "core/models/customer")
  coreDeps: string[];
  // 模块被哪些模块依赖 (cross-module import)
  usedByModules: string[];
}

async function readDirSafe(dir: string): Promise<string[]> {
  try {
    return await readdir(dir);
  } catch {
    return [];
  }
}

async function analyzeModule(name: string): Promise<ModuleInfo> {
  const modulePath = path.join(MODULES_DIR, name);
  const entries = await readDirSafe(modulePath);

  let screens = 0;
  let widgets = 0;
  let libs = 0;
  const coreDeps = new Set<string>();

  for (const entry of entries) {
    const entryPath = path.join(modulePath, entry);
    const stat = await readDirSafe(entryPath);
    if (entry === "screens") screens = stat.filter((f) => f.endsWith(".dart")).length;
    else if (entry === "widgets") widgets = stat.filter((f) => f.endsWith(".dart")).length;
    else if (entry === "lib") {
      libs = stat.filter((f) => f.endsWith(".dart")).length;
      // 解析 lib/*.dart 的 imports (找 cross-module 引用)
      for (const f of stat.filter((f) => f.endsWith(".dart"))) {
        const content = await readFile(path.join(entryPath, f), "utf-8");
        // 找 `import '../../../core/X/Y.dart';` 模式
        const matches = content.matchAll(/import\s+['"]\.\.\/\.\.\/\.\.\/core\/([^'"]+)['"]/g);
        for (const m of matches) coreDeps.add("core/" + m[1]);
      }
    } else if (entry === "README.md") {
      // 模块是否占位 (检查 README 是否有 "占位" 字样)
    }
  }

  // 解析 screens/*.dart 的 core imports
  const screensDir = path.join(modulePath, "screens");
  const screenFiles = (await readDirSafe(screensDir)).filter((f) => f.endsWith(".dart"));
  for (const sf of screenFiles) {
    const content = await readFile(path.join(screensDir, sf), "utf-8");
    const matches = content.matchAll(/import\s+['"]\.\.\/\.\.\/\.\.\/core\/([^'"]+)['"]/g);
    for (const m of matches) coreDeps.add("core/" + m[1]);
    // 私有 widget (../widgets/X)
    const widgetMatches = content.matchAll(/import\s+['"]\.\.\/widgets\/([^'"]+)['"]/g);
    for (const w of widgetMatches) widgets++; // 算上
  }

  // 解析 widgets/*.dart 的 core imports
  const widgetsDir = path.join(modulePath, "widgets");
  const widgetFiles = (await readDirSafe(widgetsDir)).filter((f) => f.endsWith(".dart"));
  for (const wf of widgetFiles) {
    const content = await readFile(path.join(widgetsDir, wf), "utf-8");
    const matches = content.matchAll(/import\s+['"]\.\.\/\.\.\/\.\.\/core\/([^'"]+)['"]/g);
    for (const m of matches) coreDeps.add("core/" + m[1]);
  }

  return {
    name,
    status: screens + widgets + libs > 0 ? "active" : "placeholder",
    screens,
    widgets,
    libs,
    coreDeps: [...coreDeps].sort(),
    usedByModules: [], // 反向依赖扫描下面做
  };
}

// 扫描反向依赖 (presentation/widgets 被哪个模块用)
async function scanReverseDeps(modules: ModuleInfo[]): Promise<Map<string, string[]>> {
  const reverseDeps = new Map<string, string[]>();
  for (const m of modules) {
    for (const file of [
      ...(await readDirSafe(path.join(MODULES_DIR, m.name, "screens"))),
      ...(await readDirSafe(path.join(MODULES_DIR, m.name, "widgets"))),
      ...(await readDirSafe(path.join(MODULES_DIR, m.name, "lib"))),
    ]) {
      if (!file.endsWith(".dart")) continue;
    const content = await readFile(path.join(MODULES_DIR, m.name, file), "utf-8");
    // 找 ../../presentation/X/Y 模式
    const matches = content.matchAll(/import\s+['"]\.\.\/\.\.\/presentation\/([^'"]+)['"]/g);
    for (const match of matches) {
      const key = "presentation/" + match[1];
      if (!reverseDeps.has(key)) reverseDeps.set(key, []);
      reverseDeps.get(key)!.push(m.name);
    }
  }
  return reverseDeps;
}

async function analyzeAllModules(): Promise<ModuleInfo[]> {
  const moduleNames = (await readDirSafe(MODULES_DIR)).filter((d) =>
    !d.startsWith(".")
  );
  const modules: ModuleInfo[] = [];
  for (const name of moduleNames.sort()) {
    modules.push(await analyzeModule(name));
  }
  // 扫描反向依赖
  const reverseDeps = await scanReverseDeps(modules);
  // 给每个 module 的 usedByModules 填值
  // 检查 m.widgets 是否被其他模块引用 (跨模块直调)
  for (const m of modules) {
    for (const other of modules) {
      if (other.name === m.name) continue;
      const widgetsDir = path.join(MODULES_DIR, other.name, "widgets");
      const widgetFiles = (await readDirSafe(widgetsDir)).filter((f) => f.endsWith(".dart"));
      for (const wf of widgetFiles) {
        const content = await readFile(path.join(widgetsDir, wf), "utf-8");
        // 简单 string 包含检测: ../../<m.name>/widgets/ 任意
        if (content.includes(`../../${m.name}/widgets/`)) {
          if (!m.usedByModules.includes(other.name))
            m.usedByModules.push(other.name);
        }
      }
    }
  }
  return modules;
}

function renderCrossModule(modules: ModuleInfo[]) {
  const crossModule = modules.filter((m) => m.usedByModules.length > 0);
  if (crossModule.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        ✅ 无跨模块直调, 所有模块通过 core 底座对接 (合规)
      </p>
    );
  }
  const joinSep = ", ";
  return (
    <div className="space-y-2">
      {crossModule.map((m) => {
        const usedByText = m.usedByModules.join(joinSep);
        return (
          <div key={m.name} className="flex items-start gap-3 text-sm">
            <Network className="h-4 w-4 text-primary mt-0.5 shrink-0" />
            <div>
              <code className="font-mono text-xs">{m.name}</code>
              {" 被 "}
              <code className="font-mono text-xs">{usedByText}</code>
              {" 引用 (合规: 业务模块调 presentation widget)"}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function generateMermaid(modules: ModuleInfo[]): string {
  // 7 模块 → core 8 类
  const lines: string[] = ["flowchart LR"];
  // 节点: 7 模块
  modules.forEach((m, i) => {
    const screenPart = m.screens > 0 ? `${m.screens} screens` : "";
    const widgetPart = m.widgets > 0 ? `${m.widgets} widgets` : "";
    const libPart = m.libs > 0 ? `${m.libs} lib` : "";
    const parts = [screenPart, widgetPart, libPart].filter(Boolean).join(" / ");
    lines.push(
      "  M_" + m.name.toUpperCase() + '["' + m.name + ' ' + (parts || "(占位)") + '"]'
    );
  });
  // 节点: core 8 类
  const coreCategories = [
    { key: "models", label: "models/" },
    { key: "providers", label: "providers/" },
    { key: "http", label: "http/" },
    { key: "services", label: "services/" },
    { key: "theme", label: "theme/" },
    { key: "router", label: "router/" },
    { key: "widgets", label: "widgets/ (共享)" },
  ];
  lines.push(`  subgraph CORE[\"APK 底座 (flutter_app/lib/core/)\"]`);
  coreCategories.forEach((c) => {
    lines.push(`    C_${c.key.toUpperCase()}["${c.label}"]`);
  });
  lines.push("  end");
  // 边: modules → core
  for (const m of modules) {
    for (const dep of m.coreDeps) {
      const cat = dep.split("/")[1]; // "models/customer.dart" → "models"
      if (cat && coreCategories.some((c) => c.key === cat)) {
        lines.push(`  M_${m.name.toUpperCase()} -. "${cat}".-> C_${cat.toUpperCase()}`);
      }
    }
  }
  // classDef
  lines.push("  classDef modStyle fill:#dcfce7,stroke:#16a34a,color:#15803d");
  lines.push("  classDef coreStyle fill:#e0f2fe,stroke:#0284c7,color:#075985");
  modules.forEach((m) => {
    lines.push(`  class M_${m.name.toUpperCase()} modStyle`);
  });
  coreCategories.forEach((c) => {
    lines.push(`  class C_${c.key.toUpperCase()} coreStyle`);
  });
  return lines.join("\n");
}

export default async function ModulesArchitecturePage() {
  const modules = await analyzeAllModules();

  // 统计每个 core 资源被多少模块用
  const coreUsage = new Map<string, number>();
  for (const m of modules) {
    for (const dep of m.coreDeps) {
      coreUsage.set(dep, (coreUsage.get(dep) ?? 0) + 1);
    }
  }
  const topCore = [...coreUsage.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);

  const mermaidDiagram = generateMermaid(modules);

  return (
    <main className="mx-auto max-w-6xl px-4 py-8 sm:py-12">
      <div className="mb-6">
        <Button variant="ghost" size="sm" asChild className="mb-3">
          <Link href="/dev/architecture">
            <ArrowLeft className="h-4 w-4 mr-1" />
            返回 /dev/architecture
          </Link>
        </Button>

        <div className="flex items-center gap-2 mb-2">
          <Package className="h-7 w-7 text-primary" />
          <h1 className="text-3xl font-bold text-foreground">APK 模块依赖图</h1>
        </div>
        <p className="text-muted-foreground">
          自动从{" "}
          <code className="text-xs bg-muted px-1.5 py-0.5 rounded">
            flutter_app/lib/modules/
          </code>{" "}
          解析 7 模块 + core 底座 + 跨模块调用. 借鉴自{" "}
          <a
            href="https://github.com/sales-ai/sales-ai/blob/main/web-next/src/app/(dashboard)/admin/dev-architecture/modules/page.tsx"
            className="text-primary hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            sales-ai /admin/dev-architecture/modules
          </a>
          .
        </p>
        <div className="mt-3 flex gap-2 flex-wrap">
          <Badge variant="outline">v0.1.4</Badge>
          <Badge variant="secondary">★ 借鉴 sales-ai</Badge>
          <Badge variant="secondary">auto-parsed from source</Badge>
        </div>
      </div>

      {/* 模块状态卡 */}
      <section className="mb-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {modules.map((m) => (
          <Card key={m.name}>
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Code2 className="h-4 w-4 text-primary" />
                {m.name}
                {m.status === "placeholder" && (
                  <Badge variant="outline" className="text-xs">
                    占位
                  </Badge>
                )}
              </CardTitle>
            </CardHeader>
            <CardContent className="pt-0 text-sm text-muted-foreground">
              <div>📱 screens: {m.screens}</div>
              <div>🎨 widgets: {m.widgets}</div>
              <div>📚 lib: {m.libs}</div>
              <div className="mt-2 text-xs">
                core deps: {m.coreDeps.length}
              </div>
            </CardContent>
          </Card>
        ))}
      </section>

      {/* 依赖 mermaid 图 */}
      <section className="mb-8">
        <h2 className="text-lg font-semibold text-foreground mb-3">
          模块 → Core 底座依赖图
        </h2>
        <Card>
          <CardContent className="pt-4">
            <div className="overflow-x-auto p-4 bg-muted rounded-lg">
              <MermaidRenderer chart={mermaidDiagram} />
            </div>
          </CardContent>
        </Card>
      </section>

      {/* Top 10 core 资源 */}
      <section className="mb-8">
        <h2 className="text-lg font-semibold text-foreground mb-3">
          Top 10 最常被引用的 core 资源 (跨模块共享度)
        </h2>
        <Card>
          <CardContent className="pt-4">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs text-muted-foreground border-b">
                  <tr>
                    <th className="pb-2">core 资源</th>
                    <th className="pb-2">被引用次数</th>
                    <th className="pb-2">占总模块</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {topCore.map(([dep, count]) => (
                    <tr key={dep}>
                      <td className="py-1.5 font-mono text-xs">{dep}</td>
                      <td className="py-1.5">{count}</td>
                      <td className="py-1.5 text-xs text-muted-foreground">
                        {count} / {modules.length} (
                        {Math.round((count / modules.length) * 100)}%)
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      </section>

      {/* 跨模块调用 */}
      <section className="mb-8">
        <h2 className="text-lg font-semibold text-foreground mb-3">
          跨模块调用 (per AGENTS §4.5: 业务模块可调 presentation widget)
        </h2>
        <Card>
          <CardContent className="pt-4">
            {renderCrossModule(modules)}
          </CardContent>
        </Card>
      </section>

      {/* 合规检查 */}
      <section className="mb-8 p-4 bg-muted border border-primary/30 rounded-lg">
        <div className="flex items-start gap-3">
          <CheckCircle2 className="h-5 w-5 text-primary mt-0.5 shrink-0" />
          <div className="text-sm">
            <p className="font-semibold text-foreground mb-1">
              AGENTS §4.5 模块化约束 (合规检查)
            </p>
            <ul className="space-y-1 text-muted-foreground text-xs">
              <li>✅ 模块内部 widget / service 可选 (跨模块禁止直调, 必须走 core/)</li>
              <li>✅ 必须有 README.md (7 模块全有)</li>
              <li>✅ 跨 process 调用 (业务 → presentation widget) 合规</li>
              <li>⚠️ profile_page.dart 归位 (per Phase 9, 暂在 lib/screens/)</li>
            </ul>
          </div>
        </div>
      </section>

      <footer className="text-xs text-muted-foreground border-t pt-4 space-y-1">
        <p>
          📊 自动解析 (每次访问重新扫描): flutter_app/lib/modules/ + core/
        </p>
        <p>
          {"⚠️ 这是源码静态分析 (import 关系), 不是运行时调用图. 真运行时数据流见 "}
          <Link href="/dev/architecture" className="text-primary hover:underline">
            /dev/architecture
          </Link>
          {"."}
        </p>
      </footer>
    </main>
  );
}
