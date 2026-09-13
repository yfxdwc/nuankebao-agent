// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'wellness_record.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WellnessRecord _$WellnessRecordFromJson(Map<String, dynamic> json) {
  return _WellnessRecord.fromJson(json);
}

/// @nodoc
mixin _$WellnessRecord {
  String get id => throw _privateConstructorUsedError;
  String get customerId => throw _privateConstructorUsedError;
  String get serviceDate => throw _privateConstructorUsedError; // YYYY-MM-DD
  String get serviceItemId => throw _privateConstructorUsedError;
  String? get staffId => throw _privateConstructorUsedError;
  String? get storeId => throw _privateConstructorUsedError;
  List<String> get bodyPartIds => throw _privateConstructorUsedError;
  List<ProductUsage> get productUsages => throw _privateConstructorUsedError;
  Map<String, dynamic> get preCondition => throw _privateConstructorUsedError;
  Map<String, dynamic> get postCondition => throw _privateConstructorUsedError;
  String? get processNote => throw _privateConstructorUsedError;
  String? get customerFeedback => throw _privateConstructorUsedError;
  List<String> get photos => throw _privateConstructorUsedError;
  String? get nextAdviceDate => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this WellnessRecord to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of WellnessRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $WellnessRecordCopyWith<WellnessRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WellnessRecordCopyWith<$Res> {
  factory $WellnessRecordCopyWith(
          WellnessRecord value, $Res Function(WellnessRecord) then) =
      _$WellnessRecordCopyWithImpl<$Res, WellnessRecord>;
  @useResult
  $Res call(
      {String id,
      String customerId,
      String serviceDate,
      String serviceItemId,
      String? staffId,
      String? storeId,
      List<String> bodyPartIds,
      List<ProductUsage> productUsages,
      Map<String, dynamic> preCondition,
      Map<String, dynamic> postCondition,
      String? processNote,
      String? customerFeedback,
      List<String> photos,
      String? nextAdviceDate,
      DateTime createdAt});
}

/// @nodoc
class _$WellnessRecordCopyWithImpl<$Res, $Val extends WellnessRecord>
    implements $WellnessRecordCopyWith<$Res> {
  _$WellnessRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of WellnessRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? serviceDate = null,
    Object? serviceItemId = null,
    Object? staffId = freezed,
    Object? storeId = freezed,
    Object? bodyPartIds = null,
    Object? productUsages = null,
    Object? preCondition = null,
    Object? postCondition = null,
    Object? processNote = freezed,
    Object? customerFeedback = freezed,
    Object? photos = null,
    Object? nextAdviceDate = freezed,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      customerId: null == customerId
          ? _value.customerId
          : customerId // ignore: cast_nullable_to_non_nullable
              as String,
      serviceDate: null == serviceDate
          ? _value.serviceDate
          : serviceDate // ignore: cast_nullable_to_non_nullable
              as String,
      serviceItemId: null == serviceItemId
          ? _value.serviceItemId
          : serviceItemId // ignore: cast_nullable_to_non_nullable
              as String,
      staffId: freezed == staffId
          ? _value.staffId
          : staffId // ignore: cast_nullable_to_non_nullable
              as String?,
      storeId: freezed == storeId
          ? _value.storeId
          : storeId // ignore: cast_nullable_to_non_nullable
              as String?,
      bodyPartIds: null == bodyPartIds
          ? _value.bodyPartIds
          : bodyPartIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      productUsages: null == productUsages
          ? _value.productUsages
          : productUsages // ignore: cast_nullable_to_non_nullable
              as List<ProductUsage>,
      preCondition: null == preCondition
          ? _value.preCondition
          : preCondition // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      postCondition: null == postCondition
          ? _value.postCondition
          : postCondition // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      processNote: freezed == processNote
          ? _value.processNote
          : processNote // ignore: cast_nullable_to_non_nullable
              as String?,
      customerFeedback: freezed == customerFeedback
          ? _value.customerFeedback
          : customerFeedback // ignore: cast_nullable_to_non_nullable
              as String?,
      photos: null == photos
          ? _value.photos
          : photos // ignore: cast_nullable_to_non_nullable
              as List<String>,
      nextAdviceDate: freezed == nextAdviceDate
          ? _value.nextAdviceDate
          : nextAdviceDate // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WellnessRecordImplCopyWith<$Res>
    implements $WellnessRecordCopyWith<$Res> {
  factory _$$WellnessRecordImplCopyWith(_$WellnessRecordImpl value,
          $Res Function(_$WellnessRecordImpl) then) =
      __$$WellnessRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String customerId,
      String serviceDate,
      String serviceItemId,
      String? staffId,
      String? storeId,
      List<String> bodyPartIds,
      List<ProductUsage> productUsages,
      Map<String, dynamic> preCondition,
      Map<String, dynamic> postCondition,
      String? processNote,
      String? customerFeedback,
      List<String> photos,
      String? nextAdviceDate,
      DateTime createdAt});
}

