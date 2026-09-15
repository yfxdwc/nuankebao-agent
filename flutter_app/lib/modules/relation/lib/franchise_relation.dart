// ============================================
// FranchiseRelationSystem 默认实现 (modules/relation/lib/)
//
// ★ v0.1.3 架构重点: RelationSystem 的第一个实现 (Hexagonal: Adapter)
// 内部包装 FranchiseeService (在 core/services/api.dart), 把 Franchisee/FranchiseeTreeNode
// 适配成 RelationNode 返回.
//
// 未来切换: 新建 DistributionRelationSystem implements RelationSystem,
//          改 relationSystemProvider 默认值 (见 relation_system_provider.dart),
//          调用方零改动.
// ============================================

import '../../../core/models/franchisee.dart';
import '../../../core/services/api.dart';
import 'relation_node.dart';
import 'relation_system.dart';

/// 加盟关系系统的 RelationSystem 实现
///
/// 适配层: FranchiseeService (业务 API) → RelationSystem (通用接口)
class FranchiseRelationSystem implements RelationSystem {
  final FranchiseeService _service;

  FranchiseRelationSystem(this._service);

  @override
  String get name => 'franchise';

  @override
  Future<List<RelationNode>> getGraph(String rootId) async {
    // ★ Franchise 特有: getMyTree 是 FranchiseeService 的方法,
    // 返回 FranchiseeTreeNode (含整棵树).
    // 我们把树扁平化成 List<RelationNode> 返回.
    final tree = await _service.getMyTree(depth: 3);
    final result = <RelationNode>[];
    _flattenInto(tree, result);
    return result;
  }

  @override
  Future<RelationNode?> getNode(String nodeId) async {
    try {
      final f = await _service.getById(nodeId);
      return _toRelationNode(f);
    } catch (_) {
      // 404 / not found → null
      return null;
    }
  }

  @override
  Future<List<RelationNode>> getChildren(String parentId) async {
    // ★ Franchise 关系是二叉树 (left/right), 不是多子.
    // 简化实现: getNode(parent) → 找出直接子节点.
    // 当前 FranchiseeService 没有直接 API, 用 getMyTree 然后过滤.
    final tree = await _service.getMyTree(depth: 1);
    final parent = _findById(tree, parentId);
    if (parent == null) return [];
    return parent.children.map(_toRelationNodeFromTree).toList();
  }

  @override
  Future<void> addRelation({
    required String fromId,
    required String toId,
    required RelationType type,
  }) async {
    // ★ addRelation 在 franchise 语义下 = 在 fromId 下新增 toId 节点
    // type 仅作为 hint, 真实业务用 sideHint (left/right)
    await _service.create(CreateFranchiseeInput(
      name: 'TBD', // 创建时需要 name, 这里暂用占位
      phone: '',
      referrerId: fromId,
      sideHint: type == RelationType.child ? 'left' : null,
    ));
    // ⚠ 实际 addRelation 需要 UI 提供 name/phone,
    // 这里只演示接口形状. 真实场景: screen 收集表单 → create(input)
    // (relation_system 接口的 addRelation 是"建立关系", 实际数据由调用方决定)
  }

  @override
  Future<void> removeRelation({
    required String fromId,
    required String toId,
  }) async {
    // 删除 toId 节点 (脱离 fromId)
    await _service.delete(toId);
  }

  @override
  Future<List<RelationPath>> findPaths({
    required String fromId,
    required String toId,
  }) async {
    // ★ 简化: BFS 查找路径
    // 实际 franchise 业务很少需要"两节点间路径", 留作占位
    return [];
  }

  // ============ Helper: Franchisee → RelationNode ============

  /// Franchisee → RelationNode
  RelationNode _toRelationNode(Franchisee f) => RelationNode(
        id: f.id,
        name: f.name,
        metadata: {
          'phone': f.phone,
          'referrerId': f.referrerId,
          'placementSide': f.placementSide,
          'placementDepth': f.placementDepth,
          'isActive': f.isActive,
          if (f.joinedAt != null) 'joinedAt': f.joinedAt!.toIso8601String(),
        },
      );

  /// FranchiseeTreeNode → RelationNode (递归扁平化)
  void _flattenInto(FranchiseeTreeNode node, List<RelationNode> out) {
    out.add(_toRelationNodeFromTree(node));
    for (final child in node.children) {
      _flattenInto(child, out);
    }
  }

  RelationNode _toRelationNodeFromTree(FranchiseeTreeNode n) => RelationNode(
        id: n.id,
        name: n.name,
        metadata: {
          'placementSide': n.placementSide,
          'placementDepth': n.placementDepth,
        },
      );

  FranchiseeTreeNode? _findById(FranchiseeTreeNode node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = _findById(child, id);
      if (found != null) return found;
    }
    return null;
  }
}
