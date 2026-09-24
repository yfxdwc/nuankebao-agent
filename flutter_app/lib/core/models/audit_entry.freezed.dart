// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'audit_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AuditEntry _$AuditEntryFromJson(Map<String, dynamic> json) {
  return _AuditEntry.fromJson(json);
}

/// @nodoc
mixin _$AuditEntry {
  String get id => throw _privateConstructorUsedError;

  /// INSERT / UPDATE / DELETE (触发器原始操作名)
  String get operation => throw _privateConstructorUsedError;

  /// 发生变化的列名 (INSERT/DELETE = 整行所有列)
  List<String> get changedColumns => throw _privateConstructorUsedError;

  /// 操作人姓名; null = 系统 / 脚本 / dev skip-auth
  String? get actorName => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this AuditEntry to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AuditEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AuditEntryCopyWith<AuditEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AuditEntryCopyWith<$Res> {
  factory $AuditEntryCopyWith(
          AuditEntry value, $Res Function(AuditEntry) then) =
      _$AuditEntryCopyWithImpl<$Res, AuditEntry>;
  @useResult
  $Res call(
      {String id,
      String operation,
      List<String> changedColumns,
      String? actorName,
      DateTime createdAt});
}

/// @nodoc
class _$AuditEntryCopyWithImpl<$Res, $Val extends AuditEntry>
    implements $AuditEntryCopyWith<$Res> {
  _$AuditEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AuditEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? operation = null,
    Object? changedColumns = null,
    Object? actorName = freezed,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      operation: null == operation
          ? _value.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      changedColumns: null == changedColumns
          ? _value.changedColumns
          : changedColumns // ignore: cast_nullable_to_non_nullable
              as List<String>,
      actorName: freezed == actorName
          ? _value.actorName
          : actorName // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AuditEntryImplCopyWith<$Res>
    implements $AuditEntryCopyWith<$Res> {
  factory _$$AuditEntryImplCopyWith(
          _$AuditEntryImpl value, $Res Function(_$AuditEntryImpl) then) =
      __$$AuditEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String operation,
      List<String> changedColumns,
      String? actorName,
      DateTime createdAt});
}

/// @nodoc
class __$$AuditEntryImplCopyWithImpl<$Res>
    extends _$AuditEntryCopyWithImpl<$Res, _$AuditEntryImpl>
    implements _$$AuditEntryImplCopyWith<$Res> {
  __$$AuditEntryImplCopyWithImpl(
      _$AuditEntryImpl _value, $Res Function(_$AuditEntryImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuditEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? operation = null,
    Object? changedColumns = null,
    Object? actorName = freezed,
    Object? createdAt = null,
  }) {
    return _then(_$AuditEntryImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      operation: null == operation
          ? _value.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      changedColumns: null == changedColumns
          ? _value._changedColumns
          : changedColumns // ignore: cast_nullable_to_non_nullable
              as List<String>,
      actorName: freezed == actorName
          ? _value.actorName
          : actorName // ignore: cast_nullable_to_non_nullable
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
class _$AuditEntryImpl implements _AuditEntry {
  const _$AuditEntryImpl(
      {required this.id,
      required this.operation,
      final List<String> changedColumns = const [],
      this.actorName,
      required this.createdAt})
      : _changedColumns = changedColumns;

  factory _$AuditEntryImpl.fromJson(Map<String, dynamic> json) =>
      _$$AuditEntryImplFromJson(json);

  @override
  final String id;

  /// INSERT / UPDATE / DELETE (触发器原始操作名)
  @override
  final String operation;

  /// 发生变化的列名 (INSERT/DELETE = 整行所有列)
  final List<String> _changedColumns;

  /// 发生变化的列名 (INSERT/DELETE = 整行所有列)
  @override
  @JsonKey()
  List<String> get changedColumns {
    if (_changedColumns is EqualUnmodifiableListView) return _changedColumns;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_changedColumns);
  }

  /// 操作人姓名; null = 系统 / 脚本 / dev skip-auth
  @override
  final String? actorName;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'AuditEntry(id: $id, operation: $operation, changedColumns: $changedColumns, actorName: $actorName, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AuditEntryImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.operation, operation) ||
                other.operation == operation) &&
            const DeepCollectionEquality()
                .equals(other._changedColumns, _changedColumns) &&
            (identical(other.actorName, actorName) ||
                other.actorName == actorName) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      operation,
      const DeepCollectionEquality().hash(_changedColumns),
      actorName,
      createdAt);

  /// Create a copy of AuditEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AuditEntryImplCopyWith<_$AuditEntryImpl> get copyWith =>
      __$$AuditEntryImplCopyWithImpl<_$AuditEntryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AuditEntryImplToJson(
      this,
    );
  }
}

abstract class _AuditEntry implements AuditEntry {
  const factory _AuditEntry(
      {required final String id,
      required final String operation,
      final List<String> changedColumns,
      final String? actorName,
      required final DateTime createdAt}) = _$AuditEntryImpl;

  factory _AuditEntry.fromJson(Map<String, dynamic> json) =
      _$AuditEntryImpl.fromJson;

  @override
  String get id;

  /// INSERT / UPDATE / DELETE (触发器原始操作名)
  @override
  String get operation;

  /// 发生变化的列名 (INSERT/DELETE = 整行所有列)
  @override
  List<String> get changedColumns;

  /// 操作人姓名; null = 系统 / 脚本 / dev skip-auth
  @override
  String? get actorName;
  @override
  DateTime get createdAt;

  /// Create a copy of AuditEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AuditEntryImplCopyWith<_$AuditEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
