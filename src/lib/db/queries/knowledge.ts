import { db } from "@/lib/db";
import { wellnessKnowledge, type WellnessKnowledge } from "@/lib/db/schema";
import { eq, sql, or, ilike } from "drizzle-orm";

// ============================================
// 养生知识库 (RAG 数据源)
// W9 Phase 2 AI 增强
// ============================================

/**
 * 简单关键词检索 (无 embedding)
 * 匹配 title / content / tags
 * 后期可升级 pgvector (W10 计划)
 */
export async function searchKnowledge(
  query: string,
  limit: number = 3
): Promise<WellnessKnowledge[]> {
  if (!query.trim()) return [];

  // 提取关键词 (中文按字符, 简单拆分)
  const keywords = query
    .replace(/[，。！？、；：""''《》()（）\s,.\?!;:"""''()]/g, " ")
    .split(/\s+/)
    .filter((k) => k.length >= 2)
    .slice(0, 5);

  if (keywords.length === 0) {
    // 没关键词, 返回全部最新
    return await db
      .select()
      .from(wellnessKnowledge)
      .orderBy(sql`${wellnessKnowledge.createdAt} DESC`)
      .limit(limit);
  }

  // OR 匹配多个关键词
  const conditions = keywords.map(
    (kw) =>
      or(
        ilike(wellnessKnowledge.title, `%${kw}%`),
        ilike(wellnessKnowledge.content, `%${kw}%`),
        sql`${wellnessKnowledge.tags}::text ILIKE ${'%' + kw + '%'}`
      )!
  );

  return await db
    .select()
    .from(wellnessKnowledge)
    .where(or(...conditions)!)
    .limit(limit);
}

/**
 * 按 category 查所有
 */
export async function listKnowledgeByCategory(
  category: "physiotherapy" | "wellness_tip" | "product_guide" | "customer_care" | "seasonal"
): Promise<WellnessKnowledge[]> {
  return await db
    .select()
    .from(wellnessKnowledge)
    .where(eq(wellnessKnowledge.category, category))
    .limit(10);
}

/**
 * 取所有知识 (admin 用)
 */
export async function listAllKnowledge(limit: number = 50): Promise<WellnessKnowledge[]> {
  return await db
    .select()
    .from(wellnessKnowledge)
    .orderBy(sql`${wellnessKnowledge.createdAt} DESC`)
    .limit(limit);
}

/**
 * 搜索并格式化为 AI prompt 上下文
 */
export async function buildKnowledgeContext(
  query: string,
  limit: number = 3
): Promise<string> {
  const items = await searchKnowledge(query, limit);
  if (items.length === 0) return "";

  return items
    .map(
      (item, i) =>
        `[${i + 1}] ${item.title}\n${item.content}\n`
    )
    .join("\n---\n");
}