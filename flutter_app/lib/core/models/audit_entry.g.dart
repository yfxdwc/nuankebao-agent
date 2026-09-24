// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AuditEntryImpl _$$AuditEntryImplFromJson(Map<String, dynamic> json) =>
    _$AuditEntryImpl(
      id: json['id'] as String,
      operation: json['operation'] as String,
      changedColumns: (json['changedColumns'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      actorName: json['actorName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$$AuditEntryImplToJson(_$AuditEntryImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'operation': instance.operation,
      'changedColumns': instance.changedColumns,
      'actorName': instance.actorName,
      'createdAt': instance.createdAt.toIso8601String(),
    };
