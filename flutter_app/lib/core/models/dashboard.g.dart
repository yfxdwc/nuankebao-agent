// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DashboardStatsImpl _$$DashboardStatsImplFromJson(Map<String, dynamic> json) =>
    _$DashboardStatsImpl(
      customerCount: (json['customerCount'] as num).toInt(),
      thisMonthVisits: (json['thisMonthVisits'] as num).toInt(),
      pendingFollowUps: (json['pendingFollowUps'] as num).toInt(),
      totalInteractions: (json['totalInteractions'] as num).toInt(),
    );

Map<String, dynamic> _$$DashboardStatsImplToJson(
        _$DashboardStatsImpl instance) =>
    <String, dynamic>{
      'customerCount': instance.customerCount,
      'thisMonthVisits': instance.thisMonthVisits,
      'pendingFollowUps': instance.pendingFollowUps,
      'totalInteractions': instance.totalInteractions,
    };

_$ServiceDistributionImpl _$$ServiceDistributionImplFromJson(
        Map<String, dynamic> json) =>
    _$ServiceDistributionImpl(
      serviceItemId: json['serviceItemId'] as String,
      count: (json['count'] as num).toInt(),
    );

Map<String, dynamic> _$$ServiceDistributionImplToJson(
        _$ServiceDistributionImpl instance) =>
    <String, dynamic>{
      'serviceItemId': instance.serviceItemId,
      'count': instance.count,
    };
