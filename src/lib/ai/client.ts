// ============================================
// MiniMax AI 客户端封装
//
// 有 MINIMAX_API_KEY 时用真实 API; 没 key / 调用失败 → mock 模板
//
// ⚙️ 实现变更 (2026-09-18, 主人拍客户详情页要真 AI):
//   旧实现用 `@ai-sdk/minimax` + `ai@3.4.0` 的 `generateText()` —— 实测**静默返回空文本**
//   (`text=""` + `finishReason: stop` + usage 全 null), 不报错 → 客户画像/效果分析/跟进话术
//   三个卡片全是空白。根因: provider 包 (`latest`) 与 ai 核心 v3.4 的协议不匹配。
//   现改为**直连 MiniMax 的 Anthropic 兼容端点** (POST {base}/messages) —— 同一把 key,
//   跟官方文档一致, 不依赖 SDK 版本; 响应缺字段/报错仍回退 mock (不会把页面搞白)。
//
// 详见 docs/references.md §4 + docs/adr/0001-tech-stack.md
// ============================================

export interface AIMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export interface AICompletionOptions {
  system?: string;
  prompt: string;
  maxTokens?: number;
  temperature?: number;
}

export interface AICompletionResult {
  text: string;
  mock: boolean; // true = 用了 mock
  model: string;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

/** 拼接 Anthropic 兼容端点: base 可能带/不带 /v1 → 都归一化到 /v1/messages */
function messagesEndpoint(base: string): string {
  const trimmed = base.replace(/\/+$/, "");
  const withV1 = /\/v1$/.test(trimmed) ? trimmed : `${trimmed}/v1`;
  return `${withV1}/messages`;
}

/** 是否配了可用的 key (长度太短视为占位) */
export function isAIConfigured(): boolean {
  const apiKey = process.env.MINIMAX_API_KEY;
  return !!apiKey && apiKey.length >= 10;
}

interface AnthropicMessagesResponse {
  content?: Array<{ type?: string; text?: string }>;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
  };
  base_resp?: { status_code?: number; status_msg?: string };
  error?: { message?: string; type?: string };
}

/**
 * AI 文本生成 (主入口)
 */
export async function aiComplete(
  options: AICompletionOptions
): Promise<AICompletionResult> {
  const modelName = process.env.MINIMAX_MODEL || "MiniMax-M3";

  if (!isAIConfigured()) {
    return { text: mockCompletion(options), mock: true, model: `${modelName} (mock)` };
  }

  const base = process.env.MINIMAX_API_BASE || "https://api.minimaxi.com/anthropic";
  try {
    const res = await fetch(messagesEndpoint(base), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": process.env.MINIMAX_API_KEY!, // Anthropic 风格鉴权头
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: modelName,
        max_tokens: options.maxTokens ?? 500,
        temperature: options.temperature ?? 0.7,
        ...(options.system ? { system: options.system } : {}),
        messages: [{ role: "user", content: options.prompt }],
      }),
      // AI 生成慢: 给 60s (图片/大段文本也可能久)
      signal: AbortSignal.timeout(60_000),
    });

    const data = (await res.json()) as AnthropicMessagesResponse;

    if (!res.ok || data.error) {
      console.error(
        "[ai] MiniMax API 报错:",
        res.status,
        data.error?.message ?? data.base_resp?.status_msg
      );
      return {
        text: mockCompletion(options),
        mock: true,
        model: `${modelName} (error-fallback)`,
      };
    }

    const text = (data.content ?? [])
      .filter((b) => b.type === "text" && b.text)
      .map((b) => b.text)
      .join("")
      .trim();

    // 空文本也算失败 (2026-09-18 的 bu�� 就是这个: 不报错但没内容)
    if (!text) {
      console.error("[ai] MiniMax 返回空文本, 走 mock", JSON.stringify(data).slice(0, 300));
      return {
        text: mockCompletion(options),
        mock: true,
        model: `${modelName} (empty-fallback)`,
      };
    }

    const inTok = data.usage?.input_tokens;
    const outTok = data.usage?.output_tokens;
    return {
      text,
      mock: false,
      model: modelName,
      usage:
        inTok != null && outTok != null
          ? {
              promptTokens: inTok,
              completionTokens: outTok,
              totalTokens: inTok + outTok,
            }
          : undefined,
    };
  } catch (error) {
    console.error("[ai] MiniMax API 调用失败, fallback mock:", error);
    return {
      text: mockCompletion(options),
      mock: true,
      model: `${modelName} (error-fallback)`,
    };
  }
}

