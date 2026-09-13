import 'package:freezed_annotation/freezed_annotation.dart';

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
    @Default([]) List<String> healthTags,
    String? diseaseHistory,
    String? notes,
    /// 客户推荐人 (客户页图谱数据源), null = 无推荐人 (根/孤儿节点)
    String? referrerId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}

/// 客户推荐关系图节点 (客户页图谱视图用)
/// 边界: 手机号/健康数据不解密, 仅名字 + id + 推荐人 id
/// 边 = referrerId -> id, 前端从节点列表构建
class CustomerGraphNode {
  final String id;
  final String name;
  final String? referrerId;

  const CustomerGraphNode({
    required this.id,
    required this.name,
    this.referrerId,
  });

  factory CustomerGraphNode.fromJson(Map<String, dynamic> json) {
    return CustomerGraphNode(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      referrerId: json['referrerId'] as String?,
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
