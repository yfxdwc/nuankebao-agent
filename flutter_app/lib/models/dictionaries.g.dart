// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dictionaries.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$BodyPartImpl _$$BodyPartImplFromJson(Map<String, dynamic> json) =>
    _$BodyPartImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
    );

Map<String, dynamic> _$$BodyPartImplToJson(_$BodyPartImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
    };

_$ServiceItemImpl _$$ServiceItemImplFromJson(Map<String, dynamic> json) =>
    _$ServiceItemImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      defaultPriceCents: (json['defaultPriceCents'] as num?)?.toInt(),
      description: json['description'] as String?,
    );

Map<String, dynamic> _$$ServiceItemImplToJson(_$ServiceItemImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'durationMinutes': instance.durationMinutes,
      'defaultPriceCents': instance.defaultPriceCents,
      'description': instance.description,
    };

_$ProductImpl _$$ProductImplFromJson(Map<String, dynamic> json) =>
    _$ProductImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      unit: json['unit'] as String?,
      description: json['description'] as String?,
    );

Map<String, dynamic> _$$ProductImplToJson(_$ProductImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'unit': instance.unit,
      'description': instance.description,
    };

_$DictionariesImpl _$$DictionariesImplFromJson(Map<String, dynamic> json) =>
    _$DictionariesImpl(
      bodyParts: (json['bodyParts'] as List<dynamic>?)
              ?.map((e) => BodyPart.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      serviceItems: (json['serviceItems'] as List<dynamic>?)
              ?.map((e) => ServiceItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      products: (json['products'] as List<dynamic>?)
              ?.map((e) => Product.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$DictionariesImplToJson(_$DictionariesImpl instance) =>
    <String, dynamic>{
      'bodyParts': instance.bodyParts,
      'serviceItems': instance.serviceItems,
      'products': instance.products,
    };
