import { createCustomer } from "@/lib/db/queries/customer";
import { withAuditContext } from "@/lib/audit/context";
import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { hashForLookup } from "@/lib/crypto/field";
import type { ValidationResult } from "./validator";

// ============================================
// 批量导入器
// 把 ValidationResult.valid 批量写入 DB
// ============================================

export interface ImportSummary {
  total: number;
  inserted: number;
  skipped: number;
  errors: Array<{ rowNumber: number; error: string }>;
}

/**
 * 批量导入校验通过的 rows
 * @param userId 当前操作 user id
 */
export async function importCustomers(
  rows: ValidationResult[],
  userId: bigint,
  ipAddress: string | null
): Promise<ImportSummary> {
  const summary: ImportSummary = {
    total: rows.length,
    inserted: 0,
    skipped: 0,
    errors: [],
  };

  const ctx = {
    userId,
    ipAddress,
  };

  for (const row of rows) {
    if (!row.valid) {
      summary.skipped++;
      summary.errors.push({
        rowNumber: row.rowNumber,
        error: row.errors.join("; "),
      });
      continue;
    }

    try {
      const data = row.data as {
        name: string;
        phone: string;
        gender?: "M" | "F" | "U";
        birthYear?: number;
        healthTags?: string[];
        diseaseHistory?: string;
        notes?: string;
      };

      await createCustomer(data, ctx, userId);
      summary.inserted++;
    } catch (err) {
      summary.skipped++;
      summary.errors.push({
        rowNumber: row.rowNumber,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  return summary;
}