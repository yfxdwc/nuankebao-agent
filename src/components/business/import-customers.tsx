"use client";

import { useState, useRef } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/section";
import { cn } from "@/lib/utils";
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
    <div className="space-y-section-y">
      {/* 模板下载 + 上传区 (idle) */}
      {state.kind === "idle" && (
        <>
          <Section
            title="下载模板"
            description="按格式填入客户信息; 支持 Excel (.xlsx) / CSV; 必填: 姓名 + 手机号"
            action={
              <Button asChild variant="outline" size="sm">
                <a href="/api/import/template" download>
                  下载模板
                </a>
              </Button>
            }
          >
            <div className="flex items-center gap-2 text-body text-content-secondary">
              <FileDown className="h-4 w-4 shrink-0" />
              <span>支持 Excel/CSV 格式</span>
            </div>
          </Section>

          <Section title="选择文件">
            {/* 上传区: dashed border (上传专用, 非卡片) */}
            <div className="border-2 border-dashed border-divider rounded-md p-8 text-center">
              <Upload className="h-8 w-8 mx-auto text-content-tertiary" />
              <p className="mt-2 text-body text-content-primary">选择 Excel/CSV 文件</p>
              <input
                ref={fileRef}
                type="file"
                accept=".xlsx,.xls,.csv"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) handleFile(file);
                }}
                className="mt-4 text-body"
              />
            </div>
          </Section>
        </>
      )}

      {/* 上传中 */}
      {state.kind === "uploading" && (
        <Section>
          <div className="flex items-center gap-2 text-body text-content-secondary">
            <Loader2 className="h-4 w-4 animate-spin" />
            正在解析文件...
          </div>
        </Section>
      )}

      {/* 预览 */}
      {state.kind === "preview" && (
        <>
          <Section
            title={`预览: ${state.data.fileName}`}
            description={`${Math.ceil(state.data.fileSize / 1024)} KB`}
            action={
              state.data.validCount > 0 ? (
                <div className="flex gap-2">
                  <Button onClick={handleCommit}>
                    <CheckCircle className="h-4 w-4 mr-2" />
                    确认导入 {state.data.validCount} 条
                  </Button>
                  <Button variant="outline" onClick={reset}>
                    取消
                  </Button>
                </div>
              ) : undefined
            }
          >
            <div className="flex flex-wrap gap-2 text-body">
              <span className="text-caption text-content-secondary border border-divider px-1.5 py-0.5 rounded">
                共 {state.data.total} 条
              </span>
              <span className="text-caption text-success bg-success-light px-1.5 py-0.5 rounded">
                ✓ {state.data.validCount} 条可导入
              </span>
              {state.data.invalidCount > 0 && (
                <span className="text-caption text-danger bg-danger-light px-1.5 py-0.5 rounded">
                  ✗ {state.data.invalidCount} 条有问题
                </span>
              )}
            </div>
            {state.data.validCount === 0 && (
              <div className="mt-section-y">
                <p className="text-body text-content-secondary">无可导入数据, 请检查文件</p>
                <Button variant="outline" onClick={reset} className="mt-2">
                  取消
                </Button>
              </div>
            )}
          </Section>

          {/* 问题行详情 (同质列表 = divide-y) */}
          {state.data.results.filter((r) => !r.valid).length > 0 && (
            <Section
              title={`问题行详情 (${state.data.results.filter((r) => !r.valid).length})`}
            >
              <ul className="divide-y divide-divider">
                {state.data.results
                  .filter((r) => !r.valid)
                  .map((r) => (
                    <li key={r.rowNumber} className="py-2.5 space-y-1">
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-body-lg font-medium text-content-primary">
                          第 {r.rowNumber} 行
                        </span>
                        <span className="text-caption text-content-tertiary tabular-nums">
                          {String(r.data.name ?? "(无姓名)")}
                        </span>
                      </div>
                      <ul className="text-caption text-content-secondary space-y-0.5">
                        {r.errors.map((e, i) => (
                          <li key={i}>· {e}</li>
                        ))}
                      </ul>
                    </li>
                  ))}
              </ul>
            </Section>
          )}
        </>
      )}

      {/* 导入中 */}
      {state.kind === "committing" && (
        <Section>
          <div className="flex items-center gap-2 text-body text-content-secondary">
            <Loader2 className="h-4 w-4 animate-spin" />
            正在导入...
          </div>
        </Section>
      )}

      {/* 导入完成 */}
      {state.kind === "committed" && (
        <Section title="导入完成">
          <div className="flex items-center gap-2 text-success mb-2">
            <CheckCircle className="h-4 w-4" />
            <span className="font-medium">导入完成</span>
          </div>
          <p className="text-body-lg">
            <strong className="text-success">{state.data.inserted}</strong> 条客户已成功导入
          </p>
          {state.data.skipped > 0 && (
            <p className="text-body text-content-secondary mt-1">
              {state.data.skipped} 条跳过
            </p>
          )}
          {state.data.errors.length > 0 && (
            <details className="text-caption mt-2">
              <summary className="cursor-pointer text-content-secondary">
                错误详情 ({state.data.errors.length})
              </summary>
              <ul className="mt-2 space-y-0.5 text-content-secondary">
                {state.data.errors.map((e, i) => (
                  <li key={i}>
                    第 {e.rowNumber} 行: {e.error}
                  </li>
                ))}
              </ul>
            </details>
          )}
          <div className="flex gap-2 pt-section-y">
            <Button onClick={reset}>继续导入</Button>
            <Button variant="outline" asChild>
              <Link href="/admin/customers">查看客户列表</Link>
            </Button>
          </div>
        </Section>
      )}

      {/* 错误 */}
      {state.kind === "error" && (
        <Section>
          <div className="flex items-center gap-2 text-danger">
            <AlertCircle className="h-4 w-4" />
            <span>{state.message}</span>
          </div>
          <Button variant="outline" onClick={reset} className="mt-section-y">
            重试
          </Button>
        </Section>
      )}
    </div>
  );
}