/**
 * Mock 模板 (开发/测试用)
 * 基于 prompt 关键字返回合理模板
 */
function mockCompletion(options: AICompletionOptions): string {
  const prompt = options.prompt.toLowerCase();

  if (prompt.includes("客户画像") || prompt.includes("customer profile")) {
    return `【客户画像 - Mock 数据】

📊 健康档案
- 主要健康问题: 肩颈僵硬, 睡眠质量差
- 既往病史: 无重大疾病
- 健康标签: 肩颈 / 睡眠差 / 体寒

🛍 服务偏好
- 最常做项目: 肩颈经络理疗 (4 次/3 个月)
- 偏好技师: 王技师
- 消费水平: 中等

⏰ 跟进建议
- 距上次到店: 已 28 天
- 复购周期: 平均 30-45 天
- 推荐下次到店: 本周内

💬 推荐话术
"张女士, 上次做完肩颈之后您说睡眠改善挺明显的, 这段时间肩颈有没有又开始紧? 这次有新的艾灸套餐, 要不要预约试试?"

(注: 这是 mock 数据, 配置 MINIMAX_API_KEY 后将使用真实 AI)`;
  }

  if (prompt.includes("跟进") || prompt.includes("follow")) {
    return `【跟进话术 - Mock 数据】

📞 微信开场 (推荐)
"张姐, 下午好! 距离您上次做肩颈理疗已经 28 天了, 您最近肩颈情况怎么样? 睡眠有改善吗? 我们这边有个新的艾灸调理套餐, 对改善睡眠和肩颈疲劳很有效, 您看要不要预约这周过来体验一下?"

🎯 切入点
1. 关心上次效果 (主推)
2. 介绍新项目 (次推)
3. 节日/天气关怀 (备用)

⏰ 最佳联系时间
- 工作日: 10:00-11:30, 14:00-16:30
- 周末: 10:00-12:00

⚠️ 注意事项
- 不要直接推销, 先关心效果
- 如客户表示没空, 可约下周再联系
- 提及复购项目时强调"体验" 而非"购买"

(注: 这是 mock 数据, 配置 MINIMAX_API_KEY 后将使用真实 AI)`;
  }

  if (prompt.includes("效果分析") || prompt.includes("treatment")) {
    return `【效果分析 - Mock 数据】

📈 治疗趋势
- 过去 3 次到店: 疼痛度从 8/10 → 6/10 → 4/10 (持续改善)
- 睡眠质量: 5/10 → 7/10 (改善 40%)
- 客户主观反馈: "肩膀轻多了, 睡眠也好了一些"

✅ 治疗有效, 建议
1. 继续当前项目 (肩颈经络理疗)
2. 加做 1-2 次艾灸调理, 巩固效果
3. 引导客户办套餐卡 (提升客户粘性)

(注: 这是 mock 数据)`;
  }

  return `【AI Mock 回复】

这是一个 mock 回复, 因为没有配置 MINIMAX_API_KEY 环境变量.

配置方法:
1. 在 .env.local 添加: MINIMAX_API_KEY=<your-key>
2. 重启 dev server
3. AI 将返回真实生成的内容

(原始 prompt: ${options.prompt.slice(0, 50)}...)`;
}

/**
 * 简单的文本生成 (聊天补全模式)
 */
export async function aiChat(messages: AIMessage[]): Promise<string> {
  const system = messages.find((m) => m.role === "system")?.content;
  const userMsg = messages.find((m) => m.role === "user")?.content ?? "";

  const result = await aiComplete({
    system,
    prompt: userMsg,
  });
  return result.text;
}

/**
 * 检查 AI 是否可用 (API key 配置)
 */
export function isAIEnabled(): boolean {
  return isAIConfigured();
}