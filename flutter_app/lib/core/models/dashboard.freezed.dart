// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dashboard.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

DashboardStats _$DashboardStatsFromJson(Map<String, dynamic> json) {
  return _DashboardStats.fromJson(json);
}

/// @nodoc
mixin _$DashboardStats {
  int get customerCount => throw _privateConstructorUsedError;
  int get thisMonthVisits => throw _privateConstructorUsedError;
  int get pendingFollowUps => throw _privateConstructorUsedError;
  int get totalInteractions => throw _privateConstructorUsedError;

  /// Serializes this DashboardStats to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DashboardStats
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DashboardStatsCopyWith<DashboardStats> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DashboardStatsCopyWith<$Res> {
  factory $DashboardStatsCopyWith(
          DashboardStats value, $Res Function(DashboardStats) then) =
      _$DashboardStatsCopyWithImpl<$Res, DashboardStats>;
  @useResult
  $Res call(
      {int customerCount,
      int thisMonthVisits,
      int pendingFollowUps,
      int totalInteractions});
}

/// @nodoc
class _$DashboardStatsCopyWithImpl<$Res, $Val extends DashboardStats>
    implements $DashboardStatsCopyWith<$Res> {
  _$DashboardStatsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DashboardStats
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? customerCount = null,
    Object? thisMonthVisits = null,
    Object? pendingFollowUps = null,
    Object? totalInteractions = null,
  }) {
    return _then(_value.copyWith(
      customerCount: null == customerCount
          ? _value.customerCount
          : customerCount // ignore: cast_nullable_to_non_nullable
              as int,
      thisMonthVisits: null == thisMonthVisits
          ? _value.thisMonthVisits
          : thisMonthVisits // ignore: cast_nullable_to_non_nullable
              as int,
      pendingFollowUps: null == pendingFollowUps
          ? _value.pendingFollowUps
          : pendingFollowUps // ignore: cast_nullable_to_non_nullable
              as int,
      totalInteractions: null == totalInteractions
          ? _value.totalInteractions
          : totalInteractions // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DashboardStatsImplCopyWith<$Res>
    implements $DashboardStatsCopyWith<$Res> {
  factory _$$DashboardStatsImplCopyWith(_$DashboardStatsImpl value,
          $Res Function(_$DashboardStatsImpl) then) =
      __$$DashboardStatsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int customerCount,
      int thisMonthVisits,
      int pendingFollowUps,
      int totalInteractions});
}

/// @nodoc
class __$$DashboardStatsImplCopyWithImpl<$Res>
    extends _$DashboardStatsCopyWithImpl<$Res, _$DashboardStatsImpl>
    implements _$$DashboardStatsImplCopyWith<$Res> {
  __$$DashboardStatsImplCopyWithImpl(
      _$DashboardStatsImpl _value, $Res Function(_$DashboardStatsImpl) _then)
      : super(_value, _then);

  /// Create a copy of DashboardStats
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? customerCount = null,
    Object? thisMonthVisits = null,
    Object? pendingFollowUps = null,
    Object? totalInteractions = null,
  }) {
    return _then(_$DashboardStatsImpl(
      customerCount: null == customerCount
          ? _value.customerCount
          : customerCount // ignore: cast_nullable_to_non_nullable
              as int,
      thisMonthVisits: null == thisMonthVisits
          ? _value.thisMonthVisits
          : thisMonthVisits // ignore: cast_nullable_to_non_nullable
              as int,
      pendingFollowUps: null == pendingFollowUps
          ? _value.pendingFollowUps
          : pendingFollowUps // ignore: cast_nullable_to_non_nullable
              as int,
      totalInteractions: null == totalInteractions
          ? _value.totalInteractions
          : totalInteractions // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DashboardStatsImpl implements _DashboardStats {
  const _$DashboardStatsImpl(
      {required this.customerCount,
      required this.thisMonthVisits,
      required this.pendingFollowUps,
      required this.totalInteractions});

  factory _$DashboardStatsImpl.fromJson(Map<String, dynamic> json) =>
      _$$DashboardStatsImplFromJson(json);

  @override
  final int customerCount;
  @override
  final int thisMonthVisits;
  @override
  final int pendingFollowUps;
  @override
  final int totalInteractions;

  @override
  String toString() {
    return 'DashboardStats(customerCount: $customerCount, thisMonthVisits: $thisMonthVisits, pendingFollowUps: $pendingFollowUps, totalInteractions: $totalInteractions)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DashboardStatsImpl &&
            (identical(other.customerCount, customerCount) ||
                other.customerCount == customerCount) &&
            (identical(other.thisMonthVisits, thisMonthVisits) ||
                other.thisMonthVisits == thisMonthVisits) &&
            (identical(other.pendingFollowUps, pendingFollowUps) ||
                other.pendingFollowUps == pendingFollowUps) &&
            (identical(other.totalInteractions, totalInteractions) ||
                other.totalInteractions == totalInteractions));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, customerCount, thisMonthVisits,
      pendingFollowUps, totalInteractions);

  /// Create a copy of DashboardStats
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DashboardStatsImplCopyWith<_$DashboardStatsImpl> get copyWith =>
      __$$DashboardStatsImplCopyWithImpl<_$DashboardStatsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DashboardStatsImplToJson(
      this,
    );
  }
}

