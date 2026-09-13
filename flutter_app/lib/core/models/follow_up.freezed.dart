// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'follow_up.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

FollowUpTask _$FollowUpTaskFromJson(Map<String, dynamic> json) {
  return _FollowUpTask.fromJson(json);
}

/// @nodoc
mixin _$FollowUpTask {
  String get id => throw _privateConstructorUsedError;
  String get customerId => throw _privateConstructorUsedError;
  DateTime get dueAt => throw _privateConstructorUsedError;
  String get reason => throw _privateConstructorUsedError;
  String? get aiSuggestion => throw _privateConstructorUsedError;
  String get status =>
      throw _privateConstructorUsedError; // pending / done / cancelled
  DateTime? get completedAt => throw _privateConstructorUsedError;
  String? get completedNotes => throw _privateConstructorUsedError;
  String? get assignedTo => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this FollowUpTask to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of FollowUpTask
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FollowUpTaskCopyWith<FollowUpTask> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FollowUpTaskCopyWith<$Res> {
  factory $FollowUpTaskCopyWith(
          FollowUpTask value, $Res Function(FollowUpTask) then) =
      _$FollowUpTaskCopyWithImpl<$Res, FollowUpTask>;
  @useResult
  $Res call(
      {String id,
      String customerId,
      DateTime dueAt,
      String reason,
      String? aiSuggestion,
      String status,
      DateTime? completedAt,
      String? completedNotes,
      String? assignedTo,
      DateTime createdAt});
}

/// @nodoc
class _$FollowUpTaskCopyWithImpl<$Res, $Val extends FollowUpTask>
    implements $FollowUpTaskCopyWith<$Res> {
  _$FollowUpTaskCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FollowUpTask
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? dueAt = null,
    Object? reason = null,
    Object? aiSuggestion = freezed,
    Object? status = null,
    Object? completedAt = freezed,
    Object? completedNotes = freezed,
    Object? assignedTo = freezed,
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
      dueAt: null == dueAt
          ? _value.dueAt
          : dueAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      aiSuggestion: freezed == aiSuggestion
          ? _value.aiSuggestion
          : aiSuggestion // ignore: cast_nullable_to_non_nullable
              as String?,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      completedNotes: freezed == completedNotes
          ? _value.completedNotes
          : completedNotes // ignore: cast_nullable_to_non_nullable
              as String?,
      assignedTo: freezed == assignedTo
          ? _value.assignedTo
          : assignedTo // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FollowUpTaskImplCopyWith<$Res>
    implements $FollowUpTaskCopyWith<$Res> {
  factory _$$FollowUpTaskImplCopyWith(
          _$FollowUpTaskImpl value, $Res Function(_$FollowUpTaskImpl) then) =
      __$$FollowUpTaskImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String customerId,
      DateTime dueAt,
      String reason,
      String? aiSuggestion,
      String status,
      DateTime? completedAt,
      String? completedNotes,
      String? assignedTo,
      DateTime createdAt});
}

