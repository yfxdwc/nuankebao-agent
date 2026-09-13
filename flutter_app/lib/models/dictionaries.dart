import 'package:freezed_annotation/freezed_annotation.dart';

part 'dictionaries.freezed.dart';
part 'dictionaries.g.dart';

@freezed
class BodyPart with _$BodyPart {
  const factory BodyPart({required String id, required String name, String? description}) =
      _BodyPart;
  factory BodyPart.fromJson(Map<String, dynamic> json) =>
      _$BodyPartFromJson(json);
}

@freezed
class ServiceItem with _$ServiceItem {
  const factory ServiceItem({
    required String id,
    required String name,
    int? durationMinutes,
    int? defaultPriceCents,
    String? description,
  }) = _ServiceItem;
  factory ServiceItem.fromJson(Map<String, dynamic> json) =>
      _$ServiceItemFromJson(json);
}

@freezed
class Product with _$Product {
  const factory Product({
    required String id,
    required String name,
    String? unit,
    String? description,
  }) = _Product;
  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);
}

@freezed
class Dictionaries with _$Dictionaries {
  const factory Dictionaries({
    @Default([]) List<BodyPart> bodyParts,
    @Default([]) List<ServiceItem> serviceItems,
    @Default([]) List<Product> products,
  }) = _Dictionaries;
  factory Dictionaries.fromJson(Map<String, dynamic> json) =>
      _$DictionariesFromJson(json);
}