abstract class _DashboardStats implements DashboardStats {
  const factory _DashboardStats(
      {required final int customerCount,
      required final int thisMonthVisits,
      required final int pendingFollowUps,
      required final int totalInteractions}) = _$DashboardStatsImpl;

  factory _DashboardStats.fromJson(Map<String, dynamic> json) =
      _$DashboardStatsImpl.fromJson;

  @override
  int get customerCount;
  @override
  int get thisMonthVisits;
  @override
  int get pendingFollowUps;
  @override
  int get totalInteractions;

  /// Create a copy of DashboardStats
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DashboardStatsImplCopyWith<_$DashboardStatsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ServiceDistribution _$ServiceDistributionFromJson(Map<String, dynamic> json) {
  return _ServiceDistribution.fromJson(json);
}

/// @nodoc
mixin _$ServiceDistribution {
  String get serviceItemId => throw _privateConstructorUsedError;
  int get count => throw _privateConstructorUsedError;

  /// Serializes this ServiceDistribution to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ServiceDistribution
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ServiceDistributionCopyWith<ServiceDistribution> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ServiceDistributionCopyWith<$Res> {
  factory $ServiceDistributionCopyWith(
          ServiceDistribution value, $Res Function(ServiceDistribution) then) =
      _$ServiceDistributionCopyWithImpl<$Res, ServiceDistribution>;
  @useResult
  $Res call({String serviceItemId, int count});
}

/// @nodoc
class _$ServiceDistributionCopyWithImpl<$Res, $Val extends ServiceDistribution>
    implements $ServiceDistributionCopyWith<$Res> {
  _$ServiceDistributionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ServiceDistribution
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? serviceItemId = null,
    Object? count = null,
  }) {
    return _then(_value.copyWith(
      serviceItemId: null == serviceItemId
          ? _value.serviceItemId
          : serviceItemId // ignore: cast_nullable_to_non_nullable
              as String,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ServiceDistributionImplCopyWith<$Res>
    implements $ServiceDistributionCopyWith<$Res> {
  factory _$$ServiceDistributionImplCopyWith(_$ServiceDistributionImpl value,
          $Res Function(_$ServiceDistributionImpl) then) =
      __$$ServiceDistributionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String serviceItemId, int count});
}

/// @nodoc
class __$$ServiceDistributionImplCopyWithImpl<$Res>
    extends _$ServiceDistributionCopyWithImpl<$Res, _$ServiceDistributionImpl>
    implements _$$ServiceDistributionImplCopyWith<$Res> {
  __$$ServiceDistributionImplCopyWithImpl(_$ServiceDistributionImpl _value,
      $Res Function(_$ServiceDistributionImpl) _then)
      : super(_value, _then);

  /// Create a copy of ServiceDistribution
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? serviceItemId = null,
    Object? count = null,
  }) {
    return _then(_$ServiceDistributionImpl(
      serviceItemId: null == serviceItemId
          ? _value.serviceItemId
          : serviceItemId // ignore: cast_nullable_to_non_nullable
              as String,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ServiceDistributionImpl implements _ServiceDistribution {
  const _$ServiceDistributionImpl(
      {required this.serviceItemId, required this.count});

  factory _$ServiceDistributionImpl.fromJson(Map<String, dynamic> json) =>
      _$$ServiceDistributionImplFromJson(json);

  @override
  final String serviceItemId;
  @override
  final int count;

  @override
  String toString() {
    return 'ServiceDistribution(serviceItemId: $serviceItemId, count: $count)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ServiceDistributionImpl &&
            (identical(other.serviceItemId, serviceItemId) ||
                other.serviceItemId == serviceItemId) &&
            (identical(other.count, count) || other.count == count));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, serviceItemId, count);

  /// Create a copy of ServiceDistribution
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ServiceDistributionImplCopyWith<_$ServiceDistributionImpl> get copyWith =>
      __$$ServiceDistributionImplCopyWithImpl<_$ServiceDistributionImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ServiceDistributionImplToJson(
      this,
    );
  }
}

abstract class _ServiceDistribution implements ServiceDistribution {
  const factory _ServiceDistribution(
      {required final String serviceItemId,
      required final int count}) = _$ServiceDistributionImpl;

  factory _ServiceDistribution.fromJson(Map<String, dynamic> json) =
      _$ServiceDistributionImpl.fromJson;

  @override
  String get serviceItemId;
  @override
  int get count;

  /// Create a copy of ServiceDistribution
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ServiceDistributionImplCopyWith<_$ServiceDistributionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