/// @nodoc
class __$$FollowUpTaskImplCopyWithImpl<$Res>
    extends _$FollowUpTaskCopyWithImpl<$Res, _$FollowUpTaskImpl>
    implements _$$FollowUpTaskImplCopyWith<$Res> {
  __$$FollowUpTaskImplCopyWithImpl(
      _$FollowUpTaskImpl _value, $Res Function(_$FollowUpTaskImpl) _then)
      : super(_value, _then);

  /// Create a copy of FollowUpTask
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? dueAt = null,
    Object? reason = null,
    Object? aiSuggestion = freezed,
    Object? status = null,
    Object? completedAt = freezed,
    Object? completedNotes = freezed,
    Object? assignedTo = freezed,
    Object? createdAt = null,
  }) {
    return _then(_$FollowUpTaskImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      customerId: null == customerId
          ? _value.customerId
          : customerId // ignore: cast_nullable_to_non_nullable
              as String,
      dueAt: null == dueAt
          ? _value.dueAt
          : dueAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      aiSuggestion: freezed == aiSuggestion
          ? _value.aiSuggestion
          : aiSuggestion // ignore: cast_nullable_to_non_nullable
              as String?,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      completedNotes: freezed == completedNotes
          ? _value.completedNotes
          : completedNotes // ignore: cast_nullable_to_non_nullable
              as String?,
      assignedTo: freezed == assignedTo
          ? _value.assignedTo
          : assignedTo // ignore: cast_nullable_to_non_nullable
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
class _$FollowUpTaskImpl implements _FollowUpTask {
  const _$FollowUpTaskImpl(
      {required this.id,
      required this.customerId,
      required this.dueAt,
      required this.reason,
      this.aiSuggestion,
      required this.status,
      this.completedAt,
      this.completedNotes,
      this.assignedTo,
      required this.createdAt});

  factory _$FollowUpTaskImpl.fromJson(Map<String, dynamic> json) =>
      _$$FollowUpTaskImplFromJson(json);

  @override
  final String id;
  @override
  final String customerId;
  @override
  final DateTime dueAt;
  @override
  final String reason;
  @override
  final String? aiSuggestion;
  @override
  final String status;
// pending / done / cancelled
  @override
  final DateTime? completedAt;
  @override
  final String? completedNotes;
  @override
  final String? assignedTo;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'FollowUpTask(id: $id, customerId: $customerId, dueAt: $dueAt, reason: $reason, aiSuggestion: $aiSuggestion, status: $status, completedAt: $completedAt, completedNotes: $completedNotes, assignedTo: $assignedTo, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FollowUpTaskImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.customerId, customerId) ||
                other.customerId == customerId) &&
            (identical(other.dueAt, dueAt) || other.dueAt == dueAt) &&
            (identical(other.reason, reason) || other.reason == reason) &&
            (identical(other.aiSuggestion, aiSuggestion) ||
                other.aiSuggestion == aiSuggestion) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt) &&
            (identical(other.completedNotes, completedNotes) ||
                other.completedNotes == completedNotes) &&
            (identical(other.assignedTo, assignedTo) ||
                other.assignedTo == assignedTo) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, customerId, dueAt, reason,
      aiSuggestion, status, completedAt, completedNotes, assignedTo, createdAt);

  /// Create a copy of FollowUpTask
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FollowUpTaskImplCopyWith<_$FollowUpTaskImpl> get copyWith =>
      __$$FollowUpTaskImplCopyWithImpl<_$FollowUpTaskImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FollowUpTaskImplToJson(
      this,
    );
  }
}

abstract class _FollowUpTask implements FollowUpTask {
  const factory _FollowUpTask(
      {required final String id,
      required final String customerId,
      required final DateTime dueAt,
      required final String reason,
      final String? aiSuggestion,
      required final String status,
      final DateTime? completedAt,
      final String? completedNotes,
      final String? assignedTo,
      required final DateTime createdAt}) = _$FollowUpTaskImpl;

  factory _FollowUpTask.fromJson(Map<String, dynamic> json) =
      _$FollowUpTaskImpl.fromJson;

  @override
  String get id;
  @override
  String get customerId;
  @override
  DateTime get dueAt;
  @override
  String get reason;
  @override
  String? get aiSuggestion;
  @override
  String get status; // pending / done / cancelled
  @override
  DateTime? get completedAt;
  @override
  String? get completedNotes;
  @override
  String? get assignedTo;
  @override
  DateTime get createdAt;

