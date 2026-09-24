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
import 'package:intl/intl.dart';

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

// ============================================
// 日期相关纯函数 (2026-09-25 客户详情「记录」Tab 时间线 10 项改进)
// ============================================
//
// 设计原则:
//   - 都是纯函数, 接受可选 `now` 便于单测
//   - 都按**本地日期**对齐 (YYYY-MM-DD), 与 `followUpDaysUntilDue` 同一口径
//     —— CST 早晨的 UTC 漂移教训 (见 AGENTS §5)。
//   - 入参统一接受 YYYY-MM-DD 字符串 (serviceDate / createdAt 等的格式),
//     内部 `DateTime.tryParse`; 解析失败时**降级**为 「」/null, 不抛。

/// 把任意 DateTime 归一到「本地零点」(00:00:00)。用于日期比较, 避开时分秒/时区。
DateTime _dayKey(DateTime dt) {
  final l = dt.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// 把 YYYY-MM-DD 解析为本地零点; 失败返回 null。
DateTime? _parseYmd(String? ymd) {
  if (ymd == null || ymd.isEmpty) return null;
  final d = DateTime.tryParse(ymd);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

/// 「YYYY-MM-DD → 距今天 N 天」(0=今天, 1=明天, -1=昨天)。解析失败 → null。
int? daysFromToday(String? ymd, {DateTime? now}) {
  final d = _parseYmd(ymd);
  if (d == null) return null;
  final today = _dayKey(now ?? DateTime.now());
  return d.difference(today).inDays;
}

/// 相对时间标签 (汇总行「最近一次 X」用):
///   - 今天   → '今天'
///   - 昨天   → '昨天'
///   - N 天前 → 'N 天前'
///   失败 → ''
String relativeDayLabel(String? ymd, {DateTime? now}) {
  final diff = daysFromToday(ymd, now: now);
  if (diff == null) return '';
  if (diff == 0) return '今天';
  if (diff == -1) return '昨天';
  if (diff < -1) return '${-diff} 天前';
  // 未来 (理论上不该发生, 但 API 返回错值时给具体日期兜底)
  return '$diff 天后';
}

/// 下次建议回访日期提示:
///   - 无 nextAdviceDate 或解析失败 → null
///   - 未逾期 (含今天) → '建议 MM-dd 回访'
///   - 已逾期 N 天      → '建议 MM-dd · 已过 N 天'
String? adviceHint(WellnessRecord r, {DateTime? now}) {
  final ymd = r.nextAdviceDate;
  final d = _parseYmd(ymd);
  if (d == null) return null;
  final today = _dayKey(now ?? DateTime.now());
  final label = DateFormat('MM-dd').format(d);
  final diff = d.difference(today).inDays;
  if (diff <= 0) {
    if (diff == 0) return '建议 $label 回访';
    return '建议 $label · 已过 ${-diff} 天';
  }
  return '建议 $label 回访';
}

/// 是否为「已逾期」的下次建议日期 (供 Text.rich 染 AppColors.warning 用)。
bool adviceOverdue(WellnessRecord r, {DateTime? now}) {
  final diff = daysFromToday(r.nextAdviceDate, now: now);
  return diff != null && diff < 0;
}

/// 时间线分组桶 (按本地日期划):
///   'today' / 'yesterday' / 'thisWeek' / 'thisMonth' / 'earlier'
///   解析失败 → 'earlier' (兜底, 走「更早」组)
enum TimelineBucket { today, yesterday, thisWeek, thisMonth, earlier }

/// 分组函数 (纯函数, 测试用):
///   · 「今天」  diff == 0
///   · 「昨天」  diff == -1
///   · 「本周」  diff in [-6, -2] (周一起算: 今天 / 昨天 / 更早都视作当周)
///     —— 范围 [-6, -2] 覆盖周一到周日七天 (diff=-2 = 前天)
///   · 「本月」  diff in [-29, -7] (同月且非本周, 与时间序一致)
///   · 「更早」  diff <= -30 或未来 (兜底)
TimelineBucket bucketOf(String? ymd, {DateTime? now}) {
  final diff = daysFromToday(ymd, now: now);
  if (diff == null) return TimelineBucket.earlier;
  if (diff == 0) return TimelineBucket.today;
  if (diff == -1) return TimelineBucket.yesterday;
  if (diff >= -6 && diff <= -2) return TimelineBucket.thisWeek;
  // 同月但已超出本周范围 (粗略按 [this month start, -7])
  if (diff >= -29 && diff <= -7) return TimelineBucket.thisMonth;
  return TimelineBucket.earlier;
}

/// 分组桶显示文案 (给分组头用)
String bucketLabel(TimelineBucket b) => switch (b) {
      TimelineBucket.today => '今天',
      TimelineBucket.yesterday => '昨天',
      TimelineBucket.thisWeek => '本周',
      TimelineBucket.thisMonth => '本月',
      TimelineBucket.earlier => '更早',
    };

/// 桶在时间线上**从新到旧**的渲染顺序 (用于插分组头时倒序遍历不漏)
const List<TimelineBucket> kBucketOrderDesc = [
  TimelineBucket.today,
  TimelineBucket.yesterday,
  TimelineBucket.thisWeek,
  TimelineBucket.thisMonth,
  TimelineBucket.earlier,
];