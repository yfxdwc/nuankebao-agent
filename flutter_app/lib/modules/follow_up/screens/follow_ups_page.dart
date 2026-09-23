// ============================================
// 跟进待办页 (主人 2026-09-20 拍 P1: /follow-ups)
// ============================================
// 用途: 把「系统自动建的跟进任务 + 手动建的任务」集中成一张今天要打的名单
//   - 分组: 逾期 / 今天 / 明天 / 本周 / 更远 (按 dueAt 自然日)
//   - 一键「完成」= PATCH /api/follow-ups/:id (status=done), 完成后从列表消失
//   - 点客户名 → 进客户详情 (看历史/记互动)
//
// 口径: 任务由 scripts/refresh-follow-up-tasks.ts 每日生成 (≥P1 + 7 天去重, 主人 Q4)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/follow_up.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';

import '../../../core/theme/tokens.g.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: '加载失败',
          hint: '$e',
          onAction: () => ref.invalidate(pendingFollowUpsProvider),
          actionLabel: '重试',
        ),
        data: (todos) {
          if (todos.isEmpty) {
            return const EmptyState(
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
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpace.s24),
              children: [
                for (final g in ordered) ...[
                  _groupHeader(g, grouped[g]!.length),
                  for (final t in grouped[g]!) _todoRow(context, ref, t),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _groupHeader(String label, int count) {
    final urgent = label == '逾期';
    final color = urgent ? AppTheme.danger : AppTheme.primary;
    return Container(
      color: AppTheme.bgWarm,
      padding: const EdgeInsets.fromLTRB(AppSpace.s14, AppSpace.s8, AppSpace.s14, AppSpace.s4),
      child: Row(
        children: [
          Container(
            width: AppSpace.s8,
            height: AppSpace.s8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: AppSpace.s8),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTheme.fontSm,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpace.s6),
          Text('($count)', style: TextStyle(fontSize: AppTheme.fontXs, color: color)),
        ],
      ),
    );
  }

  Widget _todoRow(BuildContext context, WidgetRef ref, FollowUpTodo todo) {
    final t = todo.task;
    final overdue = _groupOf(t.dueAt) == '逾期';
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.s14, AppSpace.s8, AppSpace.s14, AppSpace.s8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.push('/customers/${t.customerId}'),
                  child: Text(
                    todo.customerName,
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.s2),
                Text(
                  t.reason,
                  style: TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: overdue ? AppTheme.danger : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s8),
          // 一键完成 (老人友好: 大按钮 + 明确文字)
          ElevatedButton(
            onPressed: () async {
              await ref.read(followUpServiceProvider).complete(t.id);
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
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s6),
              minimumSize: const Size(0, AppSize.tapCompact),  // 紧凑 + 触摸下限 44
            ),
            child: const Text('完成', style: TextStyle(fontSize: AppType.sm, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
