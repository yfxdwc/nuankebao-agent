// ============================================
// RelationSystem 调用方专用 Provider (modules/relation/lib/)
//
// v0.1.4 Phase 6.5 重构清理 (commit 17a6150):
// - 删 myFranchiseeTreeViaRelationProvider (死代码 + 名字欺骗)
//   - 名字暗示"走 RelationSystem", 实际直调 franchiseeServiceProvider.getMyTree
//   - 跟 service_providers.dart 的 myFranchiseeTreeProvider 干同一件事
//   - 调用方 (franchise_tree_page.dart) 用的是后者, 前者无人调用
// - 留 myRelationGraphProvider (Phase 6 后续用, 返回 List<RelationNode>)
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'relation_node.dart';
import 'relation_system_provider.dart';

/// 我的加盟树 (通过 RelationSystem 接口, 返回扁平 List<RelationNode>)
///
/// Phase 6 后续: 调用方从 myFranchiseeTreeProvider 迁到这个,
/// 同时改用 List<RelationNode> 渲染 (而不是 FranchiseeTreeNode).
/// 当前无调用方 (per Phase 6.5 决策: FranchiseeTreeNode 业务特有, UI 不重构).
final myRelationGraphProvider = FutureProvider<List<RelationNode>>((ref) async {
  final system = ref.watch(relationSystemProvider);
  return system.getGraph('me'); // 'me' = 当前用户 (W5 RBAC 时改为 self.id)
});
