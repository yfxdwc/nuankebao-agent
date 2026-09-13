// ============================================
// RelationSystem 调用方专用 Provider (modules/relation/lib/)
//
// ★ v0.1.3 Phase 6 后续工作 (Phase 6.5+):
// 当前 phase 只建接口 + 默认实现 + relationSystemProvider,
// 调用方 (modules/relation/screens/*.dart) 仍用旧的 myFranchiseeTreeProvider.
// 后续 phase 把调用方改为用下面的 Provider, 完成"全栈走接口".
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/franchisee.dart';
import '../../../core/providers/service_providers.dart';
import 'relation_system.dart';
import 'relation_system_provider.dart';

/// 我的加盟树 (通过 RelationSystem 接口, 返回扁平 List<RelationNode>)
///
/// ⚠ Phase 6 后续工作: 调用方从 myFranchiseeTreeProvider 迁到这个,
/// 同时改用 List<RelationNode> 渲染 (而不是 FranchiseeTreeNode).
final myRelationGraphProvider = FutureProvider<List<RelationNode>>((ref) async {
  final system = ref.watch(relationSystemProvider);
  return system.getGraph('me'); // 'me' = 当前用户 (W5 RBAC 时改为 self.id)
});

/// 我的加盟树 (★ Phase 6 简化版: 仍返回 FranchiseeTreeNode 形状)
///
/// ★ 过渡: 保留 FranchiseeTreeNode 数据形状 (与现有 UI 兼容),
/// 内部通过 relationSystemProvider 注入, 但调用 FranchiseRelationSystem 的
/// getFranchiseeTree 扩展方法 (见 franchise_relation.dart).
///
/// 调用方 (modules/relation/screens/franchise_tree_page.dart) 暂不切换,
/// 仍用 core/providers/service_providers.dart 的 myFranchiseeTreeProvider.
final myFranchiseeTreeViaRelationProvider =
    FutureProvider.family<FranchiseeTreeNode, int>(
  (ref, depth) async {
    final service = ref.watch(franchiseeServiceProvider);
    // ⚠ Phase 6 简化: 仍直接调 FranchiseeService
    // 完整 Phase 6.5: 改为 (system as FranchiseRelationSystem).getFranchiseeTree(depth: depth)
    return service.getMyTree(depth: depth);
  },
);
