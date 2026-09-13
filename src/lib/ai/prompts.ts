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
 * 客户画像 prompt (支持 RAG 知识注入)
 */
export function buildProfilePrompt(
  customer: {
    name: string;
    gender?: string | null;
    birthYear?: number | null;
    healthTags: string[];
    diseaseHistory?: string | null;
    notes?: string | null;
    recentRecords: Array<{
      serviceDate: string;
      serviceItem: string;
      bodyParts: string[];
      preCondition: Record<string, unknown>;
      postCondition: Record<string, unknown>;
      feedback?: string | null;
    }>;
  },
  knowledgeContext: string = ""
): { system: string; prompt: string } {
  const system = `你是一位资深的养生顾问, 服务于养生门店. 你需要根据客户的历史记录和档案, 生成一份专业的客户画像, 帮助销售人员更好地了解客户、提供个性化服务.

输出要求:
1. 简洁专业, 200 字以内
2. 结构化分段: 健康档案 / 服务偏好 / 跟进建议
3. 不要编造不存在的数据
4. 用词温和, 体现养生行业的关怀`;

  const genderMap: Record<string, string> = { M: "男", F: "女", U: "未知" };
  const recentSummary = customer.recentRecords
    .slice(0, 10)
    .map((r) => {
      const pre = Object.entries(r.preCondition)
        .map(([k, v]) => `${k}=${v}`)
        .join(", ");
      const post = Object.entries(r.postCondition)
        .map(([k, v]) => `${k}=${v}`)
        .join(", ");
      return `- ${r.serviceDate} ${r.serviceItem} (${r.bodyParts.join("/")})
  理疗前: ${pre || "无"}
  理疗后: ${post || "无"}
  ${r.feedback ? `反馈: ${r.feedback}` : ""}`;
    })
    .join("\n");

  const knowledgeSection = knowledgeContext
    ? `\n## 养生知识参考 (可参考, 不要照搬)\n${knowledgeContext}\n`
    : "";

  const prompt = `请为以下客户生成客户画像:

客户基本信息:
- 姓名: ${customer.name}
- 性别: ${genderMap[customer.gender ?? "U"] ?? "未知"}
- 出生年: ${customer.birthYear ?? "未知"}
- 健康标签: ${customer.healthTags.join(", ") || "无"}
- 既往病史: ${customer.diseaseHistory || "无"}
- 备注: ${customer.notes || "无"}

最近养生记录 (${customer.recentRecords.length} 条):
${recentSummary || "暂无记录"}
${knowledgeSection}
请生成客户画像.`;

  return { system, prompt };
}

/**
 * 跟进话术生成 prompt (支持 RAG 知识注入)
 */
export function buildFollowUpPrompt(
  input: {
    customerName: string;
    customerProfile: string;
    lastVisit: string | null;
    daysSinceLastVisit: number | null;
    avgInterval: number | null;
    reason: string;
    aiSuggestion?: string | null;
  },
  knowledgeContext: string = ""
): { system: string; prompt: string } {
  const system = `你是一位经验丰富的养生销售顾问. 你需要根据客户的画像和最近跟进情况, 生成一段贴心且专业的跟进话术, 用于销售通过微信或电话与客户联系.

输出要求:
1. 语气亲切, 像朋友聊天 (不要像机器人)
2. 字数 100-200 字
3. 包含 3 部分: 开场关心 → 推荐切入 → 预约引导
4. 体现关怀而非推销
5. 如客户有明确健康问题, 主动询问改善情况`;

  const knowledgeSection = knowledgeContext
    ? `\n## 养生知识参考 (可参考, 不要照搬)\n${knowledgeContext}\n`
    : "";

  const prompt = `为以下客户生成跟进话术:

【客户画像】
${input.customerProfile}

【跟进情境】
- 客户姓名: ${input.customerName}
- 上次到店: ${input.lastVisit ?? "无记录"}
- 距上次到店: ${input.daysSinceLastVisit ?? "未知"} 天
- 平均复购周期: ${input.avgInterval ?? "未知"} 天
- 跟进原因: ${input.reason}
${input.aiSuggestion ? `- 之前 AI 建议: ${input.aiSuggestion}` : ""}
${knowledgeSection}
请生成一段跟进话术, 包含开场 + 推荐 + 预约 3 部分.`;

  return { system, prompt };
}

/**
 * 治疗效果分析 prompt (支持 RAG 知识注入)
 */
export function buildEffectAnalysisPrompt(
  input: {
    customerName: string;
    records: Array<{
      serviceDate: string;
      serviceItem: string;
      preCondition: Record<string, unknown>;
      postCondition: Record<string, unknown>;
      feedback?: string | null;
    }>;
  },
  knowledgeContext: string = ""
): { system: string; prompt: string } {
  const system = `你是一位专业的养生效果评估师. 你需要基于客户的多次理疗记录, 分析治疗效果, 给出后续建议.

输出要求:
1. 简明扼要, 200 字以内
2. 包含: 趋势判断 / 改善幅度 / 后续建议
3. 数据驱动 (引用具体数字)`;

  const summary = input.records
    .map((r, idx) => {
      const pre = JSON.stringify(r.preCondition);
      const post = JSON.stringify(r.postCondition);
      return `第 ${idx + 1} 次 (${r.serviceDate}) - ${r.serviceItem}
  理疗前: ${pre}
  理疗后: ${post}
  反馈: ${r.feedback ?? "无"}`;
    })
    .join("\n");

  const knowledgeSection = knowledgeContext
    ? `\n## 养生知识参考 (可参考, 不要照搬)\n${knowledgeContext}\n`
    : "";

  const prompt = `分析 ${input.customerName} 的治疗效果:

${summary}
${knowledgeSection}
请生成效果分析报告.`;

  return { system, prompt };
}