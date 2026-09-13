// ============================================
// 我的 (Profile) 页面 (Plan F2 极简版)
// 销售员视角: 头像/上级/数据/加盟网络入口
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/service_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/big_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/franchise_chip.dart';
import '../models/dashboard.dart';

final _dashboardStatsProvider = dashboardStatsProvider;

// W5 RBAC: 角色 → 中文显示
const Map<String, String> _roleLabels = {
  'admin': '管理员',
  'manager': '店长',
  'sales': '销售员',
};

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final asyncStats = ref.watch(_dashboardStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        toolbarHeight: 64,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // 头像 + 基本信息卡
          _buildProfileHeader(auth),
          const SizedBox(height: 16),

          // 我的数据
          _buildStatsCard(asyncStats, ref),
          const SizedBox(height: 16),

          // 我的加盟网络入口 (接 Plan F3)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.franchisee.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.account_tree, color: AppTheme.franchisee, size: 28),
              ),
              title: const Text(
                '我的加盟网络',
                style: TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '查看上下级加盟商',
                style: TextStyle(fontSize: AppTheme.fontSm),
              ),
              trailing: const Icon(Icons.chevron_right, size: 28),
              onTap: () => context.push('/franchise-tree'),
            ),
          ),
          const SizedBox(height: 16),

          // 退出登录
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context, ref),
            icon: const Icon(Icons.logout, size: 24),
            label: const Text('退出登录', style: TextStyle(fontSize: AppTheme.fontMd)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: AppTheme.danger, width: 2),
              minimumSize: const Size(double.infinity, 56),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(AuthState auth) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: AppTheme.avatarLg / 2,
              backgroundColor: AppTheme.primaryLight,
              child: const Icon(Icons.person, size: 48, color: AppTheme.primaryDark),
            ),
            const SizedBox(height: 12),
            const Text(
              '我',
              style: TextStyle(
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const FranchiseChip(type: 'franchisee'),
            const SizedBox(height: 12),
            // W5 RBAC: 角色显示
            Builder(
              builder: (ctx) {
                final role = (auth as dynamic).role as String?;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '角色: ${_roleLabels[role ?? 'sales'] ?? '销售员'}',
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '暖客宝销售员',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(AsyncValue stats, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '我的数据',
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            stats.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: LoadingState(),
              ),
              error: (e, _) => Text('加载失败: $e', style: const TextStyle(fontSize: AppTheme.fontSm)),
              data: (s) => Row(
                children: [
                  _statBox('客户', s.customerCount ?? 0),
                  _statBox('待办', s.pendingFollowUps ?? 0, color: AppTheme.danger),
                  _statBox('本月', s.thisMonthVisits ?? 0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, int value, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: AppTheme.fontXxl,
              fontWeight: FontWeight.bold,
              color: color ?? AppTheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: AppTheme.fontSm,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定退出?'),
        content: const Text('退出后需要重新登录'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('退出', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok == true) {
        await ref.read(authProvider.notifier).logout();
        if (!context.mounted) return;
        context.go('/login');
      }
    });
  }
}