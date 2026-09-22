// ============================================
// 用量事件词表 (Dart 镜像)
//
// ⚠ 双端契约: 本文件必须与 src/lib/usage/catalog.ts 保持一致
//   - 事件名 / category / props 白名单
//   - 服务端拒绝词表外的事件 → 改这里必须同时改 TypeScript 侧
//
// 红线 (CHARTER §4.4.5):
//   - props 只放 ID / 枚举 / 计数 / 时长
//   - ❌ 不放姓名 / 手机号 / 疾病史 / 养生内容 / 自由文本
// ============================================

/// 事件分类 (字符串与服务端 catalog.ts 的 UsageCategory 对齐)
enum UsageCategory {
  lifecycle,
  nav,
  auth,
  customer,
  wellness,
  followup,
  ai,
  salon,
  relation,
  error,
  perf,
}

class UsageEventSpec {
  final UsageCategory category;
  final List<String> props;
  const UsageEventSpec(this.category, [this.props = const []]);
}

/// 事件词表 (与服务端 src/lib/usage/catalog.ts 逐条对齐)
const Map<String, UsageEventSpec> kUsageEvents = {
  // 生命周期
  'app_open': UsageEventSpec(UsageCategory.lifecycle, ['first']),
  'app_pause': UsageEventSpec(UsageCategory.lifecycle),
  'app_resume': UsageEventSpec(UsageCategory.lifecycle),
  // 导航
  'screen_view': UsageEventSpec(UsageCategory.nav),
  // 认证
  'login_success': UsageEventSpec(UsageCategory.auth),
  'login_fail': UsageEventSpec(UsageCategory.auth, ['reason']),
  'logout': UsageEventSpec(UsageCategory.auth),
  // 客户
  'customer_view': UsageEventSpec(UsageCategory.customer, ['source']),
  'customer_create': UsageEventSpec(UsageCategory.customer, ['source']),
  'customer_edit': UsageEventSpec(UsageCategory.customer),
  'customer_search': UsageEventSpec(UsageCategory.customer, ['keywordLen']),
  'customer_call': UsageEventSpec(UsageCategory.customer),
  // 养生记录
  'record_create': UsageEventSpec(UsageCategory.wellness, ['step']),
  'record_edit': UsageEventSpec(UsageCategory.wellness),
  'record_photo_taken': UsageEventSpec(UsageCategory.wellness),
  // 跟进
  'follow_up_create': UsageEventSpec(UsageCategory.followup, ['source']),
  'follow_up_done': UsageEventSpec(UsageCategory.followup),
  'follow_up_postpone': UsageEventSpec(UsageCategory.followup),
  'follow_up_list_view': UsageEventSpec(UsageCategory.followup),
  // AI (回答「AI 卡片到底有没有人点」)
  'ai_generate_click': UsageEventSpec(UsageCategory.ai, ['card']),
  'ai_generate_result': UsageEventSpec(UsageCategory.ai, ['card', 'cached']),
  'ai_regenerate': UsageEventSpec(UsageCategory.ai, ['card']),
  // 沙龙
  'salon_create': UsageEventSpec(UsageCategory.salon),
  'salon_rsvp': UsageEventSpec(UsageCategory.salon, ['status']),
  // 加盟关系
  'placement_request_create': UsageEventSpec(UsageCategory.relation),
  // 失败 / 性能
  'api_error': UsageEventSpec(UsageCategory.error, ['path', 'status']),
  'ui_error': UsageEventSpec(UsageCategory.error),
  'api_latency': UsageEventSpec(UsageCategory.perf, ['path', 'bucketMs']),
};

/// 实体类型 (与服务端 USAGE_ENTITY_TYPES 对齐)
class UsageEntityType {
  static const customer = 'customer';
  static const wellnessRecord = 'wellness_record';
  static const followUp = 'follow_up';
  static const salon = 'salon';
  static const user = 'user';
  static const franchisee = 'franchisee';

  static const all = [
    customer,
    wellnessRecord,
    followUp,
    salon,
    user,
    franchisee,
  ];
}

/// AI 卡片枚举 (与 ai_insight_cards.dart 的 4 张卡对齐)
class AiCard {
  static const profile = 'profile';
  static const followUp = 'follow_up';
  static const repurchase = 'repurchase';
  static const effect = 'effect';
}
