// ============================================
// AI 洞察模型 (客户详情页 AI 区用)
// 对应后端:
//   GET  /api/ai/profile/[id]                → CustomerProfileInsight
//   GET  /api/ai/repurchase-prediction/[id]  → RepurchasePrediction
//   GET  /api/ai/effect-analysis/[id]        → EffectAnalysis
//   POST /api/ai/follow-up                   → FollowUpSuggestion
// 手写解析 (不引 freezed/codegen): 字段少 + 后端会演进, 缺字段要有兜底默认值
// ============================================

/// AI 客户画像 (应用层聚合 + AI 总结)
class CustomerProfileInsight {
  final String aiSummary;
  final bool aiMock;
  final String? name;
  final List<String> recentSummaries;

  const CustomerProfileInsight({
    required this.aiSummary,
    this.aiMock = false,
    this.name,
    this.recentSummaries = const [],
  });

  factory CustomerProfileInsight.fromJson(Map<String, dynamic> json) {
    final cust = (json['customer'] as Map<String, dynamic>?) ?? const {};
    final records = (json['recentRecords'] as List?) ?? const [];
    return CustomerProfileInsight(
      aiSummary: (json['aiSummary'] as String?) ?? '暂无画像',
      aiMock: json['aiMock'] as bool? ?? false,
      name: cust['name'] as String?,
      recentSummaries: records
          .whereType<Map<String, dynamic>>()
          .map((r) {
            final date = (r['serviceDate'] as String?) ?? '';
            final item = (r['serviceItem'] as String?) ?? '';
            final parts = ((r['bodyParts'] as List?) ?? const []).join('/');
            return [date, item, parts].where((s) => s.isNotEmpty).join(' · ');
          })
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  static const empty = CustomerProfileInsight(aiSummary: '暂无画像');
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

/// 效果分析 (AI 总结 + 趋势)
class EffectAnalysis {
  final int totalVisits;
  final String trend; // improving / stable / worsening / unknown
  final String aiSummary;
  final bool aiMock;
  final String? from;
  final String? to;

  const EffectAnalysis({
    required this.totalVisits,
    this.trend = 'unknown',
    this.aiSummary = '',
    this.aiMock = false,
    this.from,
    this.to,
  });

  factory EffectAnalysis.fromJson(Map<String, dynamic> json) {
    final range = (json['dateRange'] as Map<String, dynamic>?) ?? const {};
    return EffectAnalysis(
      totalVisits: (json['totalVisits'] as num?)?.toInt() ?? 0,
      trend: (json['trend'] as String?) ?? 'unknown',
      aiSummary: (json['aiSummary'] as String?) ?? '',
      aiMock: json['aiMock'] as bool? ?? false,
      from: range['from'] as String?,
      to: range['to'] as String?,
    );
  }

  String get trendLabel {
    switch (trend) {
      case 'improving':
        return '好转中';
      case 'stable':
        return '平稳';
      case 'worsening':
        return '需关注';
      default:
        return '数据不足';
    }
  }
}

/// AI 跟进建议 (话术)
class FollowUpSuggestion {
  final String suggestion;
  final String reason;
  final int? daysSinceLastVisit;
  final int? avgInterval;
  final bool aiMock;

  const FollowUpSuggestion({
    required this.suggestion,
    this.reason = '',
    this.daysSinceLastVisit,
    this.avgInterval,
    this.aiMock = false,
  });

  factory FollowUpSuggestion.fromJson(Map<String, dynamic> json) {
    return FollowUpSuggestion(
      suggestion: (json['suggestion'] as String?) ?? '暂无建议',
      reason: (json['reason'] as String?) ?? '',
      daysSinceLastVisit: (json['daysSinceLastVisit'] as num?)?.toInt(),
      avgInterval: (json['avgInterval'] as num?)?.toInt(),
      aiMock: json['aiMock'] as bool? ?? false,
    );
  }
}
