// ============================================
// AI 洞察 (P5: 3 张 AI 卡合并成 **1 次** 调用)
//
// 主人 2026-09-23 拍: 「AI 4 卡合并成 1 次调用」
//
// ── 改动前 ──
//   客户详情页 AI 区有 3 张卡各自发请求 + 各自读库 + 各自调 MiniMax:
//     GET /api/ai/profile/[id]           → 1 次 AI
//     POST /api/ai/follow-up             → 1 次 AI
//     GET /api/ai/effect-analysis/[id]   → 1 次 AI
//   同一位客户的基本信息 + 养生记录被**重复喂 3 遍**; 且三段内容互相看不见
//   (话术不知道效果趋势, 效果分析不知道画像) → 既贵又不连贯。
//
// ── 改动后 ──
//   1 次读库 + **1 次 AI** → 三段内容 (画像 / 话术 / 效果) 一起出来;
//   复购预测仍是**纯 DB 计算** (不烧 AI, 见 predictions.ts)。
//
// 为什么保留三段而不是合成一大段:
//   销售的使用场景不同 —— 早上看画像了解人, 要打电话时看话术, 复盘时看效果。
//   三段各自有标题, 比一大段糊在一起更好找。
//
// 不变量 (冒烟断言): `aiCallCount === 1`
//   —— 这条是为了防止后人「顺手再加一个 aiComplete」把 P5 的收益悄悄改回去。
//   次数由本文件自己数, 与实现绑定。
// ============================================

import { db } from "@/lib/db";
import {
  customer,
  wellnessRecord,
  serviceItem,
  bodyPart,
  wellnessRecordBodyPart,
} from "@/lib/db/schema";
import { eq, desc, isNull, and, inArray } from "drizzle-orm";
import { aiComplete } from "./client";
import {
  buildAiInsightPrompt,
  INSIGHT_DELIMITERS,
  INSIGHT_SECTIONS,
  type InsightSectionKey,
} from "./prompts";
import { predictRepurchase, type RepurchasePrediction } from "./predictions";
import { decryptField } from "@/lib/crypto/field";

