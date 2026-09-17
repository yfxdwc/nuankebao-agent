// ============================================
// 加盟商详情 provider (共享)
//
// 为什么单独一个文件:
//   详情页 (franchisee_detail_page) 和 编辑页 (edit_franchisee_page) 都要读同一份缓存 —
//   编辑保存后必须 invalidate 它, 否则 pop 回详情页显示的还是旧名字 (2026-09-17 主人报的编辑页修复连带发现)
//
// 走 RelationSystem 接口 (不直接调 FranchiseeService), 保持模块可替换性
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/franchisee.dart';
import 'relation_node.dart';
import 'relation_system_provider.dart';

final franchiseeDetailProvider = FutureProvider.family<Franchisee, String>(
  (ref, id) async {
    final system = ref.watch(relationSystemProvider);
    final node = await system.getNode(id);
    if (node == null) {
      throw Exception('加盟商 $id 不存在');
    }
    return nodeToFranchisee(node);
  },
);

/// RelationNode → Franchisee 转换 (适配层, UI 兼容)
Franchisee nodeToFranchisee(RelationNode node) {
  return Franchisee(
    id: node.id,
    name: node.name,
    phone: node.metadata['phone'] as String? ?? '',
    referrerId: node.metadata['referrerId'] as String?,
    placementSide: node.metadata['placementSide'] as String?,
    placementPath: node.metadata['placementPath'] as String? ?? '',
    placementDepth: (node.metadata['placementDepth'] as num?)?.toInt() ?? 0,
    isActive: node.metadata['isActive'] as bool? ?? true,
    notes: node.metadata['notes'] as String?,
    joinedAt: node.metadata['joinedAt'] != null
        ? DateTime.tryParse(node.metadata['joinedAt'] as String)
        : null,
  );
}
