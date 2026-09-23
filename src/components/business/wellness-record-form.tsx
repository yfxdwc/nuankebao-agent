"use client";

import { useState, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Section } from "@/components/ui/section";
import { cn } from "@/lib/utils";
import { ArrowLeft, ArrowRight, Check, User, Target, Package, Activity, MessageSquare, Plus, X } from "lucide-react";

interface WellnessRecordFormProps {
  initial?: {
    id?: string;
    customerId?: string;
    serviceDate?: string;
    serviceItemId?: string;
    staffId?: string | null;
    storeId?: string | null;
    bodyPartIds?: string[];
    productUsages?: Array<{ productId: string; quantity?: number }>;
    preCondition?: Record<string, unknown>;
    postCondition?: Record<string, unknown>;
    processNote?: string;
    customerFeedback?: string;
    nextAdviceDate?: string | null;
  };
  mode: "create" | "edit";
}

interface Dictionary {
  bodyParts: Array<{ id: string; name: string }>;
  serviceItems: Array<{ id: string; name: string }>;
  products: Array<{ id: string; name: string; unit: string | null }>;
}

const STEPS = [
  { value: 0, label: "基本信息", icon: User, required: ["customerId", "serviceItemId"] },
  { value: 1, label: "部位 + 用料", icon: Target, required: ["bodyPartIds"] },
  { value: 2, label: "效果评估", icon: Activity, required: [] as string[] },  // 可选
  { value: 3, label: "反馈", icon: MessageSquare, required: [] as string[] },
] as const;

