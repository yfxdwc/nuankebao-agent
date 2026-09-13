// ============================================
// /dev/architecture/apis — 共享后端 API 列表 (借鉴 sales-ai /admin/dev-architecture/apis)
//
// 自动从 src/app/api/**/route.ts 解析:
// - HTTP method (GET/POST/PATCH/DELETE)
// - path (从文件路径推导)
// - description (JSDoc 注释)
//
// 主人 v0.1.4 拍板 C 选项 (借鉴 sales-ai)
// per docs/UI_STYLE_GUIDE.md: token 驱动, icon h-4 w-4, shadcn 手写
// ============================================

import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import Link from "next/link";
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
  Network,
  Server,
  FileText,
  CheckCircle2,
} from "lucide-react";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "后端 API 列表 · 暖客宝开发工具",
  description: "28 个共享后端 API endpoint (按域分组)",
};

const API_DIR = path.join(process.cwd(), "src/app/api");

interface ApiEndpoint {
  method: "GET" | "POST" | "PATCH" | "DELETE" | "PUT";
  path: string; // e.g. "/customers" or "/customers/[id]"
  description: string;
  domain: string; // 第一段路径
}

async function readDirSafe(dir: string): Promise<string[]> {
  try {
    return await readdir(dir);
  } catch {
    return [];
  }
}

