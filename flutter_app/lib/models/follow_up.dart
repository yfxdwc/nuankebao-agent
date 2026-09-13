import 'package:freezed_annotation/freezed_annotation.dart';

part 'follow_up.freezed.dart';
part 'follow_up.g.dart';

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