  /// Create a copy of FollowUpTask
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FollowUpTaskImplCopyWith<_$FollowUpTaskImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Interaction _$InteractionFromJson(Map<String, dynamic> json) {
  return _Interaction.fromJson(json);
}

/// @nodoc
mixin _$Interaction {
  String get id => throw _privateConstructorUsedError;
  String get customerId => throw _privateConstructorUsedError;
  String get type =>
      throw _privateConstructorUsedError; // phone / wechat / visit / holiday_greeting / other
  String? get summary => throw _privateConstructorUsedError;
  DateTime? get followUpAt => throw _privateConstructorUsedError;
  String get createdBy => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this Interaction to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $InteractionCopyWith<Interaction> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $InteractionCopyWith<$Res> {
  factory $InteractionCopyWith(
          Interaction value, $Res Function(Interaction) then) =
      _$InteractionCopyWithImpl<$Res, Interaction>;
  @useResult
  $Res call(
      {String id,
      String customerId,
      String type,
      String? summary,
      DateTime? followUpAt,
      String createdBy,
      DateTime createdAt});
}

/// @nodoc
class _$InteractionCopyWithImpl<$Res, $Val extends Interaction>
    implements $InteractionCopyWith<$Res> {
  _$InteractionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? type = null,
    Object? summary = freezed,
    Object? followUpAt = freezed,
    Object? createdBy = null,
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
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      summary: freezed == summary
          ? _value.summary
          : summary // ignore: cast_nullable_to_non_nullable
              as String?,
      followUpAt: freezed == followUpAt
          ? _value.followUpAt
          : followUpAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      createdBy: null == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$InteractionImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$InteractionImplCopyWith(
          _$InteractionImpl value, $Res Function(_$InteractionImpl) then) =
      __$$InteractionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String customerId,
      String type,
      String? summary,
      DateTime? followUpAt,
      String createdBy,
      DateTime createdAt});
}

/// @nodoc
class __$$InteractionImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$InteractionImpl>
    implements _$$InteractionImplCopyWith<$Res> {
  __$$InteractionImplCopyWithImpl(
      _$InteractionImpl _value, $Res Function(_$InteractionImpl) _then)
      : super(_value, _then);

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? type = null,
    Object? summary = freezed,
    Object? followUpAt = freezed,
    Object? createdBy = null,
    Object? createdAt = null,
  }) {
    return _then(_$InteractionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      customerId: null == customerId
          ? _value.customerId
          : customerId // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      summary: freezed == summary
          ? _value.summary
          : summary // ignore: cast_nullable_to_non_nullable
              as String?,
      followUpAt: freezed == followUpAt
          ? _value.followUpAt
          : followUpAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      createdBy: null == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$InteractionImpl implements _Interaction {
  const _$InteractionImpl(
      {required this.id,
      required this.customerId,
      required this.type,
      this.summary,
      this.followUpAt,
      required this.createdBy,
      required this.createdAt});

  factory _$InteractionImpl.fromJson(Map<String, dynamic> json) =>
      _$$InteractionImplFromJson(json);

  @override
  final String id;
  @override
  final String customerId;
  @override
  final String type;
// phone / wechat / visit / holiday_greeting / other
  @override
  final String? summary;
  @override
  final DateTime? followUpAt;
  @override
  final String createdBy;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'Interaction(id: $id, customerId: $customerId, type: $type, summary: $summary, followUpAt: $followUpAt, createdBy: $createdBy, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InteractionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.customerId, customerId) ||
                other.customerId == customerId) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.summary, summary) || other.summary == summary) &&
            (identical(other.followUpAt, followUpAt) ||
                other.followUpAt == followUpAt) &&
            (identical(other.createdBy, createdBy) ||
                other.createdBy == createdBy) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, customerId, type, summary,
      followUpAt, createdBy, createdAt);

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$InteractionImplCopyWith<_$InteractionImpl> get copyWith =>
      __$$InteractionImplCopyWithImpl<_$InteractionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$InteractionImplToJson(
      this,
    );
  }
}

abstract class _Interaction implements Interaction {
  const factory _Interaction(
      {required final String id,
      required final String customerId,
      required final String type,
      final String? summary,
      final DateTime? followUpAt,
      required final String createdBy,
      required final DateTime createdAt}) = _$InteractionImpl;

  factory _Interaction.fromJson(Map<String, dynamic> json) =
      _$InteractionImpl.fromJson;

  @override
  String get id;
  @override
  String get customerId;
  @override
  String get type; // phone / wechat / visit / holiday_greeting / other
  @override
  String? get summary;
  @override
  DateTime? get followUpAt;
  @override
  String get createdBy;
  @override
  DateTime get createdAt;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$InteractionImplCopyWith<_$InteractionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
