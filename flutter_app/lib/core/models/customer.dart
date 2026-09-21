import 'package:freezed_annotation/freezed_annotation.dart';

import 'me.dart' show kAvatarPresetIds;

part 'customer.freezed.dart';
part 'customer.g.dart';

@freezed
class Customer with _$Customer {
  const factory Customer({
    required String id,
    required String name,
    required String phone,
    String? gender, // M / F / U
    int? birthYear,
    /// 生日月/日 (1-12 / 1-31); null = 不知道 (可只知年份/只知月日)
    /// 主人 2026-09-18 拍: 年月日 都可缺
    int? birthMonth,
    int? birthDay,
    /// 历法: 'solar' 阳历 / 'lunar' 农历 (默认太阳历)
    @Default('solar') String birthCalendar,
    /// 生日提醒强度 (天数): 7 / 3 / 0(当天); null = 不提醒
    /// 业务规则: 月+日 都有 = 开启提醒
    int? birthdayRemindDays,
    @Default([]) List<String> healthTags,
    String? diseaseHistory,
    /// 过敏史 (2026-09-18 新增; 跟既往病史分开)
    String? allergyHistory,
    /// 客户头像 (主人 2026-09-18 拍): null = 默认首字 / 'preset:x' / '/uploads/x.jpg'
    /// 未知值一律当 null (UI 退回首字, 不渲染白框)
    // ignore: invalid_annotation_target
    @JsonKey(fromJson: _parseAvatarValue) String? avatar,
    String? notes,
    /// 客户推荐人 (客户页图谱数据源), null = 无推荐人 (根/孤儿节点)
    String? referrerId,
    /// 种子客户标记 (显式勾选, 主人 2026-09-18). 老后端不返回该字段 → 默认 false
    @Default(false) bool isSeed,
    /// 客户类型 (混合判定, 后端算好): franchisee 加盟 / seed 种子 / normal 普通
    /// 优先级: 加盟 > 种子 > 普通 (加盟表派生 > is_seed > 默认)
    /// 老后端不返回该字段 → 默认 'normal'
    @Default('normal') String customerType,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}

/// 头像值兜底 (只认 preset: / /uploads/, 跟 user 头像同一套约定; 见 src/lib/avatar.ts)
/// 跟 MeUser 的解析一致 —— 但那边是 private, 这里复制一份 (模型层不互相依赖逻辑)
String? _parseAvatarValue(dynamic raw) {
  if (raw is! String) return null;
  final v = raw.trim();
  if (v.isEmpty) return null;
  if (v.startsWith('preset:')) {
    final id = v.substring('preset:'.length);
    return kAvatarPresetIds.contains(id) ? 'preset:$id' : null;
  }
  if (v.startsWith('/uploads/') && !v.contains('..') && v.length <= 200) {
    return v;
  }
  return null;
}

/// 客户推荐关系图节点 (客户页图谱视图用)
/// 边界: 手机号/健康数据不解密, 仅名字 + id + 推荐人 id
/// 边 = referrerId -> id, 前端从节点列表构建
class CustomerGraphNode {
  final String id;
  final String name;
  final String? referrerId;

  /// 会员标识 (主人 2026-09-21 拍): 同手机号的账号是不是会员, 后端每次现算
  ///   充值转会员 / 到期掉会员 → 下次拉图即变 (无需同步任务)
  ///   老后端不返回该字段 → 默认 false
  final bool member;

  const CustomerGraphNode({
    required this.id,
    required this.name,
    this.referrerId,
    this.member = false,
  });

  factory CustomerGraphNode.fromJson(Map<String, dynamic> json) {
    return CustomerGraphNode(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      referrerId: json['referrerId'] as String?,
      member: json['member'] as bool? ?? false,
    );
  }
}

/// 推荐关系图响应
class CustomerGraph {
  final List<CustomerGraphNode> nodes;
  final int count;

  const CustomerGraph({required this.nodes, required this.count});

  factory CustomerGraph.fromJson(Map<String, dynamic> json) {
    final raw = (json['nodes'] as List?) ?? [];
    return CustomerGraph(
      nodes: raw
          .map((e) => CustomerGraphNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      count: (json['count'] as num?)?.toInt() ?? raw.length,
    );
  }
}