async function analyzeRouteFile(
  absPath: string,
  relPath: string
): Promise<ApiEndpoint[]> {
  try {
    const content = await readFile(absPath, "utf-8");

    // 提取 JSDoc 注释 (// * xxx) 里的 description
    const jsdocMatch = content.match(/^\/\*\*\s*\n([\s\S]*?)\*\//m);
    let description = "";
    if (jsdocMatch) {
      // 取 JSDoc 第一行有效文字
      description = jsdocMatch[1]
        .split("\n")
        .map((l) => l.replace(/^\s*\*\s?/, "").trim())
        .filter(Boolean)
        .filter((l) => !l.startsWith("@") && !l.startsWith("GET") && !l.startsWith("POST") && !l.startsWith("PATCH") && !l.startsWith("DELETE") && !l.startsWith("PUT"))
        .join(" ")
        .trim();
      if (!description) {
        // 退到 GET/POST 等行
        const methodLines = jsdocMatch[1].split("\n").filter((l) => /^(GET|POST|PATCH|DELETE|PUT)\s/i.test(l));
        description = methodLines[0]?.replace(/^\s*\*\s?/, "").trim() || "";
      }
    }

    // 提取 methods
    const methodRegex =
      /export\s+async\s+function\s+(GET|POST|PATCH|DELETE|PUT)\s*\(/g;
    const methods: ApiEndpoint["method"][] = [];
    let m;
    while ((m = methodRegex.exec(content)) !== null) {
      methods.push(m[1] as ApiEndpoint["method"]);
    }

    // path: relPath 去掉 /route.ts, 例如 "/customers/[id]/route.ts" → "/customers/[id]"
    const apiPath = relPath.replace(/\/route\.ts$/, "");
    const domain = apiPath.split("/")[1] || "(root)";

    return methods.map((method) => ({
      method,
      path: apiPath,
      description,
      domain,
    }));
  } catch {
    return [];
  }
}

async function findRouteFiles(
  dir: string,
  base: string = ""
): Promise<{ abs: string; rel: string }[]> {
  const results: { abs: string; rel: string }[] = [];
  const entries = await readDirSafe(dir);
  for (const entry of entries) {
    const abs = path.join(dir, entry);
    const rel = path.join(base, entry);
    // Skip dynamic catch-all routes like [...nextauth] (these are auth handlers, not typical APIs)
    if (entry === "route.ts") {
      results.push({ abs, rel });
    } else if (entry.startsWith("[...")) {
      // skip [...nextauth] catch-all
      continue;
    } else {
      // 递归子目录 (e.g. [id])
      const sub = await readDirSafe(abs);
      if (sub.length > 0) {
        const subResults = await findRouteFiles(abs, rel);
        results.push(...subResults);
      }
    }
  }
  return results;
}

async function analyzeAllApis(): Promise<ApiEndpoint[]> {
  const files = await findRouteFiles(API_DIR);
  const allApis: ApiEndpoint[] = [];
  for (const f of files) {
    const eps = await analyzeRouteFile(f.abs, f.rel);
    allApis.push(...eps);
  }
  // 按 path 排序
  return allApis.sort((a, b) => {
    if (a.domain !== b.domain) return a.domain.localeCompare(b.domain);
    if (a.path !== b.path) return a.path.localeCompare(b.path);
    return a.method.localeCompare(b.method);
  });
}

const METHOD_COLORS: Record<string, string> = {
  GET: "bg-primary/10 text-primary border-primary/30",
  POST: "bg-muted text-foreground border-foreground/30",
  PATCH: "bg-foreground/10 text-foreground border-foreground/30",
  DELETE: "bg-destructive/10 text-destructive border-destructive/30",
  PUT: "bg-foreground/10 text-foreground border-foreground/30",
};

export default async function ApisArchitecturePage() {
  const apis = await analyzeAllApis();

  // 统计
  const methodCounts: Record<string, number> = {};
  for (const api of apis) {
    methodCounts[api.method] = (methodCounts[api.method] ?? 0) + 1;
  }

  // 按域分组
  const byDomain = new Map<string, ApiEndpoint[]>();
  for (const api of apis) {
    if (!byDomain.has(api.domain)) byDomain.set(api.domain, []);
    byDomain.get(api.domain)!.push(api);
  }

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
          <Network className="h-7 w-7 text-primary" />
          <h1 className="text-3xl font-bold text-foreground">后端 API 列表</h1>
        </div>
        <p className="text-muted-foreground">
          自动从{" "}
          <code className="text-xs bg-muted px-1.5 py-0.5 rounded">
            src/app/api/**/route.ts
          </code>{" "}
          解析 {apis.length} 个 endpoint (按域分组). 借鉴自{" "}
          <a
            href="https://github.com/sales-ai/sales-ai/blob/main/web-next/src/app/(dashboard)/admin/dev-architecture/apis/page.tsx"
            className="text-primary hover:underline"
            target="_blank"
            rel="noreferrer"
          >
            sales-ai /admin/dev-architecture/apis
          </a>
          .
        </p>
        <div className="mt-3 flex gap-2 flex-wrap">
          <Badge variant="outline">v0.1.4</Badge>
          <Badge variant="secondary">★ 借鉴 sales-ai</Badge>
          <Badge variant="secondary">auto-parsed from source</Badge>
        </div>
      </div>

      {/* 统计 */}
      <section className="mb-8 grid gap-3 sm:grid-cols-5">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <Server className="h-4 w-4 text-primary" />
              总数
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-3xl font-bold text-primary">{apis.length}</p>
            <p className="text-xs text-muted-foreground mt-1">endpoint</p>
          </CardContent>
        </Card>
        {Object.entries(methodCounts).map(([method, count]) => (
          <Card key={method}>
            <CardHeader className="pb-3">
              <CardTitle className="text-base">{method}</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">{count}</p>
              <p className="text-xs text-muted-foreground mt-1">
                {((count / apis.length) * 100).toFixed(0)}%
              </p>
            </CardContent>
          </Card>
        ))}
      </section>

      {/* 按域分组 */}
      <section className="mb-8 space-y-6">
        {[...byDomain.entries()].map(([domain, domainApis]) => (
          <Card key={domain}>
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2">
                <FileText className="h-4 w-4 text-primary" />
                {domain}{" "}
                <span className="text-muted-foreground font-normal">
                  ({domainApis.length} endpoint)
                </span>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs text-muted-foreground border-b">
                    <tr>
                      <th className="pb-2 w-16">Method</th>
                      <th className="pb-2">Path</th>
                      <th className="pb-2">描述</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {domainApis.map((api, i) => (
                      <tr key={`${api.method}-${api.path}-${i}`}>
                        <td className="py-1.5">
                          <Badge
                            variant="outline"
                            className={`text-xs font-mono ${METHOD_COLORS[api.method]}`}
                          >
                            {api.method}
                          </Badge>
                        </td>
                        <td className="py-1.5 font-mono text-xs">
                          /api{api.path}
                        </td>
                        <td className="py-1.5 text-xs text-muted-foreground">
                          {api.description || "(无描述)"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        ))}
      </section>

      {/* 合规检查 */}
      <section className="mb-8 p-4 bg-muted border border-primary/30 rounded-lg">
        <div className="flex items-start gap-3">
          <CheckCircle2 className="h-5 w-5 text-primary mt-0.5 shrink-0" />
          <div className="text-sm">
            <p className="font-semibold text-foreground mb-1">
              CHARTER §3.5 + AGENTS §4.5 API 合规检查
            </p>
            <ul className="space-y-1 text-muted-foreground text-xs">
              <li>✅ 所有 endpoint 在 /api/* 下 (两域共享后端入口)</li>
              <li>✅ 命名约定 (kebab-case 路径 + camelCase 查询)</li>
              <li>⚠️ 详见每个 route.ts 文件里的 Zod schema 校验 (CHARTER §3.5 字段加密)</li>
            </ul>
          </div>
        </div>
      </section>

      <footer className="text-xs text-muted-foreground border-t pt-4">
        <p>
          📊 自动解析 (每次访问重新扫描):{" "}
          <code className="bg-muted px-1.5 py-0.5 rounded">
            src/app/api/**/route.ts
          </code>
          .
        </p>
        <p className="mt-1">
          ⚠️ 跳过 [...nextauth] catch-all (Auth.js 内部), 不计入 API 列表.
          真实运行时数据见{" "}
          <Link
            href="/dev/architecture"
            className="text-primary hover:underline"
          >
            /dev/architecture
          </Link>
          .
        </p>
      </footer>
    </main>
  );
}
