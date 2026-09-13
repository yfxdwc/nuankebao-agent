import 'package:freezed_annotation/freezed_annotation.dart';

part 'dashboard.freezed.dart';
part 'dashboard.g.dart';

@freezed
class DashboardStats with _$DashboardStats {
  const factory DashboardStats({
    required int customerCount,
    required int thisMonthVisits,
    required int pendingFollowUps,
    required int totalInteractions,
  }) = _DashboardStats;
  factory DashboardStats.fromJson(Map<String, dynamic> json) =>
      _$DashboardStatsFromJson(json);
}

@freezed
class ServiceDistribution with _$ServiceDistribution {
  const factory ServiceDistribution({
    required String serviceItemId,
    required int count,
  }) = _ServiceDistribution;
  factory ServiceDistribution.fromJson(Map<String, dynamic> json) =>
      _$ServiceDistributionFromJson(json);
}
