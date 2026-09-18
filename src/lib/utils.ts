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
 * 规则 (先判手机号, 再兜底通用):
 *   - 11 位手机号 (1[3-9]xxxxxxxx) → 头 3 + **** + 尾 4
 *   - 其他 (座机 / 境外 / 带分机 / 老数据) → 头 3 + 同样长度的星号 + 尾 2
 *     (长度 <= 5 时全打码)
 *   - null / undefined / 空串 / 没数字 → "" (调用方自己决定占位符)
 *
 * ⚠ 不变量: 输出永远不等于输入 (回归测试锁住) —— 打码函数把明文漏出去 = 事故
 * 用在: GET /api/me (「我的」页默认只显示打码号, 点"显示"才用 full)
 */
export function maskPhone(phone: string | null | undefined): string {
  if (!phone) return "";
  const digits = phone.replace(/\D/g, "");
  if (digits.length === 0) return "";
  if (/^1[3-9]\d{9}$/.test(digits)) {
    return `${digits.slice(0, 3)}****${digits.slice(7)}`;
  }
  if (digits.length <= 5) return "*".repeat(digits.length);
  return `${digits.slice(0, 3)}${"*".repeat(digits.length - 5)}${digits.slice(-2)}`;
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