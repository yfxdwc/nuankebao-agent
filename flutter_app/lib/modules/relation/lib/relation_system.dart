// ============================================
// RelationSystem 抽象接口 (modules/relation/lib/)
//
// ★ v0.1.3 架构重点: 节点关系系统的端口 (Hexagonal Architecture: Ports)
// 默认实现: FranchiseRelationSystem (see franchise_relation.dart)
// 未来切换: 新建 XxxRelationSystem implements RelationSystem, 改
//           relationSystemProvider 默认值, 调用方零改动.
//
// 配套文档: docs/adr/0007-modular-architecture.md §RelationSystem 接口设计
// ============================================

import 'relation_node.dart';

/// 节点关系系统抽象接口
///
/// **核心契约** (7 个方法):
/// 1. `name` — 系统标识 (e.g. "franchise", "distribution")
/// 2. `getGraph(rootId)` — 获取某节点的完整关系图 (含所有后代)
/// 3. `getNode(nodeId)` — 获取单个节点详情
/// 4. `getChildren(parentId)` — 获取直接子节点
/// 5. `addRelation({fromId, toId, type})` — 添加关系
/// 6. `removeRelation({fromId, toId})` — 删除关系
/// 7. `findPaths({fromId, toId})` — 查找两个节点间的所有路径
///
/// **YAGNI 原则**: 只列当前实际需要的方法. 未来扩展时再加,
/// 不要预先定义"可能用到"的方法 (Hexagonal Architecture 风格).
abstract class RelationSystem {
  /// 系统名 (e.g. "franchise", "distribution")
  ///
  /// 用于:
  /// - UI 显示"当前是加盟关系"or"分销关系"
  /// - 日志 / 审计 / 多系统切换时区分
  String get name;

  /// 获取节点的完整关系图 (含所有后代, 不限深度)
  ///
  /// e.g. franchise 关系中, 返回 root 节点 + 整棵二叉树 (W5 RBAC ≤3 层硬限)
  Future<List<RelationNode>> getGraph(String rootId);

  /// 获取单个节点详情
  ///
  /// 返回 null 表示节点不存在
  Future<RelationNode?> getNode(String nodeId);

  /// 获取直接子节点 (一级, 不递归)
  ///
  /// 用于 UI 显示"我的下级"列表
  Future<List<RelationNode>> getChildren(String parentId);

  /// 添加关系
  ///
  /// ⚠ 副作用操作, 需要 RBAC 校验 (W5 sales 角色只能加自己下游)
  Future<void> addRelation({
    required String fromId,
    required String toId,
    required RelationType type,
  });

  /// 删除关系
  ///
  /// ⚠ 副作用操作, W5 RBAC: 仅 admin / manager 可调用
  Future<void> removeRelation({
    required String fromId,
    required String toId,
  });

  /// 查找两个节点间的所有路径
  ///
  /// e.g. "我到 A 隔着几个人" — 用于"推荐链查询"
  Future<List<RelationPath>> findPaths({
    required String fromId,
    required String toId,
  });
}
