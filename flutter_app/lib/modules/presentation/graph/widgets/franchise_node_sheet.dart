// ============================================
// 节点点击底部表单 (Plan F3)
// 选项: 联系 / 详情 / 添加下线到左 / 添加下线到右 / 取消
// ============================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/franchisee.dart';
import '../../../../core/theme/app_theme.dart';

import '../../../../core/theme/tokens.g.dart';
Future<void> showFranchiseNodeSheet(
  BuildContext context, {
  required FranchiseeTreeNode node,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.bgWarm,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
    ),
    builder: (ctx) => _FranchiseNodeSheet(node: node),
  );
}

class _FranchiseNodeSheet extends StatelessWidget {
  final FranchiseeTreeNode node;
  const _FranchiseNodeSheet({required this.node});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 节点信息头
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppTheme.franchisee.withOpacity(0.2),
                  child: Text(
                    node.name.isNotEmpty ? node.name[0] : '?',
                    style: const TextStyle(
                      fontSize: AppType.lg,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.franchisee,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(
                          fontSize: AppTheme.fontLg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpace.s4),
                      Text(
                        _positionLabel(node),
                        style: const TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpace.s32),

            // 操作选项
            _actionTile(
              context,
              icon: Icons.account_circle_outlined,
              label: '查看详情',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/franchisees/${node.id}');
              },
            ),
            _actionTile(
              context,
              icon: Icons.phone_in_talk,
              iconColor: AppTheme.primary,
              label: '联系',
              hint: '复用联系记录',
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('联系: TODO 接 AddRecordSheet 模式',
                    style: TextStyle(fontSize: AppTheme.fontMd)),
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpace.s16),
            const Text(
              '添加下线到此节点',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpace.s8),

            // 添加下线 - 左
            _actionTile(
              context,
              icon: Icons.arrow_back,
              iconColor: AppTheme.primary,
              label: '加到A线',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/franchisees/new?parentId=${node.id}&sideHint=left');
              },
            ),
            // 添加下线 - 右
            _actionTile(
              context,
              icon: Icons.arrow_forward,
              iconColor: AppTheme.franchisee,
              label: '加到B线',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/franchisees/new?parentId=${node.id}&sideHint=right');
              },
            ),

            const SizedBox(height: AppSpace.s8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
              child: const Text(
                '取消',
                style: TextStyle(fontSize: AppTheme.fontMd),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _positionLabel(FranchiseeTreeNode node) {
    // A线/B线 命名 (主人 2026-09-17 拍: 左线→A线, 右线→B线) + 关系三维区分
    final relation = node.relation.label;
    if (node.placementSide == null) return '顶级加盟商 · $relation';
    final line = node.placementSide == 'left' ? 'A线' : 'B线';
    return '第 ${node.placementDepth} 层 · $line · $relation';
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? hint,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Container(
          height: AppSpace.s56,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
          child: Row(
            children: [
              Icon(icon, color: iconColor ?? AppTheme.textPrimary, size: 24),
              const SizedBox(width: AppSpace.s16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (hint != null)
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
              const SizedBox(width: AppSpace.s8),
              const Icon(Icons.chevron_right, size: 24, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddHint(BuildContext context, FranchiseeTreeNode parent, String side) {
    // 已用 context.push 替换, 此方法不再使用
  }
}