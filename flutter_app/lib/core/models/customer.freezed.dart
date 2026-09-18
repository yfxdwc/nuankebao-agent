// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'customer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Customer _$CustomerFromJson(Map<String, dynamic> json) {
  return _Customer.fromJson(json);
}

/// @nodoc
mixin _$Customer {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get phone => throw _privateConstructorUsedError;
  String? get gender => throw _privateConstructorUsedError; // M / F / U
  int? get birthYear => throw _privateConstructorUsedError;
  List<String> get healthTags => throw _privateConstructorUsedError;
  String? get diseaseHistory => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;

  /// 客户推荐人 (客户页图谱数据源), null = 无推荐人 (根/孤儿节点)
  String? get referrerId => throw _privateConstructorUsedError;

  /// 种子客户标记 (显式勾选, 主人 2026-09-18). 老后端不返回该字段 → 默认 false
  bool get isSeed => throw _privateConstructorUsedError;

  /// 客户类型 (混合判定, 后端算好): franchisee 加盟 / seed 种子 / normal 普通
  /// 优先级: 加盟 > 种子 > 普通 (加盟表派生 > is_seed > 默认)
  /// 老后端不返回该字段 → 默认 'normal'
  String get customerType => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this Customer to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CustomerCopyWith<Customer> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CustomerCopyWith<$Res> {
  factory $CustomerCopyWith(Customer value, $Res Function(Customer) then) =
      _$CustomerCopyWithImpl<$Res, Customer>;
  @useResult
  $Res call(
      {String id,
      String name,
      String phone,
      String? gender,
      int? birthYear,
      List<String> healthTags,
      String? diseaseHistory,
      String? notes,
      String? referrerId,
      bool isSeed,
      String customerType,
      DateTime createdAt,
      DateTime updatedAt});
}

/// @nodoc
class _$CustomerCopyWithImpl<$Res, $Val extends Customer>
    implements $CustomerCopyWith<$Res> {
  _$CustomerCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? phone = null,
    Object? gender = freezed,
    Object? birthYear = freezed,
    Object? healthTags = null,
    Object? diseaseHistory = freezed,
    Object? notes = freezed,
    Object? referrerId = freezed,
    Object? isSeed = null,
    Object? customerType = null,
    Object? createdAt = null,
    Object? updatedAt = null,
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
      phone: null == phone
          ? _value.phone
          : phone // ignore: cast_nullable_to_non_nullable
              as String,
      gender: freezed == gender
          ? _value.gender
          : gender // ignore: cast_nullable_to_non_nullable
              as String?,
      birthYear: freezed == birthYear
          ? _value.birthYear
          : birthYear // ignore: cast_nullable_to_non_nullable
              as int?,
      healthTags: null == healthTags
          ? _value.healthTags
          : healthTags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      diseaseHistory: freezed == diseaseHistory
          ? _value.diseaseHistory
          : diseaseHistory // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      referrerId: freezed == referrerId
          ? _value.referrerId
          : referrerId // ignore: cast_nullable_to_non_nullable
              as String?,
      isSeed: null == isSeed
          ? _value.isSeed
          : isSeed // ignore: cast_nullable_to_non_nullable
              as bool,
      customerType: null == customerType
          ? _value.customerType
          : customerType // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CustomerImplCopyWith<$Res>
    implements $CustomerCopyWith<$Res> {
  factory _$$CustomerImplCopyWith(
          _$CustomerImpl value, $Res Function(_$CustomerImpl) then) =
      __$$CustomerImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String phone,
      String? gender,
      int? birthYear,
      List<String> healthTags,
      String? diseaseHistory,
      String? notes,
      String? referrerId,
      bool isSeed,
      String customerType,
      DateTime createdAt,
      DateTime updatedAt});
}

/// @nodoc
class __$$CustomerImplCopyWithImpl<$Res>
    extends _$CustomerCopyWithImpl<$Res, _$CustomerImpl>
    implements _$$CustomerImplCopyWith<$Res> {
  __$$CustomerImplCopyWithImpl(
      _$CustomerImpl _value, $Res Function(_$CustomerImpl) _then)
      : super(_value, _then);

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? phone = null,
    Object? gender = freezed,
    Object? birthYear = freezed,
    Object? healthTags = null,
    Object? diseaseHistory = freezed,
    Object? notes = freezed,
    Object? referrerId = freezed,
    Object? isSeed = null,
    Object? customerType = null,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_$CustomerImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      phone: null == phone
          ? _value.phone
          : phone // ignore: cast_nullable_to_non_nullable
              as String,
      gender: freezed == gender
          ? _value.gender
          : gender // ignore: cast_nullable_to_non_nullable
              as String?,
      birthYear: freezed == birthYear
          ? _value.birthYear
          : birthYear // ignore: cast_nullable_to_non_nullable
              as int?,
      healthTags: null == healthTags
          ? _value._healthTags
          : healthTags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      diseaseHistory: freezed == diseaseHistory
          ? _value.diseaseHistory
          : diseaseHistory // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      referrerId: freezed == referrerId
          ? _value.referrerId
          : referrerId // ignore: cast_nullable_to_non_nullable
              as String?,
      isSeed: null == isSeed
          ? _value.isSeed
          : isSeed // ignore: cast_nullable_to_non_nullable
              as bool,
      customerType: null == customerType
          ? _value.customerType
          : customerType // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CustomerImpl implements _Customer {
  const _$CustomerImpl(
      {required this.id,
      required this.name,
      required this.phone,
      this.gender,
      this.birthYear,
      final List<String> healthTags = const [],
      this.diseaseHistory,
      this.notes,
      this.referrerId,
      this.isSeed = false,
      this.customerType = 'normal',
      required this.createdAt,
      required this.updatedAt})
      : _healthTags = healthTags;

  factory _$CustomerImpl.fromJson(Map<String, dynamic> json) =>
      _$$CustomerImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String phone;
  @override
  final String? gender;
// M / F / U
  @override
  final int? birthYear;
  final List<String> _healthTags;
  @override
  @JsonKey()
  List<String> get healthTags {
    if (_healthTags is EqualUnmodifiableListView) return _healthTags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_healthTags);
  }

  @override
  final String? diseaseHistory;
  @override
  final String? notes;

  /// 客户推荐人 (客户页图谱数据源), null = 无推荐人 (根/孤儿节点)
  @override
  final String? referrerId;

  /// 种子客户标记 (显式勾选, 主人 2026-09-18). 老后端不返回该字段 → 默认 false
  @override
  @JsonKey()
  final bool isSeed;

  /// 客户类型 (混合判定, 后端算好): franchisee 加盟 / seed 种子 / normal 普通
  /// 优先级: 加盟 > 种子 > 普通 (加盟表派生 > is_seed > 默认)
  /// 老后端不返回该字段 → 默认 'normal'
  @override
  @JsonKey()
  final String customerType;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;

  @override
  String toString() {
    return 'Customer(id: $id, name: $name, phone: $phone, gender: $gender, birthYear: $birthYear, healthTags: $healthTags, diseaseHistory: $diseaseHistory, notes: $notes, referrerId: $referrerId, isSeed: $isSeed, customerType: $customerType, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CustomerImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.phone, phone) || other.phone == phone) &&
            (identical(other.gender, gender) || other.gender == gender) &&
            (identical(other.birthYear, birthYear) ||
                other.birthYear == birthYear) &&
            const DeepCollectionEquality()
                .equals(other._healthTags, _healthTags) &&
            (identical(other.diseaseHistory, diseaseHistory) ||
                other.diseaseHistory == diseaseHistory) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.referrerId, referrerId) ||
                other.referrerId == referrerId) &&
            (identical(other.isSeed, isSeed) || other.isSeed == isSeed) &&
            (identical(other.customerType, customerType) ||
                other.customerType == customerType) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      phone,
      gender,
      birthYear,
      const DeepCollectionEquality().hash(_healthTags),
      diseaseHistory,
      notes,
      referrerId,
      isSeed,
      customerType,
      createdAt,
      updatedAt);

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CustomerImplCopyWith<_$CustomerImpl> get copyWith =>
      __$$CustomerImplCopyWithImpl<_$CustomerImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CustomerImplToJson(
      this,
    );
  }
}

abstract class _Customer implements Customer {
  const factory _Customer(
      {required final String id,
      required final String name,
      required final String phone,
      final String? gender,
      final int? birthYear,
      final List<String> healthTags,
      final String? diseaseHistory,
      final String? notes,
      final String? referrerId,
      final bool isSeed,
      final String customerType,
      required final DateTime createdAt,
      required final DateTime updatedAt}) = _$CustomerImpl;

  factory _Customer.fromJson(Map<String, dynamic> json) =
      _$CustomerImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get phone;
  @override
  String? get gender; // M / F / U
  @override
  int? get birthYear;
  @override
  List<String> get healthTags;
  @override
  String? get diseaseHistory;
  @override
  String? get notes;

  /// 客户推荐人 (客户页图谱数据源), null = 无推荐人 (根/孤儿节点)
  @override
  String? get referrerId;

  /// 种子客户标记 (显式勾选, 主人 2026-09-18). 老后端不返回该字段 → 默认 false
  @override
  bool get isSeed;

  /// 客户类型 (混合判定, 后端算好): franchisee 加盟 / seed 种子 / normal 普通
  /// 优先级: 加盟 > 种子 > 普通 (加盟表派生 > is_seed > 默认)
  /// 老后端不返回该字段 → 默认 'normal'
  @override
  String get customerType;
  @override
  DateTime get createdAt;
  @override
  DateTime get updatedAt;

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CustomerImplCopyWith<_$CustomerImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
