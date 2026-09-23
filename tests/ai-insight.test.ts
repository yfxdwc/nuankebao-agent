// ============================================
// AI 洞察 (P5 合并调用) 单测
// ============================================
// 守护的东西:
//   ① **P5 的核心承诺**: 三段内容只花 **1 次** AI 调用 (aiCallCount === 1)
//      —— 防止后人"顺手再加一个 aiComplete"把收益悄悄改回去
//   ② 分隔符解析**永远不丢内容** (模型不按格式输出时, 全文仍在)
//   ③ prompt 与解析器用同一套分隔符 (常量同源, 改一处不会两边不一致)
//   ④ 复购预测是本地算的, 不该因为它多一次 AI 调用
//
// 跑: pnpm test:run tests/ai-insight.test.ts

import { describe, it, expect, beforeAll } from "vitest";
import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import { encryptField } from "@/lib/crypto/field";
import { createHash } from "node:crypto";
import {
  parseInsightSections,
  generateAiInsight,
} from "@/lib/ai/insight";
import {
  INSIGHT_SECTIONS,
  INSIGHT_DELIMITERS,
  buildAiInsightPrompt,
} from "@/lib/ai/prompts";

describe("parseInsightSections", () => {
  it("标准三分段: 按分隔符切出三段且各自 trim", () => {
    const raw = `${INSIGHT_DELIMITERS.profile}
  画像内容
${INSIGHT_DELIMITERS.followUp}
话术内容
${INSIGHT_DELIMITERS.effect}
效果内容`;

    const { sections, parsed } = parseInsightSections(raw);
    expect(parsed).toBe(true);
    expect(sections.profile).toBe("画像内容");
    expect(sections.followUp).toBe("话术内容");
    expect(sections.effect).toBe("效果内容");
  });

  it("模型多写开场白 → 开场白被丢弃, 三段仍正确", () => {
    const raw = `好的, 我来为您分析这位客户。
${INSIGHT_DELIMITERS.profile}
画像
${INSIGHT_DELIMITERS.followUp}
话术
${INSIGHT_DELIMITERS.effect}
效果`;

    const { sections, parsed } = parseInsightSections(raw);
    expect(parsed).toBe(true);
    expect(sections.profile).toBe("画像");
    // 开场白不该混进任何一段
    expect(Object.values(sections).join("")).not.toContain("好的, 我来为您分析");
  });

  it("缺一段 → 缺的那段为空串, 其余正常 (不整体失败)", () => {
    const raw = `${INSIGHT_DELIMITERS.profile}
画像
${INSIGHT_DELIMITERS.effect}
效果`;

    const { sections, parsed } = parseInsightSections(raw);
    expect(parsed).toBe(true);
    expect(sections.profile).toBe("画像");
    expect(sections.followUp).toBe("");
    expect(sections.effect).toBe("效果");
  });

  it("完全没有分隔符 → parsed=false, 但**全文落进 profile** (绝不丢内容)", () => {
    const raw = "模型今天不听话, 直接输出了一大段没有格式的内容。";

    const { sections, parsed } = parseInsightSections(raw);
    expect(parsed).toBe(false);
    expect(sections.profile).toBe(raw);
    expect(sections.followUp).toBe("");
    expect(sections.effect).toBe("");
  });

  it("空字符串 → parsed=false 且三段全空 (不抛异常)", () => {
    const { sections, parsed } = parseInsightSections("");
    expect(parsed).toBe(false);
    expect(INSIGHT_SECTIONS.every((k) => sections[k] === "")).toBe(true);
  });

  it("同一分隔符重复出现 → 保留第一次有内容的那段", () => {
    const raw = `${INSIGHT_DELIMITERS.profile}
第一版画像
${INSIGHT_DELIMITERS.profile}
重复的画像
${INSIGHT_DELIMITERS.followUp}
话术`;

    const { sections } = parseInsightSections(raw);
    expect(sections.profile).toBe("第一版画像");
    expect(sections.followUp).toBe("话术");
  });

  it("分隔符顺序颠倒 → 按实际位置取, 不按 prompt 声明的顺序", () => {
    const raw = `${INSIGHT_DELIMITERS.effect}
先给效果
${INSIGHT_DELIMITERS.profile}
再给画像`;

    const { sections } = parseInsightSections(raw);
    expect(sections.effect).toBe("先给效果");
    expect(sections.profile).toBe("再给画像");
  });

  it("分隔符嵌在段落中间 (非行首) 不算切点", () => {
    const raw = `${INSIGHT_DELIMITERS.profile}
画像里提到 [[话术]] 这个词, 但这不是切点
${INSIGHT_DELIMITERS.followUp}
话术`;
    const { sections } = parseInsightSections(raw);
    expect(sections.profile).toContain("不是切点");
    expect(sections.followUp).toBe("话术");
  });

  it("只有分隔符没有内容 → parsed=false (空壳不算解析成功)", () => {
    const raw = `${INSIGHT_DELIMITERS.profile}
${INSIGHT_DELIMITERS.followUp}
${INSIGHT_DELIMITERS.effect}`;
    const { parsed } = parseInsightSections(raw);
    expect(parsed).toBe(false);
  });
});

describe("buildAiInsightPrompt (prompt 与解析器同源)", () => {
  const baseInput = {
    customerName: "王女士",
    gender: "F",
    birthYear: 1985,
    healthTags: ["肩颈", "睡眠差"],
    diseaseHistory: null,
    notes: null,
    daysSinceLastVisit: 28,
    avgIntervalDays: 35,
    totalVisits: 6,
    trend: "improving" as const,
    reason: "复购周期提醒",
    recentRecords: [
      {
        serviceDate: "2026-09-01",
        serviceItem: "肩颈经络理疗",
        bodyParts: ["肩颈"],
        preCondition: { pain_level: 6 },
        postCondition: { pain_level: 3 },
        feedback: "舒服多了",
      },
    ],
  };

  it("三个分隔符都出现在 prompt 里 (模型才知道要按它输出)", () => {
    const { system, prompt } = buildAiInsightPrompt(baseInput);
    for (const key of INSIGHT_SECTIONS) {
      expect(system).toContain(INSIGHT_DELIMITERS[key]);
    }
    expect(prompt).toContain("王女士");
    expect(prompt).toContain("肩颈经络理疗");
  });

  it("已算好的事实直接给模型 (不让它自己算错)", () => {
    const { prompt } = buildAiInsightPrompt(baseInput);
    expect(prompt).toContain("28");
    expect(prompt).toContain("35");
    expect(prompt).toContain("6");
    expect(prompt).toContain("改善中");
  });

  it("没有任何养生记录也能构造 prompt (不抛异常)", () => {
    const { prompt } = buildAiInsightPrompt({
      ...baseInput,
      daysSinceLastVisit: null,
      avgIntervalDays: null,
      totalVisits: 0,
      trend: "unknown",
      recentRecords: [],
    });
    expect(prompt).toContain("暂无记录");
  });

  it("医学红线: system 明确要求不做诊断 / 不给治疗方案", () => {
    const { system } = buildAiInsightPrompt(baseInput);
    expect(system).toContain("不做医疗诊断");
  });
});

// ============================================
// 真库集成 (setup.ts 已强制 MINIMAX_API_KEY="" → 走 mock)
// ============================================
describe("generateAiInsight (集成, mock 模式)", () => {
  let customerId: bigint;

  beforeAll(async () => {
    // ⚠ 手机号每次全新: 测试库不清库, 固定号码第二次跑本文件就撞 phoneHash 唯一索引
    const phone = `139${String(Date.now() % 100000000).padStart(8, "0")}9`;
    const phoneHash = createHash("sha256").update(phone).digest("hex");
    const [row] = await db
      .insert(customer)
      .values({
        name: "AI洞察测试客户",
        phoneEncrypted: encryptField(phone),
        phoneHash,
        createdBy: 1,
        healthTagsEncrypted: encryptField(JSON.stringify(["肩颈", "睡眠差"])),
      })
      .returning();
    customerId = row.id;
  });

  it("⚠ P5 不变量: 三段内容只花 1 次 AI 调用", async () => {
    const result = await generateAiInsight(customerId);
    expect(result).not.toBeNull();
    expect(result!.aiCallCount).toBe(1);
  });

  it("mock 模式下分段解析成功, 三段都有内容", async () => {
    const result = await generateAiInsight(customerId);
    expect(result!.aiMock).toBe(true);
    expect(result!.sectionsParsed).toBe(true);
    for (const key of INSIGHT_SECTIONS) {
      expect(result!.sections[key].length).toBeGreaterThan(0);
    }
  });

  it("复购预测一起返回, 但不另算 AI 调用", async () => {
    const result = await generateAiInsight(customerId);
    expect(result!.repurchase).not.toBeNull();
    // 关键: 复购预测是纯 DB 计算, 加上它之后总调用次数**仍是 1**
    expect(result!.aiCallCount).toBe(1);
  });

  it("事实底稿结构化返回 (客户端可展示依据)", async () => {
    const result = await generateAiInsight(customerId, { reason: "好久没来了" });
    expect(result!.facts.reason).toBe("好久没来了");
    expect(result!.facts.totalVisits).toBe(0); // 新客户没记录
    expect(result!.facts.trend).toBe("unknown");
  });

  it("客户不存在 → null (调用方据此给 404)", async () => {
    const result = await generateAiInsight(BigInt("999999999"));
    expect(result).toBeNull();
  });
});