/// @nodoc
class __$$WellnessRecordImplCopyWithImpl<$Res>
    extends _$WellnessRecordCopyWithImpl<$Res, _$WellnessRecordImpl>
    implements _$$WellnessRecordImplCopyWith<$Res> {
  __$$WellnessRecordImplCopyWithImpl(
      _$WellnessRecordImpl _value, $Res Function(_$WellnessRecordImpl) _then)
      : super(_value, _then);

  /// Create a copy of WellnessRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? serviceDate = null,
    Object? serviceItemId = null,
    Object? staffId = freezed,
    Object? storeId = freezed,
    Object? bodyPartIds = null,
    Object? productUsages = null,
    Object? preCondition = null,
    Object? postCondition = null,
    Object? processNote = freezed,
    Object? customerFeedback = freezed,
    Object? photos = null,
    Object? nextAdviceDate = freezed,
    Object? createdAt = null,
  }) {
    return _then(_$WellnessRecordImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      customerId: null == customerId
          ? _value.customerId
          : customerId // ignore: cast_nullable_to_non_nullable
              as String,
      serviceDate: null == serviceDate
          ? _value.serviceDate
          : serviceDate // ignore: cast_nullable_to_non_nullable
              as String,
      serviceItemId: null == serviceItemId
          ? _value.serviceItemId
          : serviceItemId // ignore: cast_nullable_to_non_nullable
              as String,
      staffId: freezed == staffId
          ? _value.staffId
          : staffId // ignore: cast_nullable_to_non_nullable
              as String?,
      storeId: freezed == storeId
          ? _value.storeId
          : storeId // ignore: cast_nullable_to_non_nullable
              as String?,
      bodyPartIds: null == bodyPartIds
          ? _value._bodyPartIds
          : bodyPartIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      productUsages: null == productUsages
          ? _value._productUsages
          : productUsages // ignore: cast_nullable_to_non_nullable
              as List<ProductUsage>,
      preCondition: null == preCondition
          ? _value._preCondition
          : preCondition // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      postCondition: null == postCondition
          ? _value._postCondition
          : postCondition // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      processNote: freezed == processNote
          ? _value.processNote
          : processNote // ignore: cast_nullable_to_non_nullable
              as String?,
      customerFeedback: freezed == customerFeedback
          ? _value.customerFeedback
          : customerFeedback // ignore: cast_nullable_to_non_nullable
              as String?,
      photos: null == photos
          ? _value._photos
          : photos // ignore: cast_nullable_to_non_nullable
              as List<String>,
      nextAdviceDate: freezed == nextAdviceDate
          ? _value.nextAdviceDate
          : nextAdviceDate // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WellnessRecordImpl implements _WellnessRecord {
  const _$WellnessRecordImpl(
      {required this.id,
      required this.customerId,
      required this.serviceDate,
      required this.serviceItemId,
      this.staffId,
      this.storeId,
      final List<String> bodyPartIds = const [],
      final List<ProductUsage> productUsages = const [],
      final Map<String, dynamic> preCondition = const {},
      final Map<String, dynamic> postCondition = const {},
      this.processNote,
      this.customerFeedback,
      final List<String> photos = const [],
      this.nextAdviceDate,
      required this.createdAt})
      : _bodyPartIds = bodyPartIds,
        _productUsages = productUsages,
        _preCondition = preCondition,
        _postCondition = postCondition,
        _photos = photos;

  factory _$WellnessRecordImpl.fromJson(Map<String, dynamic> json) =>
      _$$WellnessRecordImplFromJson(json);

  @override
  final String id;
  @override
  final String customerId;
  @override
  final String serviceDate;
// YYYY-MM-DD
  @override
  final String serviceItemId;
  @override
  final String? staffId;
  @override
  final String? storeId;
  final List<String> _bodyPartIds;
  @override
  @JsonKey()
  List<String> get bodyPartIds {
    if (_bodyPartIds is EqualUnmodifiableListView) return _bodyPartIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_bodyPartIds);
  }

  final List<ProductUsage> _productUsages;
  @override
  @JsonKey()
  List<ProductUsage> get productUsages {
    if (_productUsages is EqualUnmodifiableListView) return _productUsages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_productUsages);
  }

  final Map<String, dynamic> _preCondition;
  @override
  @JsonKey()
  Map<String, dynamic> get preCondition {
    if (_preCondition is EqualUnmodifiableMapView) return _preCondition;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_preCondition);
  }

  final Map<String, dynamic> _postCondition;
  @override
  @JsonKey()
  Map<String, dynamic> get postCondition {
    if (_postCondition is EqualUnmodifiableMapView) return _postCondition;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_postCondition);
  }

  @override
  final String? processNote;
  @override
  final String? customerFeedback;
  final List<String> _photos;
  @override
  @JsonKey()
  List<String> get photos {
    if (_photos is EqualUnmodifiableListView) return _photos;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_photos);
  }

  @override
  final String? nextAdviceDate;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'WellnessRecord(id: $id, customerId: $customerId, serviceDate: $serviceDate, serviceItemId: $serviceItemId, staffId: $staffId, storeId: $storeId, bodyPartIds: $bodyPartIds, productUsages: $productUsages, preCondition: $preCondition, postCondition: $postCondition, processNote: $processNote, customerFeedback: $customerFeedback, photos: $photos, nextAdviceDate: $nextAdviceDate, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WellnessRecordImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.customerId, customerId) ||
                other.customerId == customerId) &&
            (identical(other.serviceDate, serviceDate) ||
                other.serviceDate == serviceDate) &&
            (identical(other.serviceItemId, serviceItemId) ||
                other.serviceItemId == serviceItemId) &&
            (identical(other.staffId, staffId) || other.staffId == staffId) &&
            (identical(other.storeId, storeId) || other.storeId == storeId) &&
            const DeepCollectionEquality()
                .equals(other._bodyPartIds, _bodyPartIds) &&
            const DeepCollectionEquality()
                .equals(other._productUsages, _productUsages) &&
            const DeepCollectionEquality()
                .equals(other._preCondition, _preCondition) &&
            const DeepCollectionEquality()
                .equals(other._postCondition, _postCondition) &&
            (identical(other.processNote, processNote) ||
                other.processNote == processNote) &&
            (identical(other.customerFeedback, customerFeedback) ||
                other.customerFeedback == customerFeedback) &&
            const DeepCollectionEquality().equals(other._photos, _photos) &&
            (identical(other.nextAdviceDate, nextAdviceDate) ||
                other.nextAdviceDate == nextAdviceDate) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      customerId,
      serviceDate,
      serviceItemId,
      staffId,
      storeId,
      const DeepCollectionEquality().hash(_bodyPartIds),
      const DeepCollectionEquality().hash(_productUsages),
      const DeepCollectionEquality().hash(_preCondition),
      const DeepCollectionEquality().hash(_postCondition),
      processNote,
      customerFeedback,
      const DeepCollectionEquality().hash(_photos),
      nextAdviceDate,
      createdAt);

  /// Create a copy of WellnessRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WellnessRecordImplCopyWith<_$WellnessRecordImpl> get copyWith =>
      __$$WellnessRecordImplCopyWithImpl<_$WellnessRecordImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WellnessRecordImplToJson(
      this,
    );
  }
}

