// ============================================
// 节点关系数据类 (modules/relation/lib/)
//
// ★ v0.1.3 架构重点: RelationSystem 的通用数据契约
// 未来想换「分销关系」「会员等级」「上下级」等其他关系系统时,
// 新建 XxxRelationSystem implements RelationSystem 即可, 不用改这文件.
//
// 当前默认实现: FranchiseRelationSystem (see franchise_relation.dart)
// ============================================

/// 关系类型枚举
///
/// 各 RelationSystem 实现可选择使用这些类型, 也可定义自己的扩展类型.
/// (Dart enum 不能继承, 实现方需要在 RelationNode.metadata 里塞额外信息)
enum RelationType {
  /// 上级 (e.g. 加盟主)
  parent,

  /// 下级 (e.g. 加盟商)
  child,

  /// 同级 (e.g. 平级加盟商)
  peer,

  /// 管理 (e.g. 店长-店员)
  manager,

  /// 引荐 (e.g. 分销推荐)
  referral,
}

/// 关系系统中的一个节点
///
/// 不绑定具体业务 (Franchisee / Member / DistributionNode 等),
/// 由 RelationSystem 实现方把业务数据映射到 RelationNode.
class RelationNode {
  /// 节点唯一 ID (字符串, 兼容 bigint / uuid / 自定义 ID)
  final String id;

  /// 显示名 (UI 上展示用)
  final String name;

  /// 头像 URL (可选)
  final String? avatarUrl;

  /// 节点元数据 (业务相关字段, e.g. phone / joinedAt / level / storeId)
  ///
  /// ⚠ 这是一个开放字段, 实现方应约定 schema (e.g. README 文档化)
  /// UI 渲染时按需读取
  final Map<String, dynamic> metadata;

  const RelationNode({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.metadata = const {},
  });

  RelationNode copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    Map<String, dynamic>? metadata,
  }) =>
      RelationNode(
        id: id ?? this.id,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        metadata: metadata ?? this.metadata,
      );

  @override
  String toString() => 'RelationNode(id=$id, name=$name)';
}

/// 两个节点之间的路径
///
/// e.g. A(parent) → B(child) → C(child), 共 3 节点 + 2 条边
class RelationPath {
  final List<RelationNode> nodes;
  final List<RelationType> edges;

  const RelationPath({
    required this.nodes,
    required this.edges,
  });

  int get length => edges.length;

  @override
  String toString() => 'RelationPath(${nodes.length} nodes, ${edges.length} edges)';
}
