// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dictionaries.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

BodyPart _$BodyPartFromJson(Map<String, dynamic> json) {
  return _BodyPart.fromJson(json);
}

/// @nodoc
mixin _$BodyPart {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;

  /// Serializes this BodyPart to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of BodyPart
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BodyPartCopyWith<BodyPart> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BodyPartCopyWith<$Res> {
  factory $BodyPartCopyWith(BodyPart value, $Res Function(BodyPart) then) =
      _$BodyPartCopyWithImpl<$Res, BodyPart>;
  @useResult
  $Res call({String id, String name, String? description});
}

/// @nodoc
class _$BodyPartCopyWithImpl<$Res, $Val extends BodyPart>
    implements $BodyPartCopyWith<$Res> {
  _$BodyPartCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BodyPart
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BodyPartImplCopyWith<$Res>
    implements $BodyPartCopyWith<$Res> {
  factory _$$BodyPartImplCopyWith(
          _$BodyPartImpl value, $Res Function(_$BodyPartImpl) then) =
      __$$BodyPartImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String name, String? description});
}

/// @nodoc
class __$$BodyPartImplCopyWithImpl<$Res>
    extends _$BodyPartCopyWithImpl<$Res, _$BodyPartImpl>
    implements _$$BodyPartImplCopyWith<$Res> {
  __$$BodyPartImplCopyWithImpl(
      _$BodyPartImpl _value, $Res Function(_$BodyPartImpl) _then)
      : super(_value, _then);

  /// Create a copy of BodyPart
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
  }) {
    return _then(_$BodyPartImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BodyPartImpl implements _BodyPart {
  const _$BodyPartImpl(
      {required this.id, required this.name, this.description});

  factory _$BodyPartImpl.fromJson(Map<String, dynamic> json) =>
      _$$BodyPartImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? description;

  @override
  String toString() {
    return 'BodyPart(id: $id, name: $name, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BodyPartImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, description);

  /// Create a copy of BodyPart
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BodyPartImplCopyWith<_$BodyPartImpl> get copyWith =>
      __$$BodyPartImplCopyWithImpl<_$BodyPartImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BodyPartImplToJson(
      this,
    );
  }
}

abstract class _BodyPart implements BodyPart {
  const factory _BodyPart(
      {required final String id,
      required final String name,
      final String? description}) = _$BodyPartImpl;

  factory _BodyPart.fromJson(Map<String, dynamic> json) =
      _$BodyPartImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get description;

  /// Create a copy of BodyPart
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BodyPartImplCopyWith<_$BodyPartImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ServiceItem _$ServiceItemFromJson(Map<String, dynamic> json) {
  return _ServiceItem.fromJson(json);
}

/// @nodoc
mixin _$ServiceItem {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  int? get durationMinutes => throw _privateConstructorUsedError;
  int? get defaultPriceCents => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;

  /// Serializes this ServiceItem to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ServiceItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ServiceItemCopyWith<ServiceItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ServiceItemCopyWith<$Res> {
  factory $ServiceItemCopyWith(
          ServiceItem value, $Res Function(ServiceItem) then) =
      _$ServiceItemCopyWithImpl<$Res, ServiceItem>;
  @useResult
  $Res call(
      {String id,
      String name,
      int? durationMinutes,
      int? defaultPriceCents,
      String? description});
}

/// @nodoc
class _$ServiceItemCopyWithImpl<$Res, $Val extends ServiceItem>
    implements $ServiceItemCopyWith<$Res> {
  _$ServiceItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ServiceItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? durationMinutes = freezed,
    Object? defaultPriceCents = freezed,
    Object? description = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      durationMinutes: freezed == durationMinutes
          ? _value.durationMinutes
          : durationMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
      defaultPriceCents: freezed == defaultPriceCents
          ? _value.defaultPriceCents
          : defaultPriceCents // ignore: cast_nullable_to_non_nullable
              as int?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ServiceItemImplCopyWith<$Res>
    implements $ServiceItemCopyWith<$Res> {
  factory _$$ServiceItemImplCopyWith(
          _$ServiceItemImpl value, $Res Function(_$ServiceItemImpl) then) =
      __$$ServiceItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      int? durationMinutes,
      int? defaultPriceCents,
      String? description});
}

/// @nodoc
class __$$ServiceItemImplCopyWithImpl<$Res>
    extends _$ServiceItemCopyWithImpl<$Res, _$ServiceItemImpl>
    implements _$$ServiceItemImplCopyWith<$Res> {
  __$$ServiceItemImplCopyWithImpl(
      _$ServiceItemImpl _value, $Res Function(_$ServiceItemImpl) _then)
      : super(_value, _then);

  /// Create a copy of ServiceItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? durationMinutes = freezed,
    Object? defaultPriceCents = freezed,
    Object? description = freezed,
  }) {
    return _then(_$ServiceItemImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      durationMinutes: freezed == durationMinutes
          ? _value.durationMinutes
          : durationMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
      defaultPriceCents: freezed == defaultPriceCents
          ? _value.defaultPriceCents
          : defaultPriceCents // ignore: cast_nullable_to_non_nullable
              as int?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ServiceItemImpl implements _ServiceItem {
  const _$ServiceItemImpl(
      {required this.id,
      required this.name,
      this.durationMinutes,
      this.defaultPriceCents,
      this.description});

  factory _$ServiceItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$ServiceItemImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final int? durationMinutes;
  @override
  final int? defaultPriceCents;
  @override
  final String? description;

  @override
  String toString() {
    return 'ServiceItem(id: $id, name: $name, durationMinutes: $durationMinutes, defaultPriceCents: $defaultPriceCents, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ServiceItemImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.durationMinutes, durationMinutes) ||
                other.durationMinutes == durationMinutes) &&
            (identical(other.defaultPriceCents, defaultPriceCents) ||
                other.defaultPriceCents == defaultPriceCents) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, name, durationMinutes, defaultPriceCents, description);

  /// Create a copy of ServiceItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ServiceItemImplCopyWith<_$ServiceItemImpl> get copyWith =>
      __$$ServiceItemImplCopyWithImpl<_$ServiceItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ServiceItemImplToJson(
      this,
    );
  }
}

abstract class _ServiceItem implements ServiceItem {
  const factory _ServiceItem(
      {required final String id,
      required final String name,
      final int? durationMinutes,
      final int? defaultPriceCents,
      final String? description}) = _$ServiceItemImpl;

  factory _ServiceItem.fromJson(Map<String, dynamic> json) =
      _$ServiceItemImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  int? get durationMinutes;
  @override
  int? get defaultPriceCents;
  @override
  String? get description;

  /// Create a copy of ServiceItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ServiceItemImplCopyWith<_$ServiceItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Product _$ProductFromJson(Map<String, dynamic> json) {
  return _Product.fromJson(json);
}

/// @nodoc
mixin _$Product {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get unit => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;

  /// Serializes this Product to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Product
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProductCopyWith<Product> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProductCopyWith<$Res> {
  factory $ProductCopyWith(Product value, $Res Function(Product) then) =
      _$ProductCopyWithImpl<$Res, Product>;
  @useResult
  $Res call({String id, String name, String? unit, String? description});
}

/// @nodoc
class _$ProductCopyWithImpl<$Res, $Val extends Product>
    implements $ProductCopyWith<$Res> {
  _$ProductCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Product
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? unit = freezed,
    Object? description = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      unit: freezed == unit
          ? _value.unit
          : unit // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ProductImplCopyWith<$Res> implements $ProductCopyWith<$Res> {
  factory _$$ProductImplCopyWith(
          _$ProductImpl value, $Res Function(_$ProductImpl) then) =
      __$$ProductImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String name, String? unit, String? description});
}