abstract class _WellnessRecord implements WellnessRecord {
  const factory _WellnessRecord(
      {required final String id,
      required final String customerId,
      required final String serviceDate,
      required final String serviceItemId,
      final String? staffId,
      final String? storeId,
      final List<String> bodyPartIds,
      final List<ProductUsage> productUsages,
      final Map<String, dynamic> preCondition,
      final Map<String, dynamic> postCondition,
      final String? processNote,
      final String? customerFeedback,
      final List<String> photos,
      final String? nextAdviceDate,
      required final DateTime createdAt}) = _$WellnessRecordImpl;

  factory _WellnessRecord.fromJson(Map<String, dynamic> json) =
      _$WellnessRecordImpl.fromJson;

  @override
  String get id;
  @override
  String get customerId;
  @override
  String get serviceDate; // YYYY-MM-DD
  @override
  String get serviceItemId;
  @override
  String? get staffId;
  @override
  String? get storeId;
  @override
  List<String> get bodyPartIds;
  @override
  List<ProductUsage> get productUsages;
  @override
  Map<String, dynamic> get preCondition;
  @override
  Map<String, dynamic> get postCondition;
  @override
  String? get processNote;
  @override
  String? get customerFeedback;
  @override
  List<String> get photos;
  @override
  String? get nextAdviceDate;
  @override
  DateTime get createdAt;

  /// Create a copy of WellnessRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WellnessRecordImplCopyWith<_$WellnessRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ProductUsage _$ProductUsageFromJson(Map<String, dynamic> json) {
  return _ProductUsage.fromJson(json);
}

/// @nodoc
mixin _$ProductUsage {
  String get productId => throw _privateConstructorUsedError;
  String? get quantity => throw _privateConstructorUsedError;

  /// Serializes this ProductUsage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ProductUsage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProductUsageCopyWith<ProductUsage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProductUsageCopyWith<$Res> {
  factory $ProductUsageCopyWith(
          ProductUsage value, $Res Function(ProductUsage) then) =
      _$ProductUsageCopyWithImpl<$Res, ProductUsage>;
  @useResult
  $Res call({String productId, String? quantity});
}

/// @nodoc
class _$ProductUsageCopyWithImpl<$Res, $Val extends ProductUsage>
    implements $ProductUsageCopyWith<$Res> {
  _$ProductUsageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ProductUsage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? productId = null,
    Object? quantity = freezed,
  }) {
    return _then(_value.copyWith(
      productId: null == productId
          ? _value.productId
          : productId // ignore: cast_nullable_to_non_nullable
              as String,
      quantity: freezed == quantity
          ? _value.quantity
          : quantity // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ProductUsageImplCopyWith<$Res>
    implements $ProductUsageCopyWith<$Res> {
  factory _$$ProductUsageImplCopyWith(
          _$ProductUsageImpl value, $Res Function(_$ProductUsageImpl) then) =
      __$$ProductUsageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String productId, String? quantity});
}

/// @nodoc
class __$$ProductUsageImplCopyWithImpl<$Res>
    extends _$ProductUsageCopyWithImpl<$Res, _$ProductUsageImpl>
    implements _$$ProductUsageImplCopyWith<$Res> {
  __$$ProductUsageImplCopyWithImpl(
      _$ProductUsageImpl _value, $Res Function(_$ProductUsageImpl) _then)
      : super(_value, _then);

  /// Create a copy of ProductUsage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? productId = null,
    Object? quantity = freezed,
  }) {
    return _then(_$ProductUsageImpl(
      productId: null == productId
          ? _value.productId
          : productId // ignore: cast_nullable_to_non_nullable
              as String,
      quantity: freezed == quantity
          ? _value.quantity
          : quantity // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ProductUsageImpl implements _ProductUsage {
  const _$ProductUsageImpl({required this.productId, this.quantity});

  factory _$ProductUsageImpl.fromJson(Map<String, dynamic> json) =>
      _$$ProductUsageImplFromJson(json);

  @override
  final String productId;
  @override
  final String? quantity;

  @override
  String toString() {
    return 'ProductUsage(productId: $productId, quantity: $quantity)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProductUsageImpl &&
            (identical(other.productId, productId) ||
                other.productId == productId) &&
            (identical(other.quantity, quantity) ||
                other.quantity == quantity));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, productId, quantity);

  /// Create a copy of ProductUsage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProductUsageImplCopyWith<_$ProductUsageImpl> get copyWith =>
      __$$ProductUsageImplCopyWithImpl<_$ProductUsageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ProductUsageImplToJson(
      this,
    );
  }
}

abstract class _ProductUsage implements ProductUsage {
  const factory _ProductUsage(
      {required final String productId,
      final String? quantity}) = _$ProductUsageImpl;

  factory _ProductUsage.fromJson(Map<String, dynamic> json) =
      _$ProductUsageImpl.fromJson;

  @override
  String get productId;
  @override
  String? get quantity;

  /// Create a copy of ProductUsage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProductUsageImplCopyWith<_$ProductUsageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
