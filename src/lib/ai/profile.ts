import { db } from "@/lib/db";
import {
  customer,
  wellnessRecord,
  serviceItem,
  bodyPart,
  wellnessRecordBodyPart,
} from "@/lib/db/schema";
import { eq, desc, isNull, and } from "drizzle-orm";
import { aiComplete } from "./client";
import { buildProfilePrompt } from "./prompts";

// ============================================
// 客户画像: 聚合数据 + AI 总结
// 流程: 1. 拉取客户 + 最近 N 条养生记录 (SQL JOIN)
//      2. 应用层聚合数据 (不调 LLM, 纯数据)
//      3. 调 LLM 生成画像文字
// ============================================

export interface CustomerProfileResult {
  customer: {
    id: string;
    name: string;
    gender: string | null;
    birthYear: number | null;
    healthTags: string[];
    diseaseHistory: string | null;
    notes: string | null;
  };
  recentRecords: Array<{
    serviceDate: string;
    serviceItem: string;
    bodyParts: string[];
    preCondition: Record<string, unknown>;
    postCondition: Record<string, unknown>;
    feedback: string | null;
  }>;
  aiSummary: string;
  aiMock: boolean;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

/**
 * 生成客户画像 (应用层聚合 + AI 总结)
 */
export async function generateCustomerProfile(
  customerId: bigint
): Promise<CustomerProfileResult | null> {
  // 1. 取客户
  const [cust] = await db
    .select()
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);

  if (!cust) return null;

  // 2. 取最近 10 条养生记录 + JOIN 项目名 + 部位名
  const recentRecords = await db
    .select({
      id: wellnessRecord.id,
      serviceDate: wellnessRecord.serviceDate,
      serviceItemId: wellnessRecord.serviceItemId,
      preConditionEncrypted: wellnessRecord.preConditionEncrypted,
      postConditionEncrypted: wellnessRecord.postConditionEncrypted,
      customerFeedbackEncrypted: wellnessRecord.customerFeedbackEncrypted,
    })
    .from(wellnessRecord)
    .where(eq(wellnessRecord.customerId, customerId))
    .orderBy(desc(wellnessRecord.serviceDate))
    .limit(10);

  // 批量取项目名 + 部位名
  const serviceIds = Array.from(new Set(recentRecords.map((r) => r.serviceItemId)));
  const [services, allBodyParts, recordBodyPartRows] = await Promise.all([
    serviceIds.length > 0
      ? db.select().from(serviceItem).where(inArrayIdList(serviceIds))
      : Promise.resolve([]),
    db.select().from(bodyPart),
    db
      .select()
      .from(wellnessRecordBodyPart)
      .where(
        inArrayIdList(
          recentRecords.map((r) => r.id),
          "wellnessRecordId"
        )
      ),
  ]);

  const serviceMap = new Map(services.map((s) => [s.id.toString(), s.name]));
  const bodyPartMap = new Map(allBodyParts.map((b) => [b.id.toString(), b.name]));

  // 按 recordId 分组 body parts
  const bodyPartByRecord = new Map<string, string[]>();
  for (const row of recordBodyPartRows) {
    const recId = row.wellnessRecordId.toString();
    const partName = bodyPartMap.get(row.bodyPartId.toString()) ?? `#${row.bodyPartId}`;
    if (!bodyPartByRecord.has(recId)) bodyPartByRecord.set(recId, []);
    bodyPartByRecord.get(recId)!.push(partName);
  }

  // 3. 解密 + 汇总 (复用 decryptField, 不重复写)
  const { decryptField } = await import("@/lib/crypto/field");

  const recentRecordsView = recentRecords.map((r) => ({
    serviceDate: String(r.serviceDate),
    serviceItem: serviceMap.get(r.serviceItemId.toString()) ?? `#${r.serviceItemId}`,
    bodyParts: bodyPartByRecord.get(r.id.toString()) ?? [],
    preCondition: r.preConditionEncrypted
      ? safeJsonParseObj(decryptField(r.preConditionEncrypted))
      : {},
    postCondition: r.postConditionEncrypted
      ? safeJsonParseObj(decryptField(r.postConditionEncrypted))
      : {},
    feedback: r.customerFeedbackEncrypted
      ? decryptField(r.customerFeedbackEncrypted)
      : null,
  }));

  // 4. 准备 AI 输入
  const profileInput = {
    name: cust.name,
    gender: cust.gender,
    birthYear: cust.birthYear,
    healthTags: cust.healthTagsEncrypted
      ? safeJsonParseArr(decryptField(cust.healthTagsEncrypted))
      : [],
    diseaseHistory: cust.diseaseHistoryEncrypted
      ? decryptField(cust.diseaseHistoryEncrypted)
      : null,
    notes: cust.notesEncrypted ? decryptField(cust.notesEncrypted) : null,
    recentRecords: recentRecordsView,
  };

  // 5. 调 AI (或 mock)
  const { system, prompt } = buildProfilePrompt(profileInput);
  const aiResult = await aiComplete({
    system,
    prompt,
    maxTokens: 800,
    temperature: 0.6,
  });

  return {
    customer: {
      id: cust.id.toString(),
      name: cust.name,
      gender: cust.gender,
      birthYear: cust.birthYear,
      healthTags: profileInput.healthTags,
      diseaseHistory: profileInput.diseaseHistory,
      notes: profileInput.notes,
    },
    recentRecords: recentRecordsView,
    aiSummary: aiResult.text,
    aiMock: aiResult.mock,
    usage: aiResult.usage,
  };
}

function safeJsonParse(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return {};
  }
}

function safeJsonParseArr(s: string): string[] {
  try {
    const r = JSON.parse(s);
    return Array.isArray(r) ? r : [];
  } catch {
    return [];
  }
}

function safeJsonParseObj(s: string): Record<string, unknown> {
  try {
    const r = JSON.parse(s);
    return r && typeof r === "object" ? (r as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

// 简化 inArrayIdList (避免拉一堆 SQL helpers)
import { inArray } from "drizzle-orm";
function inArrayIdList(
  ids: Array<bigint | string>,
  columnName?: "wellnessRecordId"
) {
  // 仅 wellnessRecordBodyPart 用 wellnessRecordId 列
  if (columnName === "wellnessRecordId") {
    return inArray(wellnessRecordBodyPart.wellnessRecordId, ids as bigint[]);
  }
  return inArray(serviceItem.id, ids as bigint[]);
}