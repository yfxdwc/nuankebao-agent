"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import Link from "next/link";
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
      <div className="py-10 text-center text-body text-content-secondary">
        {search
          ? `未找到包含 "${search}" 的客户`
          : "暂无客户,点击右下角 + 开始"}
      </div>
    );
  }

  return (
    <>
      {/* B3: 同质列表 = divide-y 分隔线, 不再包 border + bg-card (反 SaaS 观感) */}
      <ul className="divide-y divide-divider">
        {items.map((customer) => (
          <Link
            key={customer.id}
            href={`/admin/customers/${customer.id}`}
            className="block hover:bg-surface-subtle transition-colors active:bg-surface-sunken"
          >
            {/* B3: min-h-control-lg 行高 (44px) 兜底热区, 移动/桌面统一 */}
            <div className="px-1 py-3 min-h-control-lg flex items-start gap-3">
                <div
                  className="h-10 w-10 rounded-full bg-brand-surface text-brand flex items-center justify-center text-body-lg font-medium shrink-0"
                  aria-hidden="true"
                >
                  {customer.name.slice(0, 1)}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <h3 className="font-medium text-body-lg text-content-primary truncate">
                      {customer.name}
                    </h3>
                    <span className="text-caption text-content-tertiary shrink-0 tabular-nums">
                      {customer.gender === "F"
                        ? "女"
                        : customer.gender === "M"
                          ? "男"
                          : "-"}
                    </span>
                  </div>
                  <div className="flex items-center gap-1.5 text-caption text-content-secondary mt-0.5">
                    <Phone className="h-3 w-3 shrink-0" />
                    <span className="truncate tabular-nums">
                      {customer.phone.replace(/(\d{3})\d{4}(\d{4})/, "$1****$2")}
                    </span>
                    <span className="ml-auto tabular-nums">
                      {customer.createdAt.split("T")[0]}
                    </span>
                  </div>
                  {customer.healthTags.length > 0 && (
                    <div className="flex flex-wrap gap-1 mt-1.5">
                      {customer.healthTags.slice(0, 2).map((tag) => (
                        <span
                          key={tag}
                          className="text-caption text-content-secondary bg-surface-subtle px-1.5 py-0.5 rounded"
                        >
                          {tag}
                        </span>
                      ))}
                      {customer.healthTags.length > 2 && (
                        <span className="text-caption text-content-tertiary self-center">
                          +{customer.healthTags.length - 2}
                        </span>
                      )}
                    </div>
                  )}
                </div>
              </div>
          </Link>
        ))}
      </ul>

      {/* 底部: 加载更多 / 已加载完 / 错误 */}
      <div ref={sentinelRef} className="h-4" aria-hidden="true" />

      {loading && (
        <div className="flex items-center justify-center gap-2 py-4 text-body text-content-secondary">
          <Loader2 className="h-4 w-4 animate-spin" />
          加载更多…
        </div>
      )}

      {error && !loading && (
        <div className="text-center py-3">
          <p className="text-body text-danger mb-2">加载失败: {error}</p>
          <button
            type="button"
            onClick={loadMore}
            className="text-body text-brand underline min-h-tap-compact px-4"
          >
            重试
          </button>
        </div>
      )}

      {!hasMore && !loading && items.length > 0 && (
        <p className="text-center text-caption text-content-tertiary py-4">
          — 共 {total} 位客户，已加载完毕 —
        </p>
      )}
    </>
  );
}
