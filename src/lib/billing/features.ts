// ============================================
// 会员功能清单 (服务端唯一真相)
// ============================================
// ADR-0012 + docs/membership-billing-draft.md v0.2
//
// 产品口径 (主人 2026-09-19):
//   免费档 = 除下面 9 项外的**全部功能**; 会员档 = 全部功能
//   到期 = 降级免费档 (基础功能照用, 数据不删不锁)
//
// 用法 (服务端唯一安全边界):
//   const m = await requireFeature(userId, "ai.follow_up");   // 非会员 → 402
//   if (!m) → 客户端只负责"别显示入口", 断不了后端的门
//
// 新增会员功能时: 先在这里加 key → 再在 plan.features 里挂上 → 再在 route 首行判权
// (漏了第 3 步 = 白送功能, code review 必查)

export const FEATURES = {
  /** AI 助手区块 (整块; 客户端用它隐藏整个 AI 区) */
  AI_ASSISTANT: "ai.assistant",
  /** 跟进建议 (AI 话术) */
  AI_FOLLOW_UP: "ai.follow_up",
  /** 客户画像 (AI) */
  AI_CUSTOMER_PROFILE: "ai.customer_profile",
  /** 效果分析 (AI) */
  AI_EFFECT_ANALYSIS: "ai.effect_analysis",
  /** 跟进推荐 (复购预测; 纯 DB 计算, 但主人拍板归会员 — D21) */
  AI_REPURCHASE: "ai.repurchase",
  /** 沙龙发起 (另一 session 正在建的 modules/salon; 建好即会员功能) */
  SALON_CREATE: "salon.create",
  /** 互动记录 (GET 允许看历史, POST 需会员) */
  CRM_INTERACTION: "crm.interaction",
  /** 生日提醒 (非会员读客户数据时 birthdayRemindDays → null) */
  CRM_BIRTHDAY_REMINDER: "crm.birthday_reminder",
  /** 图片上传 (业务照片; 个人头像 purpose=avatar 不受限) */
  MEDIA_UPLOAD: "media.upload",
} as const;

export type FeatureKey = (typeof FEATURES)[keyof typeof FEATURES];

/** 全部会员功能 (会员档 = 全部) */
export const ALL_FEATURES: FeatureKey[] = Object.values(FEATURES);

/** 免费档能用的会员功能: 空 (免费档 = 基础功能, 下面 9 项都没有) */
export const FREE_FEATURES: FeatureKey[] = [];

/** 是不是合法的 feature key (防止约定写错时静默放行) */
export function isFeatureKey(v: string): v is FeatureKey {
  return (ALL_FEATURES as string[]).includes(v);
}

/** 按当前是否会员算出租户... 不对, 是**用户**能用的功能集 (个人订阅制) */
export function featuresFor(isMember: boolean): FeatureKey[] {
  return isMember ? ALL_FEATURES : FREE_FEATURES;
}

/** 单个功能是否可用 (纯函数, 单测用) */
export function canUseFeature(isMember: boolean, key: FeatureKey): boolean {
  if (!isFeatureKey(key)) return false; // 写错的 key 一律拒绝 (不静默放行)
  return featuresFor(isMember).includes(key);
}
