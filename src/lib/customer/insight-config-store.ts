// ============================================
// 客户洞察参数: DB 覆盖层 (admin 调节页的后端)
// ============================================
// 主人 2026-09-23 拍: 「让评分规则及其他客户管理中的参数可在管理页面进行调节」
//
// 三层结构 (自下而上):
//   ① DEFAULT_INSIGHT_CONFIG        代码里的默认值 (唯一真相源)
//   ② app_config['customer.insight'] DB 覆盖值 (只放与默认不同的部分)
//   ③ resolveInsightConfig(②)       逐字段合并 + 夹区间 → 生效配置
//
// 为什么"夹区间"这么重要:
//   DB 里的值来自 HTTP 请求体 (不受信)。admin 手滑填 -1 / 1e9 / "abc" 都可能,
//   而评分是**全店**共用的 —— 一个越界权重能让所有人的分数失真。
//   resolveInsightConfig 已经为每个字段定好上下界 (见 insight-config.ts),
//   所以写入路径可以放心把原始值交给它, 存进去的也是**夹过**的值 (不是用户原样输入)。
//
// 版本号 (scoring.version / actions.version):
//   保存时**只在配置真的变了**才 +1。理由: 详情页要靠版本变化提示"评分规则已更新,
//   分数可能变化"。如果没变也 +1, 用户会收到无意义的提示。
// ============================================

import {
  DEFAULT_INSIGHT_CONFIG,
  resolveInsightConfig,
  type InsightConfig,
} from "@/lib/customer/insight-config";
import { APP_CONFIG_KEYS } from "@/lib/config/app-config";
import {
  getAppConfigRecord,
  setAppConfigValue,
  deleteAppConfigValue,
} from "@/lib/config/app-config";
import type { AuditContext } from "@/lib/audit/context";

export const INSIGHT_CONFIG_KEY = APP_CONFIG_KEYS.CUSTOMER_INSIGHT;

/** admin 页要展示的完整视图 */
export interface InsightConfigView {
  /** 生效配置 (默认 ⊕ 覆盖, 已夹区间) */
  config: InsightConfig;
  /** 只读参考: 代码里的默认值 */
  defaults: InsightConfig;
  /** DB 里那条原始覆盖 (null = 没覆盖, 全用默认) */
  override: unknown | null;
  /** 是否被改过 (admin 页显示"已自定义" / "使用默认") */
  isCustomized: boolean;
  updatedBy: string | null;
  updatedAt: string | null;
}

/** 取生效配置 (评分/行动调用方用这个; 出异常也**不抛** —— 回落默认) */
export async function getEffectiveInsightConfig(): Promise<InsightConfig> {
  try {
    const override = await getAppConfigValueSafe();
    return resolveInsightConfig(override);
  } catch {
    // 读配置失败 (DB 抖动 / 表还没建) 不该让客户详情页打不开 —— 回落默认
    return resolveInsightConfig(undefined);
  }
}

async function getAppConfigValueSafe(): Promise<unknown | undefined> {
  const rec = await getAppConfigRecord(INSIGHT_CONFIG_KEY);
  return rec?.value;
}

/** admin 页读取: 生效值 + 默认值 + 覆盖原文 + 元信息 */
export async function getInsightConfigView(): Promise<InsightConfigView> {
  const rec = await getAppConfigRecord(INSIGHT_CONFIG_KEY);
  return {
    config: resolveInsightConfig(rec?.value),
    defaults: DEFAULT_INSIGHT_CONFIG,
    override: rec?.value ?? null,
    isCustomized: rec != null,
    updatedBy: rec?.updatedBy?.toString() ?? null,
    updatedAt: rec?.updatedAt?.toISOString() ?? null,
  };
}

/**
 * 保存覆盖值
 *
 * @param input 原始输入 (不受信) —— 会被 resolveInsightConfig 夹过再存
 * @returns 保存后的视图 + `versionBumped` (这次是否真的改了配置)
 */
export async function saveInsightConfig(
  input: unknown,
  ctx: AuditContext
): Promise<InsightConfigView & { versionBumped: boolean }> {
  const before = await getInsightConfigView();
  const resolved = resolveInsightConfig(input);

  // 只有"配置内容真的变了"才推进版本号 (否则详情页会发无意义的"规则已更新")
  const changed = !configsEqual(before.config, resolved);
  // ⚠ 版本号**不能从提交的 payload 里取**: 客户端通常根本不传 version,
  //   `resolveInsightConfig` 会回落默认 "v1" → 第二次保存同样内容会把版本
  //   从 v2 退回 v1 (踩过)。规则: 变了就 +1, 没变就保留当前值。
  const next: InsightConfig = {
    scoring: {
      ...resolved.scoring,
      version: changed
        ? bumpVersion(before.config.scoring.version)
        : before.config.scoring.version,
    },
    actions: {
      ...resolved.actions,
      version: changed
        ? bumpVersion(before.config.actions.version)
        : before.config.actions.version,
    },
  };

  await setAppConfigValue(
    INSIGHT_CONFIG_KEY,
    next,
    ctx,
    "客户洞察可调参数 (评分 3 维 + 行动 9 条规则 + 阈值)"
  );

  return { ...(await getInsightConfigView()), versionBumped: changed };
}

/** 重置为默认 = 删掉覆盖行 (回落代码里的 DEFAULT_INSIGHT_CONFIG) */
export async function resetInsightConfig(
  ctx: AuditContext
): Promise<InsightConfigView & { deleted: boolean }> {
  const deleted = await deleteAppConfigValue(INSIGHT_CONFIG_KEY, ctx);
  return { ...(await getInsightConfigView()), deleted };
}

/**
 * 版本号 +1: "v1" → "v2"
 *
 * 非法格式 (空/非 v<数字>) 一律退回 v2 —— 不能因为历史脏数据就让保存失败。
 */
export function bumpVersion(v: string | undefined): string {
  const m = /^v(\d+)$/.exec((v ?? "").trim());
  if (!m) return "v2";
  return `v${Number(m[1]) + 1}`;
}

/**
 * 两份配置是否等价 (只比生效字段, 不含版本号)
 *
 * 比版本号会把"只改了 version"误判成有变化 → 版本无限自增。
 */
function configsEqual(a: InsightConfig, b: InsightConfig): boolean {
  return stableStringify(stripVersions(a)) === stableStringify(stripVersions(b));
}

function stripVersions(c: InsightConfig) {
  return {
    scoring: { ...c.scoring, version: "" },
    actions: { ...c.actions, version: "" },
  };
}

/** 稳定序列化 (对象键排序) —— 免得 {a,b} 和 {b,a} 被判成不同 */
function stableStringify(v: unknown): string {
  if (v === null || typeof v !== "object") return JSON.stringify(v) ?? "null";
  if (Array.isArray(v)) return `[${v.map(stableStringify).join(",")}]`;
  const o = v as Record<string, unknown>;
  const keys = Object.keys(o).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${stableStringify(o[k])}`).join(",")}}`;
}
