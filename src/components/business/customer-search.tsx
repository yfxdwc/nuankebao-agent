"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState, useEffect, useTransition } from "react";
import { Search, X } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

/**
 * 暖客宝 客户搜索 (client component)
 *
 * 行为:
 *   - 受控输入, 200ms debounce 后 push URL ?search=xxx
 *   - URL 是 source of truth (SSR 一致, 后退按钮工作)
 *   - 桌面/移动通用
 */
export function CustomerSearch({ initial }: { initial: string }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [value, setValue] = useState(initial);
  const [, startTransition] = useTransition();

  // 同步 URL → input (用户点返回按钮时)
  useEffect(() => {
    setValue(searchParams.get("search") ?? "");
  }, [searchParams]);

  // 200ms debounce 推 URL
  useEffect(() => {
    const t = setTimeout(() => {
      const current = searchParams.get("search") ?? "";
      if (value === current) return;  // 没变, 不动
      const params = new URLSearchParams(searchParams.toString());
      if (value) {
        params.set("search", value);
      } else {
        params.delete("search");
      }
      const qs = params.toString();
      startTransition(() => {
        router.replace(qs ? `/admin/customers?${qs}` : "/admin/customers");
      });
    }, 200);
    return () => clearTimeout(t);
  }, [value, router, searchParams]);

  return (
    <div className="relative">
      <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-content-tertiary pointer-events-none" />
      <Input
        type="search"
        inputMode="search"
        placeholder="搜索客户姓名/手机号…"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        className="pl-9 pr-9 min-h-control text-body-lg"
        aria-label="搜索客户"
      />
      {value && (
        <Button
          type="button"
          variant="ghost"
          size="icon"
          onClick={() => setValue("")}
          className="absolute right-1 top-1/2 -translate-y-1/2 h-8 w-8"
          aria-label="清除搜索"
        >
          <X className="h-4 w-4" />
        </Button>
      )}
    </div>
  );
}
