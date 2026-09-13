import { db } from "@/lib/db";
import {
  customer,
  wellnessRecord,
  followUpTask,
} from "@/lib/db/schema";
import { eq, desc, sql, isNull, and } from "drizzle-orm";
import { aiComplete } from "./client";
import { buildFollowUpPrompt } from "./prompts";
import { decryptField } from "@/lib/crypto/field";

// ============================================
// 跟进话术生成
// 输入: customerId 或 taskId
// 输出: 完整跟进话术
// ============================================

export interface FollowUpSuggestion {
  customerId: string;
  customerName: string;
  lastVisit: string | null;
  daysSinceLastVisit: number | null;
  avgInterval: number | null;
  reason: string;
  suggestion: string;
  aiMock: boolean;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

/**
 * 计算客户最近到店间隔 (天)
 */
async function getDaysSinceLastVisit(
  customerId: bigint
): Promise<{ daysSinceLastVisit: number | null; avgInterval: number | null; lastVisit: string | null }> {
  const records = await db
    .select({ serviceDate: wellnessRecord.serviceDate })
    .from(wellnessRecord)
    .where(eq(wellnessRecord.customerId, customerId))
    .orderBy(desc(wellnessRecord.serviceDate))
    .limit(20);

  if (records.length === 0) {
    return { daysSinceLastVisit: null, avgInterval: null, lastVisit: null };
  }

  const lastDate = new Date(String(records[0].serviceDate));
  const daysSince = Math.floor(
    (Date.now() - lastDate.getTime()) / (1000 * 60 * 60 * 24)
  );

  // 平均复购周期 (相邻间隔)
  let avgInterval: number | null = null;
  if (records.length >= 2) {
    const result = await db.execute<{ avg_days: number }>(sql`
      WITH ordered AS (
        SELECT
          service_date,
          LAG(service_date) OVER (ORDER BY service_date) AS prev_date
        FROM wellness_record
        WHERE customer_id = ${customerId.toString()}
      )
      SELECT AVG(service_date - prev_date)::float AS avg_days
      FROM ordered
      WHERE prev_date IS NOT NULL
    `);
    const r = result as unknown as Array<{ avg_days: number | null }>;
    if (r[0]?.avg_days != null) {
      avgInterval = Math.round(Number(r[0].avg_days));
    }
  }

  return {
    daysSinceLastVisit: daysSince,
    avgInterval,
    lastVisit: String(records[0].serviceDate),
  };
}

/**
 * 生成跟进话术
 */
export async function generateFollowUpSuggestion(
  customerId: bigint,
  reason: string = "复购周期提醒"
): Promise<FollowUpSuggestion | null> {
  // 1. 取客户
  const [cust] = await db
    .select()
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);

  if (!cust) return null;

  // 2. 计算到店间隔
  const interval = await getDaysSinceLastVisit(customerId);

  // 3. 解密基础信息
  const healthTags = cust.healthTagsEncrypted
    ? safeJsonParse(decryptField(cust.healthTagsEncrypted))
    : [];

  // 4. 准备 AI 输入 (简化 profile)
  const profileSummary = `客户 ${cust.name}, ${
    cust.gender === "F" ? "女" : cust.gender === "M" ? "男" : ""
  }, 出生年 ${cust.birthYear ?? "未知"}, 健康标签: ${
    Array.isArray(healthTags) ? healthTags.join("/") : "无"
  }, 既往病史: ${
    cust.diseaseHistoryEncrypted ? decryptField(cust.diseaseHistoryEncrypted) : "无"
  }`;

  const { system, prompt } = buildFollowUpPrompt({
    customerName: cust.name,
    customerProfile: profileSummary,
    lastVisit: interval.lastVisit,
    daysSinceLastVisit: interval.daysSinceLastVisit,
    avgInterval: interval.avgInterval,
    reason,
  });

  const aiResult = await aiComplete({
    system,
    prompt,
    maxTokens: 500,
    temperature: 0.7,
  });

  return {
    customerId: customerId.toString(),
    customerName: cust.name,
    lastVisit: interval.lastVisit,
    daysSinceLastVisit: interval.daysSinceLastVisit,
    avgInterval: interval.avgInterval,
    reason,
    suggestion: aiResult.text,
    aiMock: aiResult.mock,
    usage: aiResult.usage,
  };
}

function safeJsonParse(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return [];
  }
}