export function WellnessRecordForm({ initial, mode }: WellnessRecordFormProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const preselectedCustomerId = searchParams.get("customerId") ?? undefined;

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dict, setDict] = useState<Dictionary | null>(null);
  const [step, setStep] = useState(0);

  const [form, setForm] = useState({
    customerId: initial?.customerId ?? preselectedCustomerId ?? "",
    serviceDate:
      initial?.serviceDate ??
      new Date().toISOString().split("T")[0],
    serviceItemId: initial?.serviceItemId ?? "",
    bodyPartIds: initial?.bodyPartIds ?? [],
    productUsages: initial?.productUsages ?? [],
    painLevelPre: (initial?.preCondition?.pain_level as number | undefined) ?? undefined,
    sleepQualityPre: (initial?.preCondition?.sleep_quality as number | undefined) ?? undefined,
    painLevelPost: (initial?.postCondition?.pain_level as number | undefined) ?? undefined,
    sleepQualityPost: (initial?.postCondition?.sleep_quality as number | undefined) ?? undefined,
    processNote: initial?.processNote ?? "",
    customerFeedback: initial?.customerFeedback ?? "",
    nextAdviceDate: initial?.nextAdviceDate ?? "",
  });

  useEffect(() => {
    fetch("/api/dictionaries")
      .then((r) => r.json())
      .then((d) => {
        // 防御: API 可能返 { error } (401 dev skip auth) 或旧 shape
        if (!d || !Array.isArray(d.serviceItems)) {
          throw new Error("字典数据格式错误");
        }
        setDict(d);
      })
      .catch((e) => setError(`加载字典失败: ${e.message}`));
  }, []);

  function toggleBodyPart(id: string) {
    setForm((prev) => ({
      ...prev,
      bodyPartIds: prev.bodyPartIds.includes(id)
        ? prev.bodyPartIds.filter((x) => x !== id)
        : [...prev.bodyPartIds, id],
    }));
  }

  function addProduct() {
    setForm((prev) => ({
      ...prev,
      productUsages: [...prev.productUsages, { productId: "", quantity: undefined }],
    }));
  }

  function updateProduct(idx: number, field: "productId" | "quantity", value: string | number | undefined) {
    setForm((prev) => ({
      ...prev,
      productUsages: prev.productUsages.map((p, i) =>
        i === idx ? { ...p, [field]: value } : p
      ),
    }));
  }

  function removeProduct(idx: number) {
    setForm((prev) => ({
      ...prev,
      productUsages: prev.productUsages.filter((_, i) => i !== idx),
    }));
  }

  function validateStep(s: number): string | null {
    if (s === 0) {
      if (!form.customerId) return "请输入客户 ID";
      if (!form.serviceItemId) return "请选择服务项目";
    }
    if (s === 1) {
      if (form.bodyPartIds.length === 0) return "请至少选择 1 个部位";
    }
    return null;
  }

  function next() {
    const err = validateStep(step);
    if (err) {
      setError(err);
      return;
    }
    setError(null);
    setStep((s) => Math.min(STEPS.length - 1, s + 1));
  }

  function prev() {
    setError(null);
    setStep((s) => Math.max(0, s - 1));
  }

  async function handleSubmit(e?: React.FormEvent) {
    e?.preventDefault();
    // 全部 step 都过一遍校验
    for (let i = 0; i < STEPS.length; i++) {
      const err = validateStep(i);
      if (err) {
        setError(`第 ${i + 1} 步: ${err}`);
        setStep(i);
        return;
      }
    }
    setError(null);
    setLoading(true);
    try {
      const payload = {
        customerId: form.customerId,
        serviceDate: form.serviceDate,
        serviceItemId: form.serviceItemId,
        bodyPartIds: form.bodyPartIds,
        productUsages: form.productUsages.filter((p) => p.productId),
        preCondition: {
          ...(form.painLevelPre !== undefined && { pain_level: form.painLevelPre }),
          ...(form.sleepQualityPre !== undefined && { sleep_quality: form.sleepQualityPre }),
        },
        postCondition: {
          ...(form.painLevelPost !== undefined && { pain_level: form.painLevelPost }),
          ...(form.sleepQualityPost !== undefined && { sleep_quality: form.sleepQualityPost }),
        },
        processNote: form.processNote || undefined,
        customerFeedback: form.customerFeedback || undefined,
        nextAdviceDate: form.nextAdviceDate || undefined,
      };

      const url =
        mode === "create"
          ? "/api/wellness-records"
          : `/api/wellness-records/${initial?.id}`;
      const method = mode === "create" ? "POST" : "PATCH";

      const res = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || "保存失败");
      }

      const record = await res.json();
      router.push(`/admin/wellness-records/${record.id}`);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "保存失败");
      setLoading(false);
    }
  }

  if (!dict) {
    return <div className="text-content-secondary">加载中...</div>;
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3 md:space-y-4">
      {/* 进度条 (移动更突出) */}
      <div className="sticky top-12 z-20 -mx-3 md:mx-0 bg-background px-3 md:px-0 py-2 border-b border-divider md:border-b-0">
        <div className="flex items-center gap-1.5 md:gap-2 mb-1.5">
          {STEPS.map((s, idx) => {
            const Icon = s.icon;
            const isActive = step === idx;
            const isDone = step > idx;
            return (
              <div key={s.value} className="flex items-center gap-1.5 flex-1 md:flex-initial">
                <button
                  type="button"
                  onClick={() => {
                    // 只能点回已完成的 step 或下一步 (不允许跳到未填的)
                    if (idx <= step) setStep(idx);
                  }}
                  className={cn(
                    "flex items-center gap-1.5 px-2 py-1.5 rounded-md text-caption font-medium min-h-control-sm",
                    isActive
                      ? "bg-brand text-brand-foreground"
                      : isDone
                        ? "bg-brand-surface text-brand"
                        : "bg-surface-subtle text-content-secondary",
                    idx > step && "opacity-50 cursor-not-allowed"
                  )}
                >
                  {isDone ? <Check className="h-3 w-3" /> : <Icon className="h-3 w-3" />}
                  <span className="hidden sm:inline">{idx + 1}. {s.label}</span>
                  <span className="sm:hidden">{idx + 1}</span>
                </button>
                {idx < STEPS.length - 1 && (
                  <div className={cn("h-px flex-1", isDone ? "bg-brand" : "bg-divider")} />
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* 错误提示 (粘顶部下方) */}
      {error && (
        <p className="text-body text-danger bg-danger-surface rounded-md px-3 py-2">
          {error}
        </p>
      )}

      {/* Step 0: 基本信息 */}
      {step === 0 && (
        <Section title="基本信息" description="客户 ID 与服务日期、项目">
          <div className="grid gap-section-y sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="customerId">客户 ID *</Label>
              <Input
                id="customerId"
                type="number"
                required
                value={form.customerId}
                onChange={(e) => setForm({ ...form, customerId: e.target.value })}
                placeholder="客户 ID (数字)"
                className="min-h-control"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="serviceDate">服务日期 *</Label>
              <Input
                id="serviceDate"
                type="date"
                required
                value={form.serviceDate}
                onChange={(e) => setForm({ ...form, serviceDate: e.target.value })}
                className="min-h-control"
              />
            </div>
          </div>
          <div className="space-y-2 mt-section-y">
            <Label htmlFor="serviceItemId">服务项目 *</Label>
            <select
              id="serviceItemId"
              required
              value={form.serviceItemId}
              onChange={(e) => setForm({ ...form, serviceItemId: e.target.value })}
              className="flex h-11 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            >
              <option value="">请选择项目</option>
              {dict.serviceItems.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          </div>
        </Section>
      )}

      {/* Step 1: 部位 + 用料 */}
      {step === 1 && (
        <>
          <Section title="身体部位" description="多选 *">
            <div className="flex flex-wrap gap-2">
              {dict.bodyParts.map((bp) => (
                <button
                  key={bp.id}
                  type="button"
                  onClick={() => toggleBodyPart(bp.id)}
                  className={cn(
                    "px-3 py-1.5 rounded-full text-caption font-medium transition-colors min-h-control-sm",
                    form.bodyPartIds.includes(bp.id)
                      ? "bg-brand text-brand-foreground"
                      : "bg-surface-subtle text-content-secondary hover:bg-surface-sunken"
                  )}
                >
                  {bp.name}
                </button>
              ))}
            </div>
          </Section>

          <Section
            title="使用耗材"
            description="可选"
            action={
              <Button type="button" variant="outline" size="sm" onClick={addProduct}>
                <Plus className="h-3.5 w-3.5 mr-1" />
                添加
              </Button>
            }
          >
            {form.productUsages.length === 0 ? (
              <p className="text-body text-content-secondary">未使用耗材</p>
            ) : (
              <div className="divide-y divide-divider">
                {form.productUsages.map((p, idx) => (
                  <div key={idx} className="flex gap-2 items-end py-2 first:pt-0">
                    <div className="flex-1 space-y-1">
                      <Label className="text-caption">耗材</Label>
                      <select
                        value={p.productId}
                        onChange={(e) => updateProduct(idx, "productId", e.target.value)}
                        className="flex h-11 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                      >
                        <option value="">请选择</option>
                        {dict.products.map((prod) => (
                          <option key={prod.id} value={prod.id}>
                            {prod.name} ({prod.unit})
                          </option>
                        ))}
                      </select>
                    </div>
                    <div className="w-24 space-y-1">
                      <Label className="text-caption">用量</Label>
                      <Input
                        type="number"
                        step="0.1"
                        className="min-h-control"
                        value={p.quantity ?? ""}
                        onChange={(e) =>
                          updateProduct(idx, "quantity", e.target.value ? parseFloat(e.target.value) : undefined)
                        }
                      />
                    </div>
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      onClick={() => removeProduct(idx)}
                      className="h-11 w-11 shrink-0"
                      aria-label="删除"
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </Section>
        </>
      )}

      {/* Step 2: 效果评估 */}
      {step === 2 && (
        <Section title="状态评分" description="0-10, 可选">
          <div className="grid gap-section-y sm:grid-cols-2">
            <div className="space-y-2">
              <Label>理疗前 - 疼痛度</Label>
              <Input
                type="number"
                min="0"
                max="10"
                className="min-h-control"
                value={form.painLevelPre ?? ""}
                onChange={(e) =>
                  setForm({ ...form, painLevelPre: e.target.value ? parseInt(e.target.value) : undefined })
                }
                placeholder="0=无痛 10=剧痛"
              />
            </div>
            <div className="space-y-2">
              <Label>理疗前 - 睡眠质量</Label>
              <Input
                type="number"
                min="0"
                max="10"
                className="min-h-control"
                value={form.sleepQualityPre ?? ""}
                onChange={(e) =>
                  setForm({ ...form, sleepQualityPre: e.target.value ? parseInt(e.target.value) : undefined })
                }
                placeholder="0=很差 10=很好"
              />
            </div>
            <div className="space-y-2">
              <Label>理疗后 - 疼痛度</Label>
              <Input
                type="number"
                min="0"
                max="10"
                className="min-h-control"
                value={form.painLevelPost ?? ""}
                onChange={(e) =>
                  setForm({ ...form, painLevelPost: e.target.value ? parseInt(e.target.value) : undefined })
                }
              />
            </div>
            <div className="space-y-2">
              <Label>理疗后 - 睡眠质量</Label>
              <Input
                type="number"
                min="0"
                max="10"
                className="min-h-control"
                value={form.sleepQualityPost ?? ""}
                onChange={(e) =>
                  setForm({ ...form, sleepQualityPost: e.target.value ? parseInt(e.target.value) : undefined })
                }
              />
            </div>
          </div>
        </Section>
      )}

      {/* Step 3: 反馈 + 复访 */}
      {step === 3 && (
        <Section title="反馈 + 复访" description="可选">
          <div className="space-y-2">
            <Label htmlFor="processNote">理疗过程</Label>
            <Textarea
              id="processNote"
              value={form.processNote}
              onChange={(e) => setForm({ ...form, processNote: e.target.value })}
              rows={3}
              placeholder="操作过程, 取穴, 手法 等"
            />
          </div>
          <div className="space-y-2 mt-section-y">
            <Label htmlFor="customerFeedback">客户反馈</Label>
            <Textarea
              id="customerFeedback"
              value={form.customerFeedback}
              onChange={(e) => setForm({ ...form, customerFeedback: e.target.value })}
              rows={2}
              placeholder="客户主诉感受"
            />
          </div>
          <div className="space-y-2 mt-section-y">
            <Label htmlFor="nextAdviceDate">下次建议日期</Label>
            <Input
              id="nextAdviceDate"
              type="date"
              className="min-h-control"
              value={form.nextAdviceDate}
              onChange={(e) => setForm({ ...form, nextAdviceDate: e.target.value })}
            />
          </div>
        </Section>
      )}

      {/* 底部导航 (sticky) */}
      <div className="sticky bottom-16 md:bottom-0 z-20 -mx-3 md:mx-0 bg-background px-3 md:px-0 py-2 border-t border-divider md:border-t-0 flex items-center gap-2">
        <Button
          type="button"
          variant="ghost"
          onClick={() => router.back()}
          disabled={loading}
          className="md:order-1"
        >
          取消
        </Button>
        <div className="flex-1 flex items-center gap-2 justify-end">
          {step > 0 && (
            <Button
              type="button"
              variant="outline"
              onClick={prev}
              disabled={loading}
              className="h-11"
            >
              <ArrowLeft className="h-4 w-4 mr-1" />
              上一步
            </Button>
          )}
          {step < STEPS.length - 1 ? (
            <Button
              type="button"
              onClick={next}
              disabled={loading}
              className="h-11"
            >
              下一步
              <ArrowRight className="h-4 w-4 ml-1" />
            </Button>
          ) : (
            <Button type="submit" disabled={loading} className="h-11">
              {loading ? "保存中..." : mode === "create" ? "创建记录" : "保存修改"}
            </Button>
          )}
        </div>
      </div>
    </form>
  );
}
