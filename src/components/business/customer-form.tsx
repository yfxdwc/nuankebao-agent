"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select } from "@/components/ui/select";
import { Section } from "@/components/ui/section";
import { cn } from "@/lib/utils";

interface CustomerFormProps {
  initial?: {
    id?: string;
    name?: string;
    phone?: string;
    gender?: "M" | "F" | "U";
    birthYear?: number;
    healthTags?: string[];
    diseaseHistory?: string;
    notes?: string;
  };
  mode: "create" | "edit";
}

const HEALTH_TAG_OPTIONS = [
  "肩颈", "腰部", "膝盖", "睡眠差", "体寒", "湿气重",
  "月经不调", "消化不良", "免疫力低", "压力大",
];

export function CustomerForm({ initial, mode }: CustomerFormProps) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [form, setForm] = useState({
    name: initial?.name ?? "",
    phone: initial?.phone ?? "",
    gender: initial?.gender ?? ("F" as "M" | "F" | "U"),
    birthYear: initial?.birthYear?.toString() ?? "",
    healthTags: initial?.healthTags ?? [],
    diseaseHistory: initial?.diseaseHistory ?? "",
    notes: initial?.notes ?? "",
  });

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const payload = {
        name: form.name,
        phone: form.phone,
        gender: form.gender,
        birthYear: form.birthYear ? parseInt(form.birthYear) : undefined,
        healthTags: form.healthTags,
        diseaseHistory: form.diseaseHistory || undefined,
        notes: form.notes || undefined,
      };

      const url =
        mode === "create"
          ? "/api/customers"
          : `/api/customers/${initial?.id}`;
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

      const customer = await res.json();
      router.push(`/admin/customers/${customer.id}`);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "保存失败");
      setLoading(false);
    }
  }

  function toggleHealthTag(tag: string) {
    setForm((prev) => ({
      ...prev,
      healthTags: prev.healthTags.includes(tag)
        ? prev.healthTags.filter((t) => t !== tag)
        : [...prev.healthTags, tag],
    }));
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-section-y">
      <Section title="基本信息">
        <div className="grid gap-section-y sm:grid-cols-2">
          <div className="space-y-2">
            <Label htmlFor="name">姓名 *</Label>
            <Input
              id="name"
              required
              className="min-h-control"
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              placeholder="如: 王女士"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="phone">手机号 *</Label>
            <Input
              id="phone"
              type="tel"
              required
              className="min-h-control"
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value.replace(/\D/g, "") })}
              placeholder="11 位手机号"
              maxLength={11}
            />
          </div>
        </div>

        <div className="grid gap-section-y sm:grid-cols-2 mt-section-y">
          <div className="space-y-2">
            <Label htmlFor="gender">性别</Label>
            <Select
              id="gender"
              value={form.gender}
              onChange={(e) => setForm({ ...form, gender: e.target.value as "M" | "F" | "U" })}
            >
              <option value="F">女</option>
              <option value="M">男</option>
              <option value="U">未知</option>
            </Select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="birthYear">出生年份</Label>
            <Input
              id="birthYear"
              type="number"
              className="min-h-control"
              value={form.birthYear}
              onChange={(e) => setForm({ ...form, birthYear: e.target.value })}
              placeholder="如: 1985"
              min="1900"
              max={new Date().getFullYear()}
            />
          </div>
        </div>
      </Section>

      <Section title="健康标签" description="多选">
        <div className="flex flex-wrap gap-2">
          {HEALTH_TAG_OPTIONS.map((tag) => (
            <button
              key={tag}
              type="button"
              onClick={() => toggleHealthTag(tag)}
              className={cn(
                "px-3 py-1.5 rounded-full text-caption font-medium transition-colors min-h-control-sm",
                form.healthTags.includes(tag)
                  ? "bg-brand text-brand-foreground"
                  : "bg-surface-subtle text-content-secondary hover:bg-surface-sunken"
              )}
            >
              {tag}
            </button>
          ))}
        </div>
      </Section>

      <Section title="病史与备注">
        <div className="space-y-2">
          <Label htmlFor="diseaseHistory">既往病史 / 过敏史</Label>
          <Textarea
            id="diseaseHistory"
            value={form.diseaseHistory}
            onChange={(e) => setForm({ ...form, diseaseHistory: e.target.value })}
            placeholder="如: 高血压, 青霉素过敏 等"
            rows={3}
          />
        </div>
        <div className="space-y-2 mt-section-y">
          <Label htmlFor="notes">备注</Label>
          <Textarea
            id="notes"
            value={form.notes}
            onChange={(e) => setForm({ ...form, notes: e.target.value })}
            placeholder="VIP 客户, 偏好项目 等"
            rows={3}
          />
        </div>
      </Section>

      {error && (
        <p className="text-body text-danger bg-danger-surface rounded-md px-3 py-2">
          {error}
        </p>
      )}

      <div className="flex gap-2 pt-2">
        <Button
          type="button"
          variant="outline"
          onClick={() => router.back()}
          disabled={loading}
        >
          取消
        </Button>
        <Button type="submit" disabled={loading || !form.name || form.phone.length !== 11}>
          {loading ? "保存中..." : mode === "create" ? "创建客户" : "保存修改"}
        </Button>
      </div>
    </form>
  );
}