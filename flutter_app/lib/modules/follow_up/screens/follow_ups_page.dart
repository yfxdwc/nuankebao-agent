// ============================================
// 跟进待办页 (B2 换装, 2026-09-25)
//   - 跟 B1 客户域同套组件 (AppSection / AppListRow) —— 行高 60, 一屏 9+
//   - 旧 ElevatedButton + 80pt BigFab 退役 (B2 不再保留)
// 主体逻辑未动: 分组 / 完成 / 跳详情 都按原有流程
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/follow_up.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_section.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/user_avatar.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/theme/theme_ext.dart';

/// 待办任务 + 客户名映射 (任务模型没有客户名, 这里用客户列表补上, 不动 freezed 模型)
class FollowUpTodo {
  final FollowUpTask task;
  final String customerName;
  const FollowUpTodo({required this.task, required this.customerName});
}

final pendingFollowUpsProvider =
    FutureProvider<List<FollowUpTodo>>((ref) async {
  final tasks = await ref.read(followUpServiceProvider).list(status: 'pending');
  final list = await ref.read(customerServiceProvider).list(limit: 200);
  ref.read(usageServiceProvider).track('follow_up_list_view');
  final nameById = {for (final r in list.items) r.customer.id: r.customer.name};
  final todos = tasks
      .map((t) => FollowUpTodo(
            task: t,
            customerName: nameById[t.customerId] ?? '客户 #${t.customerId}',
          ))
      .toList();
  todos.sort((a, b) => a.task.dueAt.compareTo(b.task.dueAt));
  return todos;
});

class FollowUpsPage extends ConsumerWidget {
  const FollowUpsPage({super.key});

  static const _groups = ['逾期', '今天', '明天', '本周', '更远'];

  String _groupOf(DateTime dueAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueAt.year, dueAt.month, dueAt.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return '逾期';
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff <= 7) return '本周';
    return '更远';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingFollowUpsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('跟进待办'),
        toolbarHeight: AppSize.appBarHeight,
      ),
      body: async.when(
        loading: () => const AppSkeletonList(rows: 6),
        error: (e, _) => AppEmptyState(
          icon: Icons.error_outline,
          title: '加载失败',
          hint: '$e',
          action: FilledButton(
            onPressed: () => ref.invalidate(pendingFollowUpsProvider),
            child: const Text('重试'),
          ),
        ),
        data: (todos) {
          if (todos.isEmpty) {
            return const AppEmptyState(
              icon: Icons.task_alt,
              title: '今天没有待办',
              hint: '客户列表里带 🔥 标签的，就是该联系的人',
            );
          }
          final grouped = <String, List<FollowUpTodo>>{};
          for (final t in todos) {
            grouped.putIfAbsent(_groupOf(t.task.dueAt), () => []).add(t);
          }
          final ordered = _groups.where(grouped.containsKey).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pendingFollowUpsProvider),
            // ⚠ 不再 listview (P4 旧坑); 固定列表直接 Column + 内嵌滚动
            child: ListView(
              padding: const EdgeInsets.only(
                top: AppSpace.s8,
                bottom: AppSpace.s24,
              ),
              children: <Widget>[
                for (final g in ordered) ...<Widget>[
                  _GroupHeader(label: g, count: grouped[g]!.length),
                  for (final t in grouped[g]!)
                    _TodoRow(
                      todo: t,
                      overdue: g == '逾期',
                      onComplete: () =>
                          _complete(context, ref, t),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _complete(
    BuildContext context,
    WidgetRef ref,
    FollowUpTodo todo,
  ) async {
    await ref.read(followUpServiceProvider).complete(todo.task.id);
    ref.read(usageServiceProvider).track('follow_up_done');
    ref.invalidate(pendingFollowUpsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已标记「${todo.customerName}」跟进完成',
              style: const TextStyle(fontSize: AppType.sm)),
        ),
      );
    }
  }
}

/// 区块标题：圆点 + 文字 + 计数 —— 改用 [AppSectionHeader] 风格
///
/// B2 决策：仍保留左侧圆点（语义信号），但拿掉 row 背景色块；
/// 用 `tokens.dangerSurface` / `tokens.primarySurface` 浅底表示严重度。
class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;
  const _GroupHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final urgent = label == '逾期';
    final color = urgent ? tokens.danger : tokens.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pagePadding,
        AppSpace.s10,
        AppSpace.pagePadding,
        AppSpace.s4,
      ),
      color: urgent ? tokens.dangerSurface : tokens.primarySurface,
      child: Row(
        children: <Widget>[
          Container(
            width: AppSpace.s8,
            height: AppSpace.s8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: AppSpace.inlineGap),
          Text(
            label,
            style: TextStyle(
              fontSize: AppType.sm,
              fontWeight: AppWeight.semibold,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpace.tightGap),
          Text('($count)',
              style: TextStyle(
                fontSize: AppType.xs,
                color: color,
              )),
        ],
      ),
    );
  }
}

/// 待办行 —— AppListRow, 主文=客户名, 副文=原因 (逾期红色), trailing=完成按钮
class _TodoRow extends StatelessWidget {
  final FollowUpTodo todo;
  final bool overdue;
  final VoidCallback onComplete;
  const _TodoRow({
    required this.todo,
    required this.overdue,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final reasonColor = overdue ? tokens.danger : tokens.textSecondary;
    return AppListRow(
      leading: UserAvatar(
        avatarUrl: null,
        name: todo.customerName,
        size: AppSize.avatarMd,
        showLoadingIndicator: false,
      ),
      title: Text(
        todo.customerName,
        style: const TextStyle(
          fontSize: AppType.md,
          fontWeight: AppWeight.medium,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        todo.task.reason,
        style: TextStyle(
          fontSize: AppType.xs,
          color: reasonColor,
          fontWeight: overdue ? AppWeight.semibold : AppWeight.regular,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.tapMin),
        child: TextButton(
          onPressed: onComplete,
          style: TextButton.styleFrom(
            foregroundColor: tokens.primary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.s10,
              vertical: AppSpace.s6,
            ),
          ),
          child: const Text('完成',
              style: TextStyle(
                fontSize: AppType.sm,
                fontWeight: AppWeight.semibold,
              )),
        ),
      ),
      onTap: () => context.push('/customers/${todo.task.customerId}'),
    );
  }
}
