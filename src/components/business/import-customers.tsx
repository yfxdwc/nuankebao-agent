"use client";

import { useState, useRef } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Upload, FileDown, CheckCircle, AlertCircle, Loader2 } from "lucide-react";

interface ValidationRow {
  rowNumber: number;
  valid: boolean;
  errors: string[];
  duplicate?: boolean;
  data: Record<string, unknown>;
}

interface PreviewResult {
  mode: "preview";
  fileName: string;
  fileSize: number;
  total: number;
  validCount: number;
  invalidCount: number;
  duplicateCount: number;
  results: ValidationRow[];
}

interface CommitResult {
  mode: "commit";
  total: number;
  inserted: number;
  skipped: number;
  errors: Array<{ rowNumber: number; error: string }>;
}

type State =
  | { kind: "idle" }
  | { kind: "uploading" }
  | { kind: "preview"; data: PreviewResult }
  | { kind: "committing" }
  | { kind: "committed"; data: CommitResult }
  | { kind: "error"; message: string };

export function ImportCustomers() {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [state, setState] = useState<State>({ kind: "idle" });

  async function handleFile(file: File) {
    setState({ kind: "uploading" });

    try {
      const formData = new FormData();
      formData.append("file", file);
      const res = await fetch("/api/import/customers?mode=preview", {
        method: "POST",
        body: formData,
      });
      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || "解析失败");
      }
      const data = await res.json();
      setState({ kind: "preview", data });
    } catch (err) {
      setState({
        kind: "error",
        message: err instanceof Error ? err.message : "上传失败",
      });
    }
  }

  async function handleCommit() {
    if (state.kind !== "preview") return;
    setState({ kind: "committing" });

    try {
      const file = fileRef.current?.files?.[0];
      if (!file) throw new Error("文件丢失,请重新选择");

      const formData = new FormData();
      formData.append("file", file);
      const res = await fetch("/api/import/customers?mode=commit", {
        method: "POST",
        body: formData,
      });
      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || "导入失败");
      }
      const data = await res.json();
      setState({ kind: "committed", data });
      router.refresh();
    } catch (err) {
      setState({
        kind: "error",
        message: err instanceof Error ? err.message : "导入失败",
      });
    }
  }

  function reset() {
    if (fileRef.current) fileRef.current.value = "";
    setState({ kind: "idle" });
  }

  return (
    <div className="space-y-4">
      {/* 模板下载 + 上传区 */}
      {state.kind === "idle" && (
        <Card>
          <CardContent className="py-4 px-card-y space-y-4">
            <div className="flex items-start gap-3 p-4 bg-muted rounded-md">
              <FileDown className="h-5 w-5 text-muted-foreground mt-0.5" />
              <div className="flex-1 text-sm">
                <p className="font-medium">先下载模板, 按格式填入客户信息</p>
                <p className="text-muted-foreground mt-1">
                  支持 Excel (.xlsx) / CSV, 必填: 姓名 + 手机号
                </p>
              </div>
              <Button asChild variant="outline" size="sm">
                <a href="/api/import/template" download>
                  下载模板
                </a>
              </Button>
            </div>

            <div className="border-2 border-dashed rounded-lg p-8 text-center">
              <Upload className="h-8 w-8 mx-auto text-muted-foreground" />
              <p className="mt-2 text-sm">选择 Excel/CSV 文件</p>
              <input
                ref={fileRef}
                type="file"
                accept=".xlsx,.xls,.csv"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) handleFile(file);
                }}
                className="mt-4 text-sm"
              />
            </div>
          </CardContent>
        </Card>
      )}

      {/* 上传中 */}
      {state.kind === "uploading" && (
        <Card>
          <CardContent className="py-4 px-card-y flex items-center gap-3 text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" />
            正在解析文件...
          </CardContent>
        </Card>
      )}

      {/* 预览 */}
      {state.kind === "preview" && (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">
                预览: {state.data.fileName} ({Math.ceil(state.data.fileSize / 1024)} KB)
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="flex flex-wrap gap-3 text-sm">
                <Badge variant="outline">共 {state.data.total} 条</Badge>
                <Badge className="bg-success-light text-success">
                  ✓ {state.data.validCount} 条可导入
                </Badge>
                {state.data.invalidCount > 0 && (
                  <Badge variant="destructive">
                    ✗ {state.data.invalidCount} 条有问题
                  </Badge>
                )}
              </div>

              {state.data.validCount === 0 ? (
                <p className="text-sm text-muted-foreground">无可导入数据, 请检查文件</p>
              ) : (
                <div className="flex gap-2">
                  <Button onClick={handleCommit}>
                    <CheckCircle className="h-4 w-4 mr-2" />
                    确认导入 {state.data.validCount} 条
                  </Button>
                  <Button variant="outline" onClick={reset}>
                    取消
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>

          {/* 问题行详情 */}
          {state.data.results.filter((r) => !r.valid).length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="text-base text-destructive">
                  问题行详情 ({state.data.results.filter((r) => !r.valid).length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2 text-sm">
                {state.data.results
                  .filter((r) => !r.valid)
                  .map((r) => (
                    <div key={r.rowNumber} className="p-3 border rounded-md">
                      <div className="flex items-center justify-between">
                        <span className="font-medium">第 {r.rowNumber} 行</span>
                        <Badge variant="outline">
                          {String(r.data.name ?? "(无姓名)")}
                        </Badge>
                      </div>
                      <ul className="mt-2 text-muted-foreground space-y-0.5">
                        {r.errors.map((e, i) => (
                          <li key={i}>· {e}</li>
                        ))}
                      </ul>
                    </div>
                  ))}
              </CardContent>
            </Card>
          )}
        </>
      )}

      {/* 导入中 */}
      {state.kind === "committing" && (
        <Card>
          <CardContent className="py-4 px-card-y flex items-center gap-3 text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" />
            正在导入 {state.kind === "committing" ? "" : ""}...
          </CardContent>
        </Card>
      )}

      {/* 导入完成 */}
      {state.kind === "committed" && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <CheckCircle className="h-5 w-5 text-success" />
              导入完成
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <p>
              <strong>{state.data.inserted}</strong> 条客户已成功导入
            </p>
            {state.data.skipped > 0 && (
              <p className="text-muted-foreground">
                {state.data.skipped} 条跳过
              </p>
            )}
            {state.data.errors.length > 0 && (
              <details className="text-xs">
                <summary className="cursor-pointer text-muted-foreground">
                  错误详情 ({state.data.errors.length})
                </summary>
                <ul className="mt-2 space-y-0.5 text-muted-foreground">
                  {state.data.errors.map((e, i) => (
                    <li key={i}>
                      第 {e.rowNumber} 行: {e.error}
                    </li>
                  ))}
                </ul>
              </details>
            )}
            <div className="flex gap-2 pt-2">
              <Button onClick={reset}>继续导入</Button>
              <Button variant="outline" asChild>
                <Link href="/admin/customers">查看客户列表</Link>
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* 错误 */}
      {state.kind === "error" && (
        <Card>
          <CardContent className="pt-6 space-y-3">
            <div className="flex items-center gap-2 text-destructive">
              <AlertCircle className="h-5 w-5" />
              <span>{state.message}</span>
            </div>
            <Button variant="outline" onClick={reset}>
              重试
            </Button>
          </CardContent>
        </Card>
      )}
    </div>
  );
}