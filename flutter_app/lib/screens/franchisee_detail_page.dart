// ============================================
// 加盟商详情页 (Plan F3.5)
// 仿 customer_detail_page.dart 结构 + 加盟域特有字段
// 上级 + 位置标签 + 联系 + 编辑 + 软删
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/franchisee.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/big_button.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/franchise_chip.dart';

class FranchiseeDetailPage extends ConsumerWidget {
  final String franchiseeId;
  const FranchiseeDetailPage({super.key, required this.franchiseeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncFranchisee = ref.watch(_franchiseeProvider(franchiseeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('加盟商详情'),
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: 28),
            tooltip: '编辑',
            onPressed: () => context.push('/franchisees/$franchiseeId/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 28),
            tooltip: '软删',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: asyncFranchisee.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (f) => _buildBody(context, ref, f),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, Franchisee f) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // 头部
        _buildHeader(f),
        const SizedBox(height: 16),

        // 上级信息
        if (f.referrerId != null)
          _referrerCard(context, ref, f.referrerId!),

        // 位置信息
        _positionCard(f),

        const SizedBox(height: 16),

        // 联系按钮
        BigButton(
          label: '联系',
          icon: Icons.phone_in_talk,
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '拨号: ${f.phone} (TODO 后续)',
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // 二叉树位置可视化（文字版）
        _treePositionCard(f),
      ],
    );
  }

  Widget _buildHeader(Franchisee f) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 56,
              backgroundColor: AppTheme.franchisee.withOpacity(0.2),
              child: Text(
                f.name.isNotEmpty ? f.name[0] : '?',
                style: const TextStyle(
                  fontSize: 36,
                  color: AppTheme.franchisee,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              f.name,
              style: const TextStyle(
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const FranchiseChip(type: 'franchisee'),
            const SizedBox(height: 8),
            Text(
              _maskPhone(f.phone),
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _referrerCard(BuildContext context, WidgetRef ref, String referrerId) {
    final asyncReferrer = ref.watch(_franchiseeProvider(referrerId));
    return asyncReferrer.maybeWhen(
      data: (r) {
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: AppTheme.franchisee.withOpacity(0.2),
              child: Text(
                r.name.isNotEmpty ? r.name[0] : '?',
                style: const TextStyle(color: AppTheme.franchisee),
              ),
            ),
            title: const Text(
              '上级加盟商',
              style: TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
            ),
            subtitle: Text(
              r.name,
              style: const TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.chevron_right, size: 28),
            onTap: () => context.push('/franchisees/${r.id}'),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _positionCard(Franchisee f) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '位置信息',
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _row('层级', f.placementDepth == 0 ? '顶级 (root)' : '第 ${f.placementDepth} 层'),
            _row('位置', f.placementSide == null ? '顶级' : (f.placementSide == 'left' ? '左线' : '右线')),
            _row('路径', f.placementPath.isEmpty ? '(顶级)' : f.placementPath),
            _row('加入时间', f.joinedAt != null
                ? '${f.joinedAt!.year}-${f.joinedAt!.month.toString().padLeft(2, '0')}-${f.joinedAt!.day.toString().padLeft(2, '0')}'
                : '-'),
            _row('状态', f.isActive ? '活跃' : '已停用'),
          ],
        ),
      ),
    );
  }

  Widget _treePositionCard(Franchisee f) {
    // 二叉树位置可视化（用缩进 + 箭头表示）
    final indent = '  ' * f.placementDepth;
    final sideArrow = f.placementSide == 'left'
        ? '←'
        : f.placementSide == 'right'
            ? '→'
            : '*';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '在二叉树中的位置',
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgWarm,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$indent$sideArrow ${f.name}',
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  String _maskPhone(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}****${phone.substring(7)}';
    }
    return phone;
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定删除?'),
        content: const Text('加盟商将被软删除, 不能恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('删除', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(franchiseeServiceProvider).delete(franchiseeId);
        ref.invalidate(myFranchiseeTreeProvider);
        if (!context.mounted) return;
        context.pop();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }
}

final _franchiseeProvider = FutureProvider.family<Franchisee, String>(
  (ref, id) async => ref.watch(franchiseeServiceProvider).getById(id),
);