export interface AiInsightResult {
  customerId: string;
  customerName: string;
  /** 三段 AI 内容 (按 prompt 要求的分隔符切出来) */
  sections: Record<InsightSectionKey, string>;
  /**
   * 分隔符是否切成功。
   * false = 模型没按格式输出 → 全文落在 `sections.profile` (宁可不好看, 也不丢内容)
   */
  sectionsParsed: boolean;
  /** 复购预测: 纯 DB 计算, **不含 AI** */
  repurchase: RepurchasePrediction | null;
  /** 喂给 AI 的事实底稿 (结构化; 客户端可展示"依据", 也方便排查) */
  facts: {
    totalVisits: number;
    daysSinceLastVisit: number | null;
    avgIntervalDays: number | null;
    trend: "improving" | "stable" | "worsening" | "unknown";
    reason: string;
    dateRange: { from: string; to: string } | null;
  };
  aiMock: boolean;
  model: string;
  /** ⚠ P5 不变量: 本次洞察消耗的 AI 调用次数, 恒为 1 */
  aiCallCount: number;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

/**
 * 把 AI 原始输出切成三段
 *
 * 容错设计 (为什么不要求模型输出 JSON):
 *   - 分隔符缺失 / 顺序乱了 → 按实际出现的顺序取, 缺的段给空串
 *   - 完全切不出来 → `parsed=false`, 全文放进 `profile` (不丢内容)
 *   - 用 indexOf 而不是 split(regex): 模型偶尔会把分隔符写进段落中间,
 *     按行首匹配能减少误切
 */
export function parseInsightSections(raw: string): {
  sections: Record<InsightSectionKey, string>;
  parsed: boolean;
} {
  const empty: Record<InsightSectionKey, string> = {
    profile: "",
    followUp: "",
    effect: "",
  };
  const text = (raw ?? "").trim();
  if (!text) return { sections: empty, parsed: false };

  // 找出每个分隔符在 **行首** 的位置
  const hits: Array<{ key: InsightSectionKey; at: number; len: number }> = [];
  const lines = text.split("\n");
  let offset = 0;
  for (const line of lines) {
    const trimmed = line.trim();
    for (const key of INSIGHT_SECTIONS) {
      const d = INSIGHT_DELIMITERS[key];
      if (trimmed === d || trimmed.startsWith(d)) {
        hits.push({ key, at: offset, len: line.length });
        break;
      }
    }
    offset += line.length + 1; // +1 = 被 split 掉的 \n
  }

  if (hits.length === 0) {
    // 完全没按格式 → 不丢内容, 全文归画像
    return { sections: { ...empty, profile: text }, parsed: false };
  }

  hits.sort((a, b) => a.at - b.at);
  for (let i = 0; i < hits.length; i++) {
    const start = hits[i].at + hits[i].len;
    const end = i + 1 < hits.length ? hits[i + 1].at : text.length;
    const body = text.slice(start, end).trim();
    // 同一个分隔符出现多次 → 保留第一次有内容的
    if (!empty[hits[i].key]) empty[hits[i].key] = body;
  }

  // 三段全空 = 实际上没切出东西
  const anyContent = INSIGHT_SECTIONS.some((k) => empty[k].length > 0);
  return { sections: empty, parsed: anyContent };
}

/** 计算到店间隔 + 趋势 (纯本地, 不调 AI) */
function computeFacts(
  records: Array<{
    serviceDate: string;
    preCondition: Record<string, unknown>;
    postCondition: Record<string, unknown>;
  }>
): {
  totalVisits: number;
  daysSinceLastVisit: number | null;
  avgIntervalDays: number | null;
  trend: "improving" | "stable" | "worsening" | "unknown";
  dateRange: { from: string; to: string } | null;
} {
  const totalVisits = records.length;
  if (totalVisits === 0) {
    return {
      totalVisits: 0,
      daysSinceLastVisit: null,
      avgIntervalDays: null,
      trend: "unknown",
      dateRange: null,
    };
  }

  // records 按时间 **倒序** 传进来
  const lastDate = new Date(records[0].serviceDate);
  const daysSinceLastVisit = Math.floor(
    (Date.now() - lastDate.getTime()) / (1000 * 60 * 60 * 24)
  );

  // 平均间隔 (相邻到店天数差的均值)
  let avgIntervalDays: number | null = null;
  if (totalVisits >= 2) {
    const asc = [...records].reverse(); // 升序算相邻差
    let sum = 0;
    let n = 0;
    for (let i = 1; i < asc.length; i++) {
      const prev = new Date(asc[i - 1].serviceDate).getTime();
      const cur = new Date(asc[i].serviceDate).getTime();
      const diff = Math.round((cur - prev) / (1000 * 60 * 60 * 24));
      if (diff >= 0) {
        sum += diff;
        n++;
      }
    }
    if (n > 0) avgIntervalDays = Math.round(sum / n);
  }

  // 趋势: 首次 vs 最近 的 pain_level (与 predictions.ts 同口径)
  const asc = [...records].reverse();
  const first = asc[0].preCondition.pain_level as number | undefined;
  const last = asc[asc.length - 1].preCondition.pain_level as number | undefined;
  let trend: "improving" | "stable" | "worsening" | "unknown" = "unknown";
  if (first !== undefined && last !== undefined) {
    if (last < first - 1) trend = "improving";
    else if (last > first + 1) trend = "worsening";
    else trend = "stable";
  }

  const dates = records.map((r) => r.serviceDate).sort();
  return {
    totalVisits,
    daysSinceLastVisit,
    avgIntervalDays,
    trend,
    dateRange: { from: dates[0], to: dates[dates.length - 1] },
  };
}

function safeJsonParseObj(s: string): Record<string, unknown> {
  try {
    const r: unknown = JSON.parse(s);
    return r && typeof r === "object" ? (r as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

function safeJsonParseArr(s: string): string[] {
  try {
    const r: unknown = JSON.parse(s);
    return Array.isArray(r) ? r.map((x) => String(x)) : [];
  } catch {
    return [];
  }
}

export interface GenerateAiInsightOptions {
  /** 跟进理由 (来自行动规则引擎 / 用户下拉选择); 影响 [[话术]] 段 */
  reason?: string;
}

/**
 * 生成客户 AI 洞察 (画像 + 跟进话术 + 效果分析, 一次调用)
 *
 * 返回 null = 客户不存在 (调用方给 404)
 */
export async function generateAiInsight(
  customerId: bigint,
  options: GenerateAiInsightOptions = {}
): Promise<AiInsightResult | null> {
  const reason = options.reason?.trim() || "复购周期提醒";

  // ── 1. 一次读库: 客户 + 最近 20 条养生记录 (含部位) ──
  const [cust] = await db
    .select()
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);

  if (!cust) return null;

  const records = await db
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
    .limit(20);

  // 项目名 + 部位名 批量查 (避免 N+1)
  const serviceIds = Array.from(new Set(records.map((r) => r.serviceItemId)));
  const recordIds = records.map((r) => r.id);
  const [services, allBodyParts, recordBodyPartRows] = await Promise.all([
    serviceIds.length > 0
      ? db.select().from(serviceItem).where(inArray(serviceItem.id, serviceIds))
      : Promise.resolve([] as Array<{ id: bigint; name: string }>),
    db.select().from(bodyPart),
    recordIds.length > 0
      ? db
          .select()
          .from(wellnessRecordBodyPart)
          .where(inArray(wellnessRecordBodyPart.wellnessRecordId, recordIds))
      : Promise.resolve(
          [] as Array<{ wellnessRecordId: bigint; bodyPartId: bigint }>
        ),
  ]);

  const serviceMap = new Map(services.map((s) => [s.id.toString(), s.name]));
  const bodyPartMap = new Map(
    allBodyParts.map((b) => [b.id.toString(), b.name])
  );
  const bodyPartByRecord = new Map<string, string[]>();
  for (const row of recordBodyPartRows) {
    const recId = row.wellnessRecordId.toString();
    if (!bodyPartByRecord.has(recId)) bodyPartByRecord.set(recId, []);
    bodyPartByRecord
      .get(recId)!
      .push(bodyPartMap.get(row.bodyPartId.toString()) ?? `#${row.bodyPartId}`);
  }

  const viewRecords = records.map((r) => ({
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

  // ── 2. 本地算事实 (不烧 AI; 也避免让模型自己算错) ──
  const facts = computeFacts(viewRecords);

  const healthTags = cust.healthTagsEncrypted
    ? safeJsonParseArr(decryptField(cust.healthTagsEncrypted))
    : [];

  // ── 3. **唯一一次** AI 调用 ──
  const { system, prompt } = buildAiInsightPrompt({
    customerName: cust.name,
    gender: cust.gender,
    birthYear: cust.birthYear,
    healthTags,
    diseaseHistory: cust.diseaseHistoryEncrypted
      ? decryptField(cust.diseaseHistoryEncrypted)
      : null,
    notes: cust.notesEncrypted ? decryptField(cust.notesEncrypted) : null,
    daysSinceLastVisit: facts.daysSinceLastVisit,
    avgIntervalDays: facts.avgIntervalDays,
    totalVisits: facts.totalVisits,
    trend: facts.trend,
    reason,
    recentRecords: viewRecords,
  });

  const aiResult = await aiComplete({
    system,
    prompt,
    // 三段合计 400-500 字, 800 给足余量 (截断会让最后一段残缺)
    maxTokens: 1200,
    temperature: 0.6,
  });

  const { sections, parsed } = parseInsightSections(aiResult.text);

  // ── 4. 复购预测: 纯 DB 计算, 不含 AI (所以不算进 aiCallCount) ──
  const repurchase = await predictRepurchase(customerId);

  return {
    customerId: customerId.toString(),
    customerName: cust.name,
    sections: parsed
      ? sections
      : { ...sections, profile: sections.profile || aiResult.text },
    sectionsParsed: parsed,
    repurchase,
    facts: { ...facts, reason },
    aiMock: aiResult.mock,
    model: aiResult.model,
    // P5 不变量: 本函数内只有上面那一次 aiComplete
    aiCallCount: 1,
    usage: aiResult.usage,
  };
}
