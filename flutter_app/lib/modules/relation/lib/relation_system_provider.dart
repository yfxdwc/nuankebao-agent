// ============================================
// RelationSystem Riverpod Provider (modules/relation/lib/)
//
// ★ v0.1.3 架构重点: 单一 provider 注入点
// 切换关系系统时, 只改这里的 default value.
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import 'franchise_relation.dart';
import 'relation_system.dart';

/// 全局 RelationSystem Provider
///
/// **默认**: FranchiseRelationSystem (v0.1.3 阶段)
///
/// **未来切换示例** (分销关系):
/// ```dart
/// final relationSystemProvider = Provider<RelationSystem>((ref) {
///   final distributionApi = ref.watch(distributionServiceProvider);
///   return DistributionRelationSystem(distributionApi);
/// });
/// ```
///
/// 调用方**零改动**: 所有 `ref.watch(relationSystemProvider)` 自动拿到新实现.
final relationSystemProvider = Provider<RelationSystem>((ref) {
  final franchiseService = ref.watch(franchiseeServiceProvider);
  return FranchiseRelationSystem(franchiseService);
});
