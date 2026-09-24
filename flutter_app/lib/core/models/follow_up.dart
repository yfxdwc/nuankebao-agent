import 'package:freezed_annotation/freezed_annotation.dart';

part 'follow_up.freezed.dart';
part 'follow_up.g.dart';

// ============================================
// 跟进任务 到期日 帮助函数 (2026-09-24 用户反馈)
//
// 主人原话: 「点击跟进后, 直接创建了当天的跟进任务, 并且创建时就是已过期状态。
//   当前日期的待办状态应该还没过期。」
//
// 根因 (双线):
//   1. 时间戳比较 vs 日期比较 —— 旧 `t.dueAt.isBefore(DateTime.now())` 按毫秒比,
//      后端给的 dueAt 是当下时刻 (toISOString), 建完下一秒就判"已过期",
//      但语义上"今天的待办"应该是「今天到期」而不是「已过期」。
//   2. UTC 未转本地 —— `follow_up.g.dart` 反序列化用的是 `DateTime.parse(json['dueAt'])`,
//      API 回的 ISO 字符串带 Z (UTC), 直接拿 UTC 年月日比, 在本机 CST (UTC+8)
//      的本地 00:00-08:00 会把"今天"误判成"昨天"。
//
// 后端同口径 (src/lib/follow-up/urgency.ts::daysBetween):
//   - 两侧都先把日期对齐到「日的起点」(00:00), 再算相差天数
//   - d > 0 = 已逾期; d == 0 = 今天到期; d < 0 = 未到期
//
// 因此下面 3 个函数 = Flutter 侧的同一口径:
//   ① `followUpDueDay`         本地日期的 00:00 (避开 UTC 漂移)
//   ② `followUpDaysUntilDue`   0=今天 / 1=明天 / -1=昨天
//   ③ `isFollowUpOverdue`      「日期早于今天」才算逾期 (今天/未来都不算)
//
// 所有函数都接收 `DateTime` (UTC 或 local 都行), 内部统一 `.toLocal()` 后再算日期。
// 消费方: customer_activity_cards.dart::_tile, follow_ups_page.dart::_groupOf,
//         以及所有需要判断「这单今天/明天/更远」的 UI / 排序逻辑。
// ============================================

/// 跟进任务到期日: 取本地时区的「日期」(丢掉时分秒)。
///
/// 为什么必须 `.toLocal()`:
///   API 返回的 `dueAt` 是 UTC ISO 字符串 (带 Z), freezed 反序列化成 UTC DateTime;
///   直接 `.year/.month/.day` 会拿到 UTC 那一天的年月日, 而 CST 早晨 00:00-08:00
///   看到的 UTC 还是「昨天」, 本来"今天到期"的任务会被判成"逾期"。
DateTime followUpDueDay(DateTime dueAt) {
  final local = dueAt.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 跟进任务还有几天到期。
///
///   0  → 今天到期
///   1  → 明天到期
///  -1  → 昨天 (即逾期 1 天)
///
/// `now` 默认 `DateTime.now()` (本地时区), 测试时可注入。
/// 同口径对照: src/lib/follow-up/urgency.ts::daysBetween (后端)。
int followUpDaysUntilDue(DateTime dueAt, {DateTime? now}) {
  final today = followUpDueDay(now ?? DateTime.now());
  final due = followUpDueDay(dueAt);
  return due.difference(today).inDays;
}

/// 跟进任务是否逾期。
///
///   严格按**日期**比 (不是时间戳): 「dueAt 的本地日期早于今天的本地日期」才算逾期。
///   "今天到期" 的任务 **不** 是逾期 —— 这是本次用户反馈的核心诉求。
///
/// 用法: 取代各处散落的 `t.dueAt.isBefore(DateTime.now())`。
bool isFollowUpOverdue(DateTime dueAt, {DateTime? now}) {
  return followUpDaysUntilDue(dueAt, now: now) < 0;
}

@freezed
class FollowUpTask with _$FollowUpTask {
  const factory FollowUpTask({
    required String id,
    required String customerId,
    required DateTime dueAt,
    required String reason,
    String? aiSuggestion,
    required String status, // pending / done / cancelled
    DateTime? completedAt,
    String? completedNotes,
    String? assignedTo,
    required DateTime createdAt,
  }) = _FollowUpTask;
  factory FollowUpTask.fromJson(Map<String, dynamic> json) =>
      _$FollowUpTaskFromJson(json);
}

@freezed
class Interaction with _$Interaction {
  const factory Interaction({
    required String id,
    required String customerId,
    required String type, // phone / wechat / visit / holiday_greeting / other
    String? summary,
    DateTime? followUpAt,
    required String createdBy,
    required DateTime createdAt,
  }) = _Interaction;
  factory Interaction.fromJson(Map<String, dynamic> json) =>
      _$InteractionFromJson(json);
}
