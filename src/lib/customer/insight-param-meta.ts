// ============================================
// 客户洞察参数「元数据」—— admin 调节页的 UI 真相源
// ============================================
// 为什么单独一个文件, 而不是把中文名写在前端:
//   ① 区间必须与 `resolveInsightConfig` 的夹取范围**完全一致** —— 否则 UI 允许填
//      -5, 后端悄悄夹成 0, 用户以为存进去了 (最气人的一类配置 bug)。
//      放同仓 + 下方 `assertMetaRangesMatchResolver` 测试锁住一致性。
//   ② 前端只拿到「能改哪些 / 叫什么 / 范围多少」, 不需要把 31 个字段名硬编码进 JSX。
//
// ⚠ 改这里的 min/max 时, 必须同步改 `insight-config.ts::resolveInsightConfig` 里的
//   pickNum 上下界 —— 测试会当场失败提醒你 (test/insight-param-meta 那个文件)。
//
// path 用点号路径 (与配置对象结构一一对应), 例: "scoring.effect.recentN"
// ============================================

export type ParamType = "number" | "priority";

export interface ParamMeta {
  /** 点号路径, 与 InsightConfig 结构一一对应 */
  path: string;
  /** 分组 id (见 INSIGHT_PARAM_GROUPS) */
  group: string;
  /** 中文名 (给销售/店长看的, 不要出现 weight/ratio 这类词) */
  label: string;
  /** 一句话说明: 这个数字在业务上意味着什么 */
  hint?: string;
  unit?: string;
  type: ParamType;
  /** 数值型必填 (UI 用它做 input[type=number] 的 min/max/step, 后端也会按它夹) */
  min?: number;
  max?: number;
  step?: number;
}

export interface ParamGroup {
  id: string;
  title: string;
  /** 整个分组的说明 (折叠面板标题下方一行) */
  desc: string;
}

export const INSIGHT_PARAM_GROUPS: ParamGroup[] = [
  {
    id: "weights",
    title: "三维权重与短板线",
    desc: "综合分由「效果 / 关系温度 / 价值潜力」三个维度加权得出。权重是相对比例, 不必凑成 1 (系统会自动重归一化)。",
  },
  {
    id: "effect",
    title: "健康改善分",
    desc: "看客户做完项目有没有真的变好: 用最近几次的疼痛/睡眠/情绪变化算分。",
  },
  {
    id: "engagement",
    title: "关系温度分",
    desc: "看客户跟我们的关系有多热: 到店守不守时、联系多不多、有没有按建议来。",
  },
  {
    id: "value",
    title: "价值潜力分",
    desc: "看客户值不值得投入: 到店密度、关系时长、互动渠道广度 (不含金额, CHARTER §3.6)。",
  },
  {
    id: "actions",
    title: "行动触发阈值",
    desc: "决定「什么时候该提醒销售做什么」。改这里会直接改变客户详情页的行动指引。",
  },
  {
    id: "priorities",
    title: "行动优先级",
    desc: "每条行动规则的重要程度。高优先级会排在 L0 最前面 (客户详情页顶部每天看的位置)。",
  },
];

const num = (
  path: string,
  group: string,
  label: string,
  min: number,
  max: number,
  opts: { hint?: string; unit?: string; step?: number } = {},
): ParamMeta => ({
  path,
  group,
  label,
  type: "number",
  min,
  max,
  step: opts.step ?? (max <= 2 ? 0.05 : 1),
  hint: opts.hint,
  unit: opts.unit,
});

const prio = (path: string, label: string, hint: string): ParamMeta => ({
  path,
  group: "priorities",
  label,
  hint,
  type: "priority",
});

export const INSIGHT_PARAM_META: ParamMeta[] = [
  // ── 权重与短板线 ──
  num("scoring.weights.effect", "weights", "健康改善 权重", 0, 1, {
    hint: "三个维度的相对占比。例: 0.3 表示占三成。",
  }),
  num("scoring.weights.engagement", "weights", "关系温度 权重", 0, 1),
  num("scoring.weights.value", "weights", "价值潜力 权重", 0, 1),
  num("scoring.weakDimensionThreshold", "weights", "短板判定线", 0, 100, {
    hint: "维度分低于这条线就标成「短板」, 会出现在客户详情页的提示里。",
    unit: "分",
  }),

  // ── 健康改善分 ──
  num("scoring.effect.recentN", "effect", "取最近几条记录", 1, 50, {
    hint: "算改善分时看最近多少次到店。",
    unit: "条",
  }),
  num("scoring.effect.metricWeights.pain", "effect", "疼痛 权重", 0, 1),
  num("scoring.effect.metricWeights.sleep", "effect", "睡眠 权重", 0, 1),
  num("scoring.effect.metricWeights.mood", "effect", "情绪 权重", 0, 1),
  num("scoring.effect.factorMax.latest", "effect", "「最近一次改善」满分", 0, 100, { unit: "分" }),
  num("scoring.effect.factorMax.recentAvg", "effect", "「近期平均改善」满分", 0, 100, { unit: "分" }),
  num("scoring.effect.factorMax.trend", "effect", "「趋势」满分", 0, 100, { unit: "分" }),
  num("scoring.effect.trend.headN", "effect", "趋势: 前段取几次", 1, 20, { unit: "条" }),
  num("scoring.effect.trend.tailN", "effect", "趋势: 后段取几次", 1, 20, { unit: "条" }),
  num("scoring.effect.trend.fullDelta", "effect", "趋势满分需要的改善幅度", 0.01, 2, {
    hint: "例: 1 = 改善 1 分 (0-10 量表) 就算满分趋势。",
  }),
  num("scoring.effect.scale.neutral", "effect", "评分量表中位值", 0, 100, {
    hint: "客户填 0-10, 这个值是「没变化」的位置。",
  }),
  num("scoring.effect.scale.span", "effect", "评分量表跨度", 1, 100),

  // ── 关系温度分 ──
  num("scoring.engagement.factorMax", "engagement", "关系温度 满分", 1, 100, { unit: "分" }),
  num("scoring.engagement.punctuality.fullRatio", "engagement", "守时: 满分比例", 0, 10, {
    hint: "实际到店间隔 ÷ 约定间隔 ≤ 此值 = 满分。",
  }),
  num("scoring.engagement.punctuality.zeroRatio", "engagement", "守时: 零分比例", 0.1, 20, {
    hint: "超过此比例 = 0 分。",
  }),
  num("scoring.engagement.noRhythm.cadenceDays", "engagement", "无节奏时的默认周期", 1, 365, {
    hint: "客户还没有固定节奏时, 按这个天数算「该来了」。",
    unit: "天",
  }),
  num("scoring.engagement.noRhythm.capRatio", "engagement", "无节奏时的得分上限比例", 0, 1),
  num("scoring.engagement.depth.windowDays", "engagement", "互动广度: 回看窗口", 1, 3650, {
    hint: "统计互动次数的时间窗口。",
    unit: "天",
  }),
  num("scoring.engagement.depth.fullWeighted", "engagement", "互动广度: 满分加权次数", 1, 1000, {
    unit: "次",
  }),
  num("scoring.engagement.depth.weights.visit", "engagement", "到店 计权", 0, 100),
  num("scoring.engagement.depth.weights.phone", "engagement", "打电话 计权", 0, 100),
  num("scoring.engagement.depth.weights.wechat", "engagement", "微信 计权", 0, 100),
  num("scoring.engagement.depth.weights.holidayGreeting", "engagement", "节日问候 计权", 0, 100),
  num("scoring.engagement.depth.weights.other", "engagement", "其他互动 计权", 0, 100),
  num("scoring.engagement.taskHealth.noTaskRatio", "engagement", "任务健康: 无任务扣分比例", 0, 1, {
    hint: "名下有客户却一条跟进任务都没有时, 关系温度打几折。",
  }),

  // ── 价值潜力分 ──
  num("scoring.value.visitDensity.windowDays", "value", "到店密度: 窗口", 1, 3650, {
    hint: "看「多久来一次」的回看天数。",
    unit: "天",
  }),
  num("scoring.value.visitDensity.monthsInWindow", "value", "到店密度: 折算月数", 1, 365, {
    unit: "月",
  }),
  num("scoring.value.visitDensity.fullMonthly", "value", "到店密度: 满分月均次数", 0.1, 100, {
    unit: "次/月",
  }),
  num("scoring.value.visitDensity.max", "value", "到店密度 满分", 0, 100, { unit: "分" }),
  num("scoring.value.tenure.fullMonths", "value", "关系时长: 满分月数", 1, 600, {
    unit: "月",
  }),
  num("scoring.value.tenure.max", "value", "关系时长 满分", 0, 100, { unit: "分" }),
  num("scoring.value.breadth.perChannel", "value", "互动渠道广度: 每渠道加分", 0, 100, { unit: "分" }),
  num("scoring.value.breadth.max", "value", "互动渠道广度 满分", 0, 100, { unit: "分" }),
  num("scoring.value.minTenureDays", "value", "建档多少天后才评价值", 0, 3650, {
    hint: "新客户数据太少, 不到这个天数不给价值分 (显示「待评估」而不是误判成「价值低」)。",
    unit: "天",
  }),

  // ── 行动阈值 ──
  num("actions.repurchaseOverdueFactor", "actions", "复购超期 倍数", 0.1, 10, {
    hint: "距上次到店 > 她的平均周期 × 此值 → 提醒约下次。",
    unit: "倍",
  }),
  num("actions.repurchaseAbsoluteOverdueDays", "actions", "复购超期 绝对兜底", 1, 3650, {
    hint: "她没有复购节奏时, 超过这个天数就提醒。",
    unit: "天",
  }),
  num("actions.contactGapFactor", "actions", "联系超期 倍数", 0.1, 10, {
    hint: "距上次联系 > 平均互动间隔 × 此值 → 提醒主动联系。",
    unit: "倍",
  }),
  num("actions.contactAbsoluteGapDays", "actions", "联系超期 绝对兜底", 1, 3650, {
    hint: "没有互动节奏时, 超过这个天数就提醒联系。",
    unit: "天",
  }),
  num("actions.neverContactedGraceDays", "actions", "「从没联系过」宽限", 0, 365, {
    hint: "建档多少天后仍没联系过才算需要破冰 (当天刚建的别催)。",
    unit: "天",
  }),
  num("actions.birthdayWindowDays", "actions", "生日提醒 提前量", 0, 365, { unit: "天" }),
  num("actions.firstVisitFollowupDays", "actions", "首访后回访 窗口", 0, 365, { unit: "天" }),
  num("actions.adviceLeadDays", "actions", "下次建议日 提前量", 0, 365, { unit: "天" }),

  // ── 行动优先级 (9 条规则) ──
  prio("actions.priorities.never_contacted", "从没联系过", "建档后一次都没联系过"),
  prio("actions.priorities.repurchase_window", "该复购了", "到了她的复购窗口"),
  prio("actions.priorities.task_overdue", "跟进任务逾期", "名下有逾期未完成的跟进任务"),
  prio("actions.priorities.no_improvement", "效果没改善", "最近一次做完没有改善"),
  prio("actions.priorities.contact_gap", "好久没联系", "超过她的联系节奏"),
  prio("actions.priorities.birthday_window", "生日/节日临近", "进入生日提醒窗口"),
  prio("actions.priorities.first_visit_followup", "首访后回访", "第一次到店后的回访窗口"),
  prio("actions.priorities.advice_due", "该看建议日了", "上次记录里的下次建议日临近"),
  prio("actions.priorities.profile_incomplete", "档案不完整", "缺归属人/关键字段"),
];

/** 按分组取元数据 (UI 渲染顺序 = 此表顺序) */
export function paramsOfGroup(groupId: string): ParamMeta[] {
  return INSIGHT_PARAM_META.filter((p) => p.group === groupId);
}

// ============================================
// 点号路径读写 (不改动原对象)
// ============================================

/** 读 `a.b.c`; 中间缺失返回 undefined (不抛) */
export function readParam(obj: unknown, path: string): unknown {
  let cur: unknown = obj;
  for (const seg of path.split(".")) {
    if (cur === null || typeof cur !== "object") return undefined;
    cur = (cur as Record<string, unknown>)[seg];
  }
  return cur;
}

/**
 * 写入 `a.b.c` 并返回**新对象** (逐层浅拷贝, 不 mutate 入参)
 *
 * 为什么要 immutable: 前端用 React state 存草稿配置, 直接改会让
 * `Object.is(prev, next)` 判定为没变化 → 界面不刷新。
 */
export function writeParam<T extends Record<string, unknown>>(
  obj: T,
  path: string,
  value: unknown
): T {
  const segs = path.split(".");
  const clone = (node: unknown): Record<string, unknown> =>
    node !== null && typeof node === "object"
      ? { ...(node as Record<string, unknown>) }
      : {};

  const root = clone(obj);
  let cur = root;
  for (let i = 0; i < segs.length - 1; i++) {
    cur[segs[i]] = clone(cur[segs[i]]);
    cur = cur[segs[i]] as Record<string, unknown>;
  }
  cur[segs[segs.length - 1]] = value;
  return root as T;
}

/** 把生效配置压成 `{path: value}` 扁平表 (UI 显示"当前值"用) */
export function flattenConfig(config: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const p of INSIGHT_PARAM_META) {
    out[p.path] = readParam(config, p.path);
  }
  return out;
}
