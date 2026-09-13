import 'package:freezed_annotation/freezed_annotation.dart';

part 'wellness_record.freezed.dart';
part 'wellness_record.g.dart';

@freezed
class WellnessRecord with _$WellnessRecord {
  const factory WellnessRecord({
    required String id,
    required String customerId,
    required String serviceDate, // YYYY-MM-DD
    required String serviceItemId,
    String? staffId,
    String? storeId,
    @Default([]) List<String> bodyPartIds,
    @Default([]) List<ProductUsage> productUsages,
    @Default({}) Map<String, dynamic> preCondition,
    @Default({}) Map<String, dynamic> postCondition,
    String? processNote,
    String? customerFeedback,
    @Default([]) List<String> photos,
    String? nextAdviceDate,
    required DateTime createdAt,
  }) = _WellnessRecord;

  factory WellnessRecord.fromJson(Map<String, dynamic> json) =>
      _$WellnessRecordFromJson(json);
}

@freezed
class ProductUsage with _$ProductUsage {
  const factory ProductUsage({
    required String productId,
    String? quantity,
  }) = _ProductUsage;

  factory ProductUsage.fromJson(Map<String, dynamic> json) =>
      _$ProductUsageFromJson(json);
}
