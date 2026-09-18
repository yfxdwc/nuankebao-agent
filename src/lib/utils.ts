import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * 合并 className + Tailwind 类名冲突解决
 * shadcn/ui 标准工具函数
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/**
 * 手机号打码 (展示用): 13800138000 → 138****8000
 *
 * 边界:
 *   - 非 11 位 (老数据 / 座机 / 空) → 只留头 3 + 尾 2, 至少不整串暴露;
 *     长度 <= 5 时全打码
 *   - null / undefined / 空串 → "" (调用方自己决定占位符)
 *
 * 用在: GET /api/me (「我的」页默认只显示打码号, 点"显示"才用 full)
 */
export function maskPhone(phone: string | null | undefined): string {
  if (!phone) return "";
  const digits = phone.replace(/\D/g, "");
  if (digits.length === 0) return "";
  if (digits.length === 11) return `${digits.slice(0, 3)}****${digits.slice(7)}`;
  if (digits.length <= 5) return "*".repeat(digits.length);
  return `${digits.slice(0, 3)}${"*".repeat(Math.max(digits.length - 5, 1))}${digits.slice(-2)}`;
}

/**
 * 格式化日期 (中文友好)
 */
export function formatDate(date: Date | string | null | undefined): string {
  if (!date) return "-";
  const d = typeof date === "string" ? new Date(date) : date;
  return d.toLocaleDateString("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
}