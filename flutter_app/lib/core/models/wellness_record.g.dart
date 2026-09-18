// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wellness_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WellnessRecordImpl _$$WellnessRecordImplFromJson(Map<String, dynamic> json) =>
    _$WellnessRecordImpl(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      serviceDate: json['serviceDate'] as String,
      serviceItemId: json['serviceItemId'] as String,
      staffId: json['staffId'] as String?,
      storeId: json['storeId'] as String?,
      bodyPartIds: (json['bodyPartIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      productUsages: (json['productUsages'] as List<dynamic>?)
              ?.map((e) => ProductUsage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      preCondition: json['preCondition'] as Map<String, dynamic>? ?? const {},
      postCondition: json['postCondition'] as Map<String, dynamic>? ?? const {},
      processNote: json['processNote'] as String?,
      customerFeedback: json['customerFeedback'] as String?,
      photos: (json['photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      nextAdviceDate: json['nextAdviceDate'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$$WellnessRecordImplToJson(
        _$WellnessRecordImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'customerId': instance.customerId,
      'serviceDate': instance.serviceDate,
      'serviceItemId': instance.serviceItemId,
      'staffId': instance.staffId,
      'storeId': instance.storeId,
      'bodyPartIds': instance.bodyPartIds,
      'productUsages': instance.productUsages,
      'preCondition': instance.preCondition,
      'postCondition': instance.postCondition,
      'processNote': instance.processNote,
      'customerFeedback': instance.customerFeedback,
      'photos': instance.photos,
      'nextAdviceDate': instance.nextAdviceDate,
      'createdAt': instance.createdAt.toIso8601String(),
    };

_$ProductUsageImpl _$$ProductUsageImplFromJson(Map<String, dynamic> json) =>
    _$ProductUsageImpl(
      productId: json['productId'] as String,
      quantity: json['quantity'] as String?,
    );

Map<String, dynamic> _$$ProductUsageImplToJson(_$ProductUsageImpl instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'quantity': instance.quantity,
    };
