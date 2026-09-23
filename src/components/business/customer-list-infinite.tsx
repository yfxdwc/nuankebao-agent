"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Phone, Loader2 } from "lucide-react";

interface CustomerView {
  id: string;
  name: string;
  phone: string;
  gender: "M" | "F" | "U" | null;
  birthYear: number | null;
  healthTags: string[];
  diseaseHistory: string | null;
  notes: string | null;
  createdAt: string;  // serialized from server
  updatedAt: string;
}

interface Props {
  initial: CustomerView[];
  initialTotal: number;
  pageSize: number;
  search: string;
}

/**
 * 暖客宝 客户列表无限滚动 (W17)
 *
 * 行为:
 *   - 父组件 (server) 传 initial + total + search
 *   - 滚到底部 → fetch /api/customers?offset=N&limit=pageSize
 *   - search 变化时父组件重渲染, 这里 useEffect 重置到 initial
 *   - 用 IntersectionObserver 触发 (比 scroll 监听高效)
 *   - 失败重试: 显示错误 + "重试" 按钮
 */
export function CustomerListInfinite({ initial, initialTotal, pageSize, search }: Props) {
  const [items, setItems] = useState<CustomerView[]>(initial);
  const [total, setTotal] = useState(initialTotal);
  const [offset, setOffset] = useState(initial.length);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // 用 ref 防并发 (旧请求未回时滚到又触发一次)
  const loadingRef = useRef(false);
  const sentinelRef = useRef<HTMLDivElement | null>(null);

  // search 变化 → 重置到 server 提供的 initial
  useEffect(() => {
    setItems(initial);
    setTotal(initialTotal);
    setOffset(initial.length);
    setError(null);
  }, [initial, initialTotal, search]);

  const hasMore = items.length < total;

  const loadMore = useCallback(async () => {
    if (loadingRef.current || !hasMore) return;
    loadingRef.current = true;
    setLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams({
        offset: String(offset),
        limit: String(pageSize),
      });
      if (search) params.set("search", search);
      const res = await fetch(`/api/customers?${params}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setItems((prev) => [...prev, ...data.items]);
      setOffset((prev) => prev + data.items.length);
      setTotal(data.total);
    } catch (e) {
      setError(e instanceof Error ? e.message : "加载失败");
    } finally {
      setLoading(false);
      loadingRef.current = false;
    }
  }, [offset, pageSize, hasMore, search]);

  // IntersectionObserver: 滚到 sentinel 时加载更多
  useEffect(() => {
    if (!hasMore) return;
    const el = sentinelRef.current;
    if (!el) return;
    const obs = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) {
          loadMore();
        }
      },
      { rootMargin: "200px" }  // 提前 200px 触发
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, [loadMore, hasMore]);

  if (items.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 md:py-12 text-center text-muted-foreground text-sm">
          {search
            ? `未找到包含 "${search}" 的客户`
            : "暂无客户,点击右下角 + 开始"}
        </CardContent>
      </Card>
    );
  }

  return (
    <>
      <ul className="divide-y divide-divider rounded-lg border border-border-default bg-card overflow-hidden">
        {items.map((customer) => (
          <Link
            key={customer.id}
            href={`/admin/customers/${customer.id}`}
            className="block hover:bg-surface-subtle transition-colors active:scale-[0.99]"
          >
            <div className="px-3 md:px-4 py-2.5 md:py-3">
                <div className="flex items-start gap-3">
                  <div
                    className="h-10 w-10 md:h-12 md:w-12 rounded-full bg-primary/10 text-primary flex items-center justify-center text-base md:text-lg font-medium shrink-0"
                    aria-hidden="true"
                  >
                    {customer.name.slice(0, 1)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between gap-2">
                      <h3 className="font-medium text-sm md:text-base truncate">
                        {customer.name}
                      </h3>
                      <Badge variant="outline" className="text-micro md:text-xs shrink-0">
                        {customer.gender === "F"
                          ? "女"
                          : customer.gender === "M"
                            ? "男"
                            : "-"}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-1.5 text-xs text-muted-foreground mt-1">
                      <Phone className="h-3 w-3 shrink-0" />
                      <span className="truncate">
                        {customer.phone.replace(/(\d{3})\d{4}(\d{4})/, "$1****$2")}
                      </span>
                    </div>
                    {customer.healthTags.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-2">
                        {customer.healthTags.slice(0, 2).map((tag) => (
                          <Badge
                            key={tag}
                            variant="secondary"
                            className="text-micro md:text-xs"
                          >
                            {tag}
                          </Badge>
                        ))}
                        {customer.healthTags.length > 2 && (
                          <span className="text-micro text-muted-foreground self-center">
                            +{customer.healthTags.length - 2}
                          </span>
                        )}
                      </div>
                    )}
                    <p className="text-micro md:text-xs text-muted-foreground mt-1.5 md:hidden">
                      {customer.createdAt.split("T")[0]}
                    </p>
                  </div>
                </div>
              </div>
          </Link>
        ))}
      </ul>

      {/* 底部: 加载更多 / 已加载完 / 错误 */}
      <div ref={sentinelRef} className="h-4" aria-hidden="true" />

      {loading && (
        <div className="flex items-center justify-center gap-2 py-4 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" />
          加载更多…
        </div>
      )}

      {error && !loading && (
        <div className="text-center py-3">
          <p className="text-sm text-destructive mb-2">加载失败: {error}</p>
          <button
            type="button"
            onClick={loadMore}
            className="text-sm text-primary underline min-h-tap-compact px-4"
          >
            重试
          </button>
        </div>
      )}

      {!hasMore && !loading && items.length > 0 && (
        <p className="text-center text-xs text-muted-foreground py-4">
          — 共 {total} 位客户，已加载完毕 —
        </p>
      )}
    </>
  );
}
