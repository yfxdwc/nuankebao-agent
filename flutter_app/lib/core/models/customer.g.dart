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
      birthMonth: (json['birthMonth'] as num?)?.toInt(),
      birthDay: (json['birthDay'] as num?)?.toInt(),
      birthCalendar: json['birthCalendar'] as String? ?? 'solar',
      birthdayRemindDays: (json['birthdayRemindDays'] as num?)?.toInt(),
      healthTags: (json['healthTags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      diseaseHistory: json['diseaseHistory'] as String?,
      allergyHistory: json['allergyHistory'] as String?,
      notes: json['notes'] as String?,
      referrerId: json['referrerId'] as String?,
      isSeed: json['isSeed'] as bool? ?? false,
      customerType: json['customerType'] as String? ?? 'normal',
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
      'birthMonth': instance.birthMonth,
      'birthDay': instance.birthDay,
      'birthCalendar': instance.birthCalendar,
      'birthdayRemindDays': instance.birthdayRemindDays,
      'healthTags': instance.healthTags,
      'diseaseHistory': instance.diseaseHistory,
      'allergyHistory': instance.allergyHistory,
      'notes': instance.notes,
      'referrerId': instance.referrerId,
      'isSeed': instance.isSeed,
      'customerType': instance.customerType,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
