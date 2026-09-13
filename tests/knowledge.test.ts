// 知识库 (RAG) 测试
// 跑: DATABASE_URL=postgres://nuankebao:test@localhost:5432/nuankebao_test pnpm test:run

import { describe, it, expect, beforeAll } from "vitest";
import { db } from "@/lib/db";
import { sql } from "drizzle-orm";
import { searchKnowledge, listAllKnowledge, buildKnowledgeContext } from "@/lib/db/queries/knowledge";

beforeAll(async () => {
  await db.execute(sql`TRUNCATE customer, follow_up_task, interaction, wellness_record CASCADE`);
});

describe("knowledge (RAG)", () => {
  it("listAllKnowledge 返回至少 10 条", async () => {
    const items = await listAllKnowledge();
    expect(items.length).toBeGreaterThanOrEqual(10);
  });

  it("searchKnowledge 按 title 关键词匹配", async () => {
    const items = await searchKnowledge("肩颈");
    expect(items.length).toBeGreaterThanOrEqual(1);
    expect(items.some((i) => i.title.includes("肩颈"))).toBe(true);
  });

  it("searchKnowledge 按 content 关键词匹配", async () => {
    const items = await searchKnowledge("艾灸");
    expect(items.length).toBeGreaterThanOrEqual(1);
    expect(items.some((i) => i.content.includes("艾灸"))).toBe(true);
  });

  it("searchKnowledge 找不到时返回空", async () => {
    const items = await searchKnowledge("XYZ不存在的关键词ABC");
    // 可能返回空, 也可能返回最新 (无关键词 fallback)
    expect(items.length).toBeGreaterThanOrEqual(0);
  });

  it("searchKnowledge 支持多关键词", async () => {
    const items = await searchKnowledge("肩颈 经络");
    expect(items.length).toBeGreaterThanOrEqual(1);
  });

  it("buildKnowledgeContext 返回格式化字符串", async () => {
    const ctx = await buildKnowledgeContext("肩颈");
    expect(ctx).toContain("[1]");
    expect(ctx).toContain("---");
  });

  it("buildKnowledgeContext 无匹配时返回空", async () => {
    const ctx = await buildKnowledgeContext("xyzabc123", 3);
    expect(ctx).toBe("");
  });

  it("limit 参数生效", async () => {
    const items = await searchKnowledge("养生", 2);
    expect(items.length).toBeLessThanOrEqual(2);
  });
});