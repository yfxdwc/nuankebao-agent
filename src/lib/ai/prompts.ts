// ============================================
// AI Prompt 模板 (with RAG 知识库集成)
// 借鉴 NocoBase AI Builder + LangChain LCEL 思路
//
// 设计原则:
// - 中文语境 (养生行业)
// - 结构化输入 (客户档案 + 历史记录)
// - 输出可控 (限字数, 结构化字段)
// - 注入角色定位 ("你是养生顾问...")
// - 支持 RAG 知识注入 (knowledgeContext 可选)
// ============================================

/**
 * 合并版「AI 洞察」prompt (P5, 主人 2026-09-23 拍)
 *
 * 背景: 原先客户详情页 AI 区是 3 张卡各发一次请求 (画像 / 话术 / 效果分析),
 *   3 次 MiniMax 调用 —— 同一位客户的基本信息 + 养生记录被**重复喂了 3 遍**,
 *   既不省钱, 也让三段内容互相看不见 (话术不知道效果趋势, 效果分析不知道画像)。
 *   合并成 1 次: system 只发一遍 (省 token), 且模型能一次看全貌 → 三段更连贯。
 *
 * 为什么用 `[[画像]]` 这种分隔符而不是 JSON:
 *   - 模型输出 JSON 时容易漂 (截断 / 多余解释 / 中文引号), 解析失败就丢内容;
 *   - 分隔符方案**永远不会丢内容** —— 解析不出也只影响分段, 全文仍在。
 *   解析器见 `parseInsightSections`, 失败时 `sectionsParsed=false` 且全文落在 profile。
 */
export const INSIGHT_SECTIONS = ["profile", "followUp", "effect"] as const;
export type InsightSectionKey = (typeof INSIGHT_SECTIONS)[number];

/** 分隔符 (与 prompt 里要求的一字不差; 解析器按这三个切) */
export const INSIGHT_DELIMITERS: Record<InsightSectionKey, string> = {
  profile: "[[画像]]",
  followUp: "[[话术]]",
  effect: "[[效果]]",
};

export interface AiInsightPromptInput {
  customerName: string;
  gender?: string | null;
  birthYear?: number | null;
  healthTags: string[];
  diseaseHistory?: string | null;
  notes?: string | null;
  /** 已算好的事实 (不含 AI 判断) —— 让模型少算错 */
  daysSinceLastVisit: number | null;
  avgIntervalDays: number | null;
  totalVisits: number;
  trend: "improving" | "stable" | "worsening" | "unknown";
  /** 跟进情境 (来自行动规则引擎 / 用户选的跟进理由) */
  reason: string;
  recentRecords: Array<{
    serviceDate: string;
    serviceItem: string;
    bodyParts: string[];
    preCondition: Record<string, unknown>;
    postCondition: Record<string, unknown>;
    feedback?: string | null;
  }>;
}

/**
 * 一次调用产出三段内容 (画像 / 跟进话术 / 效果分析)
 */
export function buildAiInsightPrompt(
  input: AiInsightPromptInput,
  knowledgeContext: string = ""
): { system: string; prompt: string } {
  const system = `你是一位资深的养生门店顾问, 同时具备销售跟进与效果评估经验。
你要在一份回复里, 为同一位客户产出**三段**内容, 分别用指定分隔符开头。

输出格式 (严格遵守, 分隔符必须独占一行):
${INSIGHT_DELIMITERS.profile}
(客户画像)
${INSIGHT_DELIMITERS.followUp}
(跟进话术)
${INSIGHT_DELIMITERS.effect}
(效果分析)

各段要求:
1. [[画像]] 客户画像: 150 字以内。包含健康档案 / 服务偏好 / 跟进要点三小块。
2. [[话术]] 跟进话术: 100-200 字, 语气像朋友聊天不像机器人, 含 开场关心 → 推荐切入 → 预约引导。
   写第二人称 (对她说话), 可以直接复制发给客户。
3. [[效果]] 效果分析: 150 字以内, 趋势判断 / 改善幅度 / 后续建议, 引用具体数字。

通用要求:
- 三段要**互相呼应** (话术可以参考效果趋势来关心; 效果分析可以参考画像里的健康标签)
- 只依据给出的数据, **不要编造**没有的信息; 数据不足就直说数据不足
- 不做医疗诊断, 不给治疗方案; 只做养生服务的描述性总结与关怀建议
- 不要输出除这三段以外的任何内容 (不要开场白 / 不要结尾总结)`;

  const genderMap: Record<string, string> = { M: "男", F: "女", U: "未知" };

  const recentSummary = input.recentRecords
    .slice(0, 10)
    .map((r) => {
      const pre = Object.entries(r.preCondition)
        .map(([k, v]) => `${k}=${v}`)
        .join(", ");
      const post = Object.entries(r.postCondition)
        .map(([k, v]) => `${k}=${v}`)
        .join(", ");
      return `- ${r.serviceDate} ${r.serviceItem} (${r.bodyParts.join("/") || "未记部位"})
  理疗前: ${pre || "无"}
  理疗后: ${post || "无"}
  ${r.feedback ? `反馈: ${r.feedback}` : ""}`;
    })
    .join("\n");

  const knowledgeSection = knowledgeContext
    ? `\n## 养生知识参考 (可参考, 不要照搬)\n${knowledgeContext}\n`
    : "";

  const trendLabel: Record<string, string> = {
    improving: "改善中",
    stable: "基本持平",
    worsening: "有加重迹象",
    unknown: "数据不足无法判断",
  };

  const prompt = `请为以下客户产出三段内容:

客户基本信息:
- 姓名: ${input.customerName}
- 性别: ${genderMap[input.gender ?? "U"] ?? "未知"}
- 出生年: ${input.birthYear ?? "未知"}
- 健康标签: ${input.healthTags.join(", ") || "无"}
- 既往病史: ${input.diseaseHistory || "无"}
- 备注: ${input.notes || "无"}

已算好的事实 (直接用, 不要自己重算):
- 累计到店: ${input.totalVisits} 次
- 距上次到店: ${input.daysSinceLastVisit ?? "无记录"} ${input.daysSinceLastVisit != null ? "天" : ""}
- 平均复购周期: ${input.avgIntervalDays ?? "样本不足"} ${input.avgIntervalDays != null ? "天" : ""}
- 疼痛趋势 (首次 vs 最近): ${trendLabel[input.trend] ?? input.trend}
- 本次跟进原因: ${input.reason}

最近养生记录 (${input.recentRecords.length} 条, 按时间倒序):
${recentSummary || "暂无记录"}
${knowledgeSection}
现在请按格式输出三段内容。`;

  return { system, prompt };
}
