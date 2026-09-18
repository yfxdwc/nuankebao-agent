// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'follow_up.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$FollowUpTaskImpl _$$FollowUpTaskImplFromJson(Map<String, dynamic> json) =>
    _$FollowUpTaskImpl(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      dueAt: DateTime.parse(json['dueAt'] as String),
      reason: json['reason'] as String,
      aiSuggestion: json['aiSuggestion'] as String?,
      status: json['status'] as String,
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      completedNotes: json['completedNotes'] as String?,
      assignedTo: json['assignedTo'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$$FollowUpTaskImplToJson(_$FollowUpTaskImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'customerId': instance.customerId,
      'dueAt': instance.dueAt.toIso8601String(),
      'reason': instance.reason,
      'aiSuggestion': instance.aiSuggestion,
      'status': instance.status,
      'completedAt': instance.completedAt?.toIso8601String(),
      'completedNotes': instance.completedNotes,
      'assignedTo': instance.assignedTo,
      'createdAt': instance.createdAt.toIso8601String(),
    };

_$InteractionImpl _$$InteractionImplFromJson(Map<String, dynamic> json) =>
    _$InteractionImpl(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      type: json['type'] as String,
      summary: json['summary'] as String?,
      followUpAt: json['followUpAt'] == null
          ? null
          : DateTime.parse(json['followUpAt'] as String),
      createdBy: json['createdBy'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$$InteractionImplToJson(_$InteractionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'customerId': instance.customerId,
      'type': instance.type,
      'summary': instance.summary,
      'followUpAt': instance.followUpAt?.toIso8601String(),
      'createdBy': instance.createdBy,
      'createdAt': instance.createdAt.toIso8601String(),
    };
