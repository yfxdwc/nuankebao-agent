// ============================================
// 客户分析图谱模型 (P4) —— 手写解析
// ============================================
// 对应后端:  GET /api/customers/[id]/charts
//   → { trend[], bodyParts[], scoredRecordCount, recordCount }
//
// 雷达图不需要这里的字段 —— 它直接用 CustomerScore 的 effect/engagement/value。
//
// ⚠ 后端只给**描述性统计** (次数 / 中位止痛幅度)。前端也不许自己编"医疗建议"
//   (CHARTER §1.3 不做诊断系统)。
// ============================================

/// 趋势图上一个点 (一次养生记录的前后评分)
class TrendPoint {
  final String date; // YYYY-MM-DD
  final double? prePain;
  final double? postPain;
  final double? preSleep;
  final double? postSleep;

  const TrendPoint({
    required this.date,
    this.prePain,
    this.postPain,
    this.preSleep,
    this.postSleep,
  });

  /// 有疼痛前后值 → 可以画在疼痛折线上
  bool get hasPain => prePain != null && postPain != null;
  bool get hasSleep => preSleep != null && postSleep != null;

  /// MM-DD (轴上不必显示年)
  String get shortDate => date.length >= 10 ? date.substring(5) : date;

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        date: (j['date'] as String?) ?? '',
        prePain: (j['prePain'] as num?)?.toDouble(),
        postPain: (j['postPain'] as num?)?.toDouble(),
        preSleep: (j['preSleep'] as num?)?.toDouble(),
        postSleep: (j['postSleep'] as num?)?.toDouble(),
      );
}

/// 部位统计
class BodyPartStat {
  final String id;
  final String name;
  /// 出现在几条记录里
  final int count;
  /// 疼痛下降的中位数 (正 = 改善); null = 该部位没有可比的疼痛前后值
  final double? medianPainDrop;

  const BodyPartStat({
    required this.id,
    required this.name,
    required this.count,
    this.medianPainDrop,
  });

  factory BodyPartStat.fromJson(Map<String, dynamic> j) => BodyPartStat(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        count: ((j['count'] as num?) ?? 0).toInt(),
        medianPainDrop: (j['medianPainDrop'] as num?)?.toDouble(),
      );
}

class CustomerCharts {
  final List<TrendPoint> trend;
  final List<BodyPartStat> bodyParts;
  /// 带评分的记录条数 (判断"样本够不够画图")
  final int scoredRecordCount;
  final int recordCount;

  const CustomerCharts({
    this.trend = const [],
    this.bodyParts = const [],
    this.scoredRecordCount = 0,
    this.recordCount = 0,
  });

  bool get hasTrend => trend.length >= 2;
  bool get hasBodyParts => bodyParts.isNotEmpty;

  factory CustomerCharts.fromJson(Map<String, dynamic> j) => CustomerCharts(
        trend: ((j['trend'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(TrendPoint.fromJson)
            .toList(),
        bodyParts: ((j['bodyParts'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(BodyPartStat.fromJson)
            .toList(),
        scoredRecordCount: ((j['scoredRecordCount'] as num?) ?? 0).toInt(),
        recordCount: ((j['recordCount'] as num?) ?? 0).toInt(),
      );
}
