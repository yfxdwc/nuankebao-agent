// ============================================
// AI 洞察模型 (客户详情页 AI 区用)
// 对应后端:
//   POST /ai/insight                          → AiInsightResult  ← P5 合并入口 (1 次调用)
//   GET  /ai/repurchase-prediction/[id]       → RepurchasePrediction (纯 DB, 免费自动加载)
// 手写解析 (不引 freezed/codegen): 字段少 + 后端会演进, 缺字段要有兜底默认值
//
// ⚠ P5 (主人 2026-09-23 拍「AI 4 卡合并成 1 次调用」):
//   旧模型 CustomerProfileInsight / EffectAnalysis / FollowUpSuggestion 已删 —— 它们
//   对应后端 3 个各自调一次 MiniMax 的路由。现在三段内容都在 AiInsightResult.sections 里,
//   由**同一次**调用产出 (后端有 `aiCallCount === 1` 断言守着)。
// ============================================

/// ────────────────────────────────────────────
/// P5 合并洞察: 一次调用产出的三段内容 + 事实底稿
/// ────────────────────────────────────────────

/// 三段 AI 内容
class AiInsightSections {
  final String profile;
  final String followUp;
  final String effect;

  const AiInsightSections({
    this.profile = '',
    this.followUp = '',
    this.effect = '',
  });

  factory AiInsightSections.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return AiInsightSections(
      profile: (j['profile'] as String?) ?? '',
      followUp: (j['followUp'] as String?) ?? '',
      effect: (j['effect'] as String?) ?? '',
    );
  }

  /// 三段全空 = 服务端没给出内容 (客户端该显示错误, 而不是空白卡片)
  bool get isEmpty =>
      profile.trim().isEmpty && followUp.trim().isEmpty && effect.trim().isEmpty;
}

/// 事实底稿 (本地算的, 不含 AI 判断; 卡片用它展示"依据" + 修边展示数字)
class AiInsightFacts {
  final int totalVisits;
  final int? daysSinceLastVisit;
  final int? avgIntervalDays;
  /// improving / stable / worsening / unknown
  final String trend;
  final String reason;
  final String? dateFrom;
  final String? dateTo;

  const AiInsightFacts({
    this.totalVisits = 0,
    this.daysSinceLastVisit,
    this.avgIntervalDays,
    this.trend = 'unknown',
    this.reason = '',
    this.dateFrom,
    this.dateTo,
  });

  factory AiInsightFacts.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    final range = (j['dateRange'] as Map<String, dynamic>?) ?? const {};
    return AiInsightFacts(
      totalVisits: (j['totalVisits'] as num?)?.toInt() ?? 0,
      daysSinceLastVisit: (j['daysSinceLastVisit'] as num?)?.toInt(),
      avgIntervalDays: (j['avgIntervalDays'] as num?)?.toInt(),
      trend: (j['trend'] as String?) ?? 'unknown',
      reason: (j['reason'] as String?) ?? '',
      dateFrom: range['from'] as String?,
      dateTo: range['to'] as String?,
    );
  }

  String get trendLabel => switch (trend) {
        'improving' => '改善中',
        'stable' => '基本持平',
        'worsening' => '有加重迹象',
        _ => '数据不足',
      };
}

/// 一次 AI 调用产出的完整洞察
class AiInsightResult {
  final String customerId;
  final String customerName;
  final AiInsightSections sections;
  /// false = 模型没按分隔符输出 (全文已落在 sections.profile, 不丢内容)
  final bool sectionsParsed;
  /// 复购预测 (纯 DB 计算, 不烧 AI)
  final RepurchasePrediction? repurchase;
  final AiInsightFacts facts;
  final bool aiMock;
  /// ⚠ P5 不变量: 本次洞察的 AI 调用次数 (后端保证恒为 1)
  final int aiCallCount;

  const AiInsightResult({
    required this.customerId,
    this.customerName = '',
    this.sections = const AiInsightSections(),
    this.sectionsParsed = true,
    this.repurchase,
    this.facts = const AiInsightFacts(),
    this.aiMock = false,
    this.aiCallCount = 1,
  });

  factory AiInsightResult.fromJson(Map<String, dynamic> json) {
    final rep = json['repurchase'] as Map<String, dynamic>?;
    return AiInsightResult(
      customerId: json['customerId']?.toString() ?? '',
      customerName: (json['customerName'] as String?) ?? '',
      sections:
          AiInsightSections.fromJson(json['sections'] as Map<String, dynamic>?),
      sectionsParsed: (json['sectionsParsed'] as bool?) ?? true,
      repurchase: rep == null ? null : RepurchasePrediction.fromJson(rep),
      facts: AiInsightFacts.fromJson(json['facts'] as Map<String, dynamic>?),
      aiMock: (json['aiMock'] as bool?) ?? false,
      aiCallCount: (json['aiCallCount'] as num?)?.toInt() ?? 1,
    );
  }
}

/// 复购预测 (纯 DB 计算, 不烧 AI 额度 → 页面自动加载)
class RepurchasePrediction {
  final String customerId;
  final String? lastVisit;
  final int? daysSinceLastVisit;
  final int? avgIntervalDays;
  final String? predictedNextVisit;
  final int? daysUntilPredicted;
  final String confidence; // high / medium / low
  final String reason;

  const RepurchasePrediction({
    required this.customerId,
    this.lastVisit,
    this.daysSinceLastVisit,
    this.avgIntervalDays,
    this.predictedNextVisit,
    this.daysUntilPredicted,
    this.confidence = 'low',
    this.reason = '',
  });

  factory RepurchasePrediction.fromJson(Map<String, dynamic> json) {
    return RepurchasePrediction(
      customerId: json['customerId']?.toString() ?? '',
      lastVisit: json['lastVisit'] as String?,
      daysSinceLastVisit: (json['daysSinceLastVisit'] as num?)?.toInt(),
      avgIntervalDays: (json['avgIntervalDays'] as num?)?.toInt(),
      predictedNextVisit: json['predictedNextVisit'] as String?,
      daysUntilPredicted: (json['daysUntilPredicted'] as num?)?.toInt(),
      confidence: (json['confidence'] as String?) ?? 'low',
      reason: (json['reason'] as String?) ?? '',
    );
  }

  /// 该催了 (预测窗口 7 天内 / 已过期)
  bool get isDue => daysUntilPredicted != null && daysUntilPredicted! <= 7;
}