/// @nodoc
class __$$ProductImplCopyWithImpl<$Res>
    extends _$ProductCopyWithImpl<$Res, _$ProductImpl>
    implements _$$ProductImplCopyWith<$Res> {
  __$$ProductImplCopyWithImpl(
      _$ProductImpl _value, $Res Function(_$ProductImpl) _then)
      : super(_value, _then);

  /// Create a copy of Product
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? unit = freezed,
    Object? description = freezed,
  }) {
    return _then(_$ProductImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      unit: freezed == unit
          ? _value.unit
          : unit // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ProductImpl implements _Product {
  const _$ProductImpl(
      {required this.id, required this.name, this.unit, this.description});

  factory _$ProductImpl.fromJson(Map<String, dynamic> json) =>
      _$$ProductImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? unit;
  @override
  final String? description;

  @override
  String toString() {
    return 'Product(id: $id, name: $name, unit: $unit, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProductImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.unit, unit) || other.unit == unit) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, unit, description);

  /// Create a copy of Product
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProductImplCopyWith<_$ProductImpl> get copyWith =>
      __$$ProductImplCopyWithImpl<_$ProductImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ProductImplToJson(
      this,
    );
  }
}

abstract class _Product implements Product {
  const factory _Product(
      {required final String id,
      required final String name,
      final String? unit,
      final String? description}) = _$ProductImpl;

  factory _Product.fromJson(Map<String, dynamic> json) = _$ProductImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get unit;
  @override
  String? get description;

  /// Create a copy of Product
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProductImplCopyWith<_$ProductImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Dictionaries _$DictionariesFromJson(Map<String, dynamic> json) {
  return _Dictionaries.fromJson(json);
}

/// @nodoc
mixin _$Dictionaries {
  List<BodyPart> get bodyParts => throw _privateConstructorUsedError;
  List<ServiceItem> get serviceItems => throw _privateConstructorUsedError;
  List<Product> get products => throw _privateConstructorUsedError;

  /// Serializes this Dictionaries to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Dictionaries
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DictionariesCopyWith<Dictionaries> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DictionariesCopyWith<$Res> {
  factory $DictionariesCopyWith(
          Dictionaries value, $Res Function(Dictionaries) then) =
      _$DictionariesCopyWithImpl<$Res, Dictionaries>;
  @useResult
  $Res call(
      {List<BodyPart> bodyParts,
      List<ServiceItem> serviceItems,
      List<Product> products});
}

/// @nodoc
class _$DictionariesCopyWithImpl<$Res, $Val extends Dictionaries>
    implements $DictionariesCopyWith<$Res> {
  _$DictionariesCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Dictionaries
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bodyParts = null,
    Object? serviceItems = null,
    Object? products = null,
  }) {
    return _then(_value.copyWith(
      bodyParts: null == bodyParts
          ? _value.bodyParts
          : bodyParts // ignore: cast_nullable_to_non_nullable
              as List<BodyPart>,
      serviceItems: null == serviceItems
          ? _value.serviceItems
          : serviceItems // ignore: cast_nullable_to_non_nullable
              as List<ServiceItem>,
      products: null == products
          ? _value.products
          : products // ignore: cast_nullable_to_non_nullable
              as List<Product>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DictionariesImplCopyWith<$Res>
    implements $DictionariesCopyWith<$Res> {
  factory _$$DictionariesImplCopyWith(
          _$DictionariesImpl value, $Res Function(_$DictionariesImpl) then) =
      __$$DictionariesImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<BodyPart> bodyParts,
      List<ServiceItem> serviceItems,
      List<Product> products});
}

/// @nodoc
class __$$DictionariesImplCopyWithImpl<$Res>
    extends _$DictionariesCopyWithImpl<$Res, _$DictionariesImpl>
    implements _$$DictionariesImplCopyWith<$Res> {
  __$$DictionariesImplCopyWithImpl(
      _$DictionariesImpl _value, $Res Function(_$DictionariesImpl) _then)
      : super(_value, _then);

  /// Create a copy of Dictionaries
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bodyParts = null,
    Object? serviceItems = null,
    Object? products = null,
  }) {
    return _then(_$DictionariesImpl(
      bodyParts: null == bodyParts
          ? _value._bodyParts
          : bodyParts // ignore: cast_nullable_to_non_nullable
              as List<BodyPart>,
      serviceItems: null == serviceItems
          ? _value._serviceItems
          : serviceItems // ignore: cast_nullable_to_non_nullable
              as List<ServiceItem>,
      products: null == products
          ? _value._products
          : products // ignore: cast_nullable_to_non_nullable
              as List<Product>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DictionariesImpl implements _Dictionaries {
  const _$DictionariesImpl(
      {final List<BodyPart> bodyParts = const [],
      final List<ServiceItem> serviceItems = const [],
      final List<Product> products = const []})
      : _bodyParts = bodyParts,
        _serviceItems = serviceItems,
        _products = products;

  factory _$DictionariesImpl.fromJson(Map<String, dynamic> json) =>
      _$$DictionariesImplFromJson(json);

  final List<BodyPart> _bodyParts;
  @override
  @JsonKey()
  List<BodyPart> get bodyParts {
    if (_bodyParts is EqualUnmodifiableListView) return _bodyParts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_bodyParts);
  }

  final List<ServiceItem> _serviceItems;
  @override
  @JsonKey()
  List<ServiceItem> get serviceItems {
    if (_serviceItems is EqualUnmodifiableListView) return _serviceItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_serviceItems);
  }

  final List<Product> _products;
  @override
  @JsonKey()
  List<Product> get products {
    if (_products is EqualUnmodifiableListView) return _products;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_products);
  }

  @override
  String toString() {
    return 'Dictionaries(bodyParts: $bodyParts, serviceItems: $serviceItems, products: $products)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DictionariesImpl &&
            const DeepCollectionEquality()
                .equals(other._bodyParts, _bodyParts) &&
            const DeepCollectionEquality()
                .equals(other._serviceItems, _serviceItems) &&
            const DeepCollectionEquality().equals(other._products, _products));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_bodyParts),
      const DeepCollectionEquality().hash(_serviceItems),
      const DeepCollectionEquality().hash(_products));

  /// Create a copy of Dictionaries
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DictionariesImplCopyWith<_$DictionariesImpl> get copyWith =>
      __$$DictionariesImplCopyWithImpl<_$DictionariesImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DictionariesImplToJson(
      this,
    );
  }
}

abstract class _Dictionaries implements Dictionaries {
  const factory _Dictionaries(
      {final List<BodyPart> bodyParts,
      final List<ServiceItem> serviceItems,
      final List<Product> products}) = _$DictionariesImpl;

  factory _Dictionaries.fromJson(Map<String, dynamic> json) =
      _$DictionariesImpl.fromJson;

  @override
  List<BodyPart> get bodyParts;
  @override
  List<ServiceItem> get serviceItems;
  @override
  List<Product> get products;

  /// Create a copy of Dictionaries
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DictionariesImplCopyWith<_$DictionariesImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
