// ============================================
// 养生记录 — 字典翻译 + 改善指标 (纯函数, 单测用)
//
// 来源: 原 `record_tile.dart`, 2026-09-24 记录页重构抽出。
//   为什么抽: RecordTile widget 已被新「时间线混合列表」用的 AppListRow 替换,
//   但下面这 5 个纯函数仍有调用方 (`customer_timeline_section.dart` 副文),
//   留 widget 就成了「没人用的孤儿组件」。
//
// 不变量:
//   - 改善方向: 疼痛 (lowerIsBetter=true), 睡眠 / 情绪 (lowerIsBetter=false)。
//     方向反了最容易写反 → 必须有单测。
//   - 只显示**前后都填了**的指标 (半填 = 编数据), 不能提纯。
// ============================================

import '../../../core/models/dictionaries.dart';
import '../../../core/models/wellness_record.dart';

/// 字典里的服务项目名 → 中文 (为 null = 字典还没加载完 → 调用方回落「养生记录」)
String? serviceItemName(Dictionaries? dict, String id) {
  if (dict == null) return null;
  for (final s in dict.serviceItems) {
    if (s.id == id) {
      final n = s.name.trim();
      return n.isEmpty ? null : n;
    }
  }
  return null;
}

/// 部位 ids → 名字列表 (查不到的 id 直接丢掉, 不留占位)
List<String> bodyPartNames(Dictionaries? dict, List<String> ids) {
  if (dict == null || ids.isEmpty) return const [];
  final byId = {for (final b in dict.bodyParts) b.id: b.name};
  return <String>[
    for (final id in ids)
      if ((byId[id] ?? '').trim().isNotEmpty) byId[id]!.trim(),
  ];
}

/// 前 → 后 改善指标 (疼痛 / 睡眠 / 情绪, 方向按 lowerIsBetter 区分)
class MetricDelta {
  final String label;
  final int? pre;
  final int? post;
  final bool lowerIsBetter;

  const MetricDelta({
    required this.label,
    required this.pre,
    required this.post,
    required this.lowerIsBetter,
  });

  bool get isComplete => pre != null && post != null;
  int? get rawDelta => isComplete ? post! - pre! : null;
  int? get absDelta => rawDelta?.abs();

  bool get isImprovement {
    final d = rawDelta;
    if (d == null || d == 0) return false;
    return lowerIsBetter ? d < 0 : d > 0;
  }

  bool get isWorsening {
    final d = rawDelta;
    if (d == null || d == 0) return false;
    return lowerIsBetter ? d > 0 : d < 0;
  }
}

/// 从一条养生记录抽取改善指标, 按固定顺序 (疼痛 → 睡眠 → 情绪), 最多 [max] 项
List<MetricDelta> metricDeltas(WellnessRecord r, {int max = 2}) {
  final all = <MetricDelta>[
    MetricDelta(
      label: '疼痛',
      pre: _intOf(r.preCondition['pain_level']),
      post: _intOf(r.postCondition['pain_level']),
      lowerIsBetter: true,
    ),
    MetricDelta(
      label: '睡眠',
      pre: _intOf(r.preCondition['sleep_quality']),
      post: _intOf(r.postCondition['sleep_quality']),
      lowerIsBetter: false,
    ),
    MetricDelta(
      label: '情绪',
      pre: _intOf(r.preCondition['mood']),
      post: _intOf(r.postCondition['mood']),
      lowerIsBetter: false,
    ),
  ];
  return all.where((m) => m.isComplete).take(max).toList();
}

/// 字符串 / 数字 / 其它 → 整数。null / 不可解析 → null
int? _intOf(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// 把改善指标压成单行短描述 (用于时间线副文, 例: 「疼痛 8→3 ↓5」)
///   · 无指标 → ''
///   · 单条 → '疼痛 8→3 ↓5'
///   · 多条 → '疼痛 8→3 ↓5 · 睡眠 4→7'
///   改善用 ↓ (疼痛) / ↑ (其它); 变差用 ↑ (疼痛) / ↓ (其它)。
///   不画「持平」字样 (与原 _MetricChip 行为对齐)。
String metricDeltaSummary(WellnessRecord r, {int max = 2}) {
  final ms = metricDeltas(r, max: max);
  if (ms.isEmpty) return '';
  final parts = <String>[];
  for (final m in ms) {
    final d = m.rawDelta ?? 0;
    final arrow = d == 0
        ? ''
        : (m.isImprovement
            ? (m.lowerIsBetter ? '↓${d.abs()}' : '↑$d')
            : (m.lowerIsBetter ? '↑${d.abs()}' : '↓$d'));
    final sep = arrow.isEmpty ? '' : ' $arrow';
    parts.add('${m.label} ${m.pre}→${m.post}$sep');
  }
  return parts.join(' · ');
}