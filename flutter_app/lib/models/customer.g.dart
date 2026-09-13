// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CustomerImpl _$$CustomerImplFromJson(Map<String, dynamic> json) =>
    _$CustomerImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      gender: json['gender'] as String?,
      birthYear: (json['birthYear'] as num?)?.toInt(),
      healthTags: (json['healthTags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      diseaseHistory: json['diseaseHistory'] as String?,
      notes: json['notes'] as String?,
      referrerId: json['referrerId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$$CustomerImplToJson(_$CustomerImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'phone': instance.phone,
      'gender': instance.gender,
      'birthYear': instance.birthYear,
      'healthTags': instance.healthTags,
      'diseaseHistory': instance.diseaseHistory,
      'notes': instance.notes,
      'referrerId': instance.referrerId,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
