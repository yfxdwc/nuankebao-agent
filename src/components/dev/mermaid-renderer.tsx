"use client";

// ============================================
// Mermaid 渲染器 (client component)
// 用于 /admin/dev/architecture 渲染 CHARTER §4 文字图
// mermaid 是 browser-only 库, 必须客户端渲染
// ============================================

import { useEffect, useRef, useState } from "react";
import mermaid from "mermaid";

interface MermaidRendererProps {
  chart: string;
  className?: string;
}

// 单例 mermaid init (避免重复)
let mermaidInitialized = false;

export function MermaidRenderer({ chart, className }: MermaidRendererProps) {
  const ref = useRef<HTMLDivElement>(null);
  const [svg, setSvg] = useState<string>("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!mermaidInitialized) {
      mermaid.initialize({
        startOnLoad: false,
        theme: "default",
        securityLevel: "strict",
        fontFamily: "system-ui, sans-serif",
      });
      mermaidInitialized = true;
    }

    const id = `mermaid-${Math.random().toString(36).slice(2)}`;
    mermaid
      .render(id, chart)
      .then(({ svg }) => {
        setSvg(svg);
        setError(null);
      })
      .catch((e) => {
        setError(e?.message || String(e));
      });
  }, [chart]);

  if (error) {
    return (
      <div className="p-4 bg-danger-surface border border-danger-light rounded-lg">
        <p className="text-sm font-semibold text-danger">Mermaid 渲染失败</p>
        <pre className="text-xs text-danger mt-2 whitespace-pre-wrap">
          {error}
        </pre>
      </div>
    );
  }

  return (
    <div
      ref={ref}
      className={className}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
