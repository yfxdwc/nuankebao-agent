import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { hashForLookup } from "@/lib/crypto/field";
import type { ParsedRow } from "./parser";

// ============================================
// 导入数据校验 + 去重
// ============================================

export interface ValidationResult {
  rowNumber: number;
  data: Record<string, unknown>;
  valid: boolean;
  errors: string[];
  duplicate?: boolean;  // 重复的客户 (phone 重复)
}

/**
 * 字段映射: Excel 列名 → DB 字段
 */
const FIELD_MAP: Record<string, string> = {
  姓名: "name",
  名字: "name",
  name: "name",
  手机号: "phone",
  电话: "phone",
  phone: "phone",
  性别: "gender",
  gender: "gender",
  出生年: "birthYear",
  birthYear: "birthYear",
  健康标签: "healthTags",
  healthTags: "healthTags",
  既往病史: "diseaseHistory",
  diseaseHistory: "diseaseHistory",
  备注: "notes",
  notes: "notes",
};

function mapData(data: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data)) {
    const mapped = FIELD_MAP[key] ?? key;
    result[mapped] = value;
  }
  return result;
}

function validateRow(row: ParsedRow): ValidationResult {
  const errors: string[] = [];
  const mapped = mapData(row.data);

  // 必填: 姓名
  const name = String(mapped.name ?? "").trim();
  if (!name) {
    errors.push("姓名缺失");
  }

  // 必填: 手机号
  const phone = String(mapped.phone ?? "").replace(/\D/g, "");
  if (!phone) {
    errors.push("手机号缺失");
  } else if (!/^1[3-9]\d{9}$/.test(phone)) {
    errors.push(`手机号格式错误: ${phone}`);
  }

  // 可选: 性别
  const genderRaw = String(mapped.gender ?? "").trim();
  if (genderRaw) {
    const g = genderRaw === "男" ? "M" : genderRaw === "女" ? "F" : genderRaw;
    if (!["M", "F", "U"].includes(g)) {
      errors.push(`性别值无效: ${genderRaw}`);
    }
  }

  // 可选: 出生年
  const birthYearRaw = mapped.birthYear;
  if (birthYearRaw !== "" && birthYearRaw !== undefined) {
    const by = Number(birthYearRaw);
    if (!Number.isInteger(by) || by < 1900 || by > new Date().getFullYear()) {
      errors.push(`出生年无效: ${birthYearRaw}`);
    }
  }

  // 可选: 健康标签 (逗号或中文逗号分隔)
  let healthTags: string[] = [];
  if (mapped.healthTags) {
    const tagsStr = String(mapped.healthTags);
    healthTags = tagsStr
      .split(/[,，;；]/)
      .map((s) => s.trim())
      .filter(Boolean);
  }

  return {
    rowNumber: row.rowNumber,
    data: {
      name,
      phone,
      gender: genderRaw === "男" ? "M" : genderRaw === "女" ? "F" : (genderRaw || "U"),
      birthYear: birthYearRaw ? Number(birthYearRaw) : undefined,
      healthTags,
      diseaseHistory: String(mapped.diseaseHistory ?? "").trim() || undefined,
      notes: String(mapped.notes ?? "").trim() || undefined,
    },
    valid: errors.length === 0,
    errors,
  };
}

/**
 * 批量校验 + 检测重复
 * 输入 ParsedFile, 输出 ValidationResult[]
 */
export async function validateImport(rows: ParsedRow[]): Promise<{
  results: ValidationResult[];
  validCount: number;
  invalidCount: number;
  duplicateCount: number;
}> {
  // 先做基本校验
  const results = rows.map(validateRow);

  // 检测 DB 重复 (基于 phone_hash)
  const phoneHashes = results
    .filter((r) => r.valid && r.data.phone)
    .map((r) => hashForLookup(String(r.data.phone)));

  const existingHashes = new Set<string>();
  if (phoneHashes.length > 0) {
    // 批量查重 (避免一次查太多)
    const uniqueHashes = Array.from(new Set(phoneHashes));
    for (const hash of uniqueHashes) {
      const existing = await db
        .select({ phoneHash: customer.phoneHash })
        .from(customer)
        .where(eq(customer.phoneHash, hash))
        .limit(1);
      if (existing.length > 0) {
        existingHashes.add(hash);
      }
    }
  }

  // 标记重复
  for (const r of results) {
    if (r.valid && r.data.phone) {
      const hash = hashForLookup(String(r.data.phone));
      if (existingHashes.has(hash)) {
        r.duplicate = true;
        r.errors.push("客户已存在 (手机号重复)");
        r.valid = false;
      }
    }
  }

  return {
    results,
    validCount: results.filter((r) => r.valid).length,
    invalidCount: results.filter((r) => !r.valid).length,
    duplicateCount: results.filter((r) => r.duplicate).length,
  };
}