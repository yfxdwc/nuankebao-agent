// ============================================
// 客户洞察模型 (详情页 L0 用) —— 手写解析, 不引 codegen
// ============================================
// 对应后端:  GET /api/customers/[id]/insight
//   → { score, actions, topActions, scriptAvailable, weakDimensionThreshold, configVersion }
//
// 为什么手写 (同 ai_insight.dart 的理由): 字段少 + 后端会演进,
//   缺字段要有兜底默认值, 不因为后端加字段就崩。
//
// ⚠ 这些分数**不是 AI 算的** —— 是确定性规则引擎 (后端 lib/customer/scoring.ts)。
//   同一份数据算两次必须一样; AI 只负责把分数翻译成人话 (scriptAvailable = 会员才有)。
// ============================================

/// 一个可解释因子 ("这项为什么是这个分")
class ScoreFactor {
  final String key;
  final String label;
  final double score;
  final double max;
  final String detail;

  const ScoreFactor({
    required this.key,
    required this.label,
    required this.score,
    required this.max,
    required this.detail,
  });

  factory ScoreFactor.fromJson(Map<String, dynamic> json) => ScoreFactor(
        key: (json['key'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        score: ((json['score'] as num?) ?? 0).toDouble(),
        max: ((json['max'] as num?) ?? 0).toDouble(),
        detail: (json['detail'] as String?) ?? '',
      );
}

/// 一个评分维度 (健康改善 / 关系温度 / 价值潜力)
class ScoreDimension {
  final String key;
  final String label;
  /// 0-100; null = 数据不足 (不假装 0 分)
  final double? score;
  final String bandLabel;
  final List<ScoreFactor> factors;
  /// score = null 时说明缺什么
  final String? missingReason;

  const ScoreDimension({
    required this.key,
    required this.label,
    this.score,
    required this.bandLabel,
    this.factors = const [],
    this.missingReason,
  });

  bool get hasScore => score != null;

  factory ScoreDimension.fromJson(Map<String, dynamic> json) => ScoreDimension(
        key: (json['key'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        score: (json['score'] as num?)?.toDouble(),
        bandLabel: (json['bandLabel'] as String?) ?? '待评估',
        factors: ((json['factors'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ScoreFactor.fromJson)
            .toList(),
        missingReason: json['missingReason'] as String?,
      );
}

/// 三维评分总成
class CustomerScore {
  final double? overall;
  final String overallBandLabel;
  final ScoreDimension effect;
  final ScoreDimension engagement;
  final ScoreDimension value;
  /// 短板维度 key (score < 阈值, 升序)
  final List<String> weakDimensions;
  final String scoringVersion;
  final String configVersion;

  const CustomerScore({
    this.overall,
    required this.overallBandLabel,
    required this.effect,
    required this.engagement,
    required this.value,
    this.weakDimensions = const [],
    this.scoringVersion = '',
    this.configVersion = '',
  });

  List<ScoreDimension> get dimensions => [effect, engagement, value];

  factory CustomerScore.fromJson(Map<String, dynamic> json) => CustomerScore(
        overall: (json['overall'] as num?)?.toDouble(),
        overallBandLabel: (json['overallBandLabel'] as String?) ?? '待评估',
        effect: ScoreDimension.fromJson(
            (json['effect'] as Map<String, dynamic>?) ?? const {}),
        engagement: ScoreDimension.fromJson(
            (json['engagement'] as Map<String, dynamic>?) ?? const {}),
        value: ScoreDimension.fromJson(
            (json['value'] as Map<String, dynamic>?) ?? const {}),
        weakDimensions: ((json['weakDimensions'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        scoringVersion: (json['scoringVersion'] as String?) ?? '',
        configVersion: (json['configVersion'] as String?) ?? '',
      );
}

/// 一条行动指引 (结构化, 可一键建任务)
class ActionItem {
  final String id;
  final String priority; // high | medium | low
  final String title;
  final String why;
  final Map<String, dynamic> evidence;
  final String when;
  final String channel;
  final String expected;
  /// 一键建任务时预填的标题 / 截止时间
  final String taskTitle;
  final String taskDueAt;

  const ActionItem({
    required this.id,
    required this.priority,
    required this.title,
    required this.why,
    this.evidence = const {},
    required this.when,
    required this.channel,
    required this.expected,
    required this.taskTitle,
    required this.taskDueAt,
  });

  bool get isHigh => priority == 'high';

  /// 渠道 → 中文 + 图标语义 (UI 用)
  String get channelLabel => switch (channel) {
        'phone' => '电话',
        'wechat' => '微信',
        'visit' => '到店',
        'profile' => '档案',
        _ => '内部',
      };

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
        id: (json['id'] as String?) ?? '',
        priority: (json['priority'] as String?) ?? 'low',
        title: (json['title'] as String?) ?? '',
        why: (json['why'] as String?) ?? '',
        evidence:
            (json['evidence'] as Map<String, dynamic>?) ?? const {},
        when: (json['when'] as String?) ?? '',
        channel: (json['channel'] as String?) ?? 'other',
        expected: (json['expected'] as String?) ?? '',
        taskTitle: (json['taskTitle'] as String?) ?? '',
        taskDueAt: (json['taskDueAt'] as String?) ?? '',
      );
}

/// 详情页 L0 的全部数据 (一次请求)
class CustomerInsight {
  final CustomerScore score;
  final List<ActionItem> actions;
  final List<ActionItem> topActions;
  /// AI 话术是否可用 (会员) —— 免费层只有行动本身
  final bool scriptAvailable;
  final double weakDimensionThreshold;
  final String configVersion;

  const CustomerInsight({
    required this.score,
    required this.actions,
    required this.topActions,
    this.scriptAvailable = false,
    this.weakDimensionThreshold = 60,
    this.configVersion = '',
  });

  factory CustomerInsight.fromJson(Map<String, dynamic> json) => CustomerInsight(
        score: CustomerScore.fromJson(
            (json['score'] as Map<String, dynamic>?) ?? const {}),
        actions: ((json['actions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ActionItem.fromJson)
            .toList(),
        topActions: ((json['topActions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ActionItem.fromJson)
            .toList(),
        scriptAvailable: (json['scriptAvailable'] as bool?) ?? false,
        weakDimensionThreshold:
            ((json['weakDimensionThreshold'] as num?) ?? 60).toDouble(),
        configVersion: (json['configVersion'] as String?) ?? '',
      );
}
