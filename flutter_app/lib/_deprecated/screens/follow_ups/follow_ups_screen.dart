import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/customer.dart';
import '../../models/follow_up.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_theme.dart';
import '../customers/customers_list_screen.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
final pendingFollowUpsProvider = FutureProvider<List<FollowUpTask>>((ref) async {
  return ref.watch(followUpServiceProvider).list();
});

class FollowUpsScreen extends ConsumerWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTasks = ref.watch(pendingFollowUpsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('跟进任务')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: asyncTasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('暂无待跟进任务'));
          }

          // 按到期时间分组
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final endOfWeek = today.add(const Duration(days: 7));

          final overdue = <FollowUpTask>[];
          final todayTasks = <FollowUpTask>[];
          final thisWeek = <FollowUpTask>[];
          final later = <FollowUpTask>[];

          for (final t in tasks) {
            final due = t.dueAt;
            if (due.isBefore(today)) {
              overdue.add(t);
            } else if (due.isBefore(today.add(const Duration(days: 1)))) {
              todayTasks.add(t);
            } else if (due.isBefore(endOfWeek)) {
              thisWeek.add(t);
            } else {
              later.add(t);
            }
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pendingFollowUpsProvider),
            child: ListView(
              children: [
                if (overdue.isNotEmpty) ...[
                  _SectionHeader(
                    title: '⚠️ 已逾期 (${overdue.length})',
                    color: AppTheme.danger,
                  ),
                  ...overdue.map((t) => _TaskTile(task: t, isOverdue: true, ref: ref)),
                ],
                if (todayTasks.isNotEmpty) ...[
                  _SectionHeader(
                    title: '📅 今天 (${todayTasks.length})',
                    color: AppTheme.accent,
                  ),
                  ...todayTasks.map((t) => _TaskTile(task: t, ref: ref)),
                ],
                if (thisWeek.isNotEmpty) ...[
                  _SectionHeader(
                    title: '📆 本周 (${thisWeek.length})',
                    color: AppTheme.primary,
                  ),
                  ...thisWeek.map((t) => _TaskTile(task: t, ref: ref)),
                ],
                if (later.isNotEmpty) ...[
                  _SectionHeader(
                    title: '🗓️ 更晚 (${later.length})',
                    color: Colors.grey,
                  ),
                  ...later.map((t) => _TaskTile(task: t, ref: ref)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppType.xs,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final FollowUpTask task;
  final bool isOverdue;
  final WidgetRef ref;
  const _TaskTile({required this.task, this.isOverdue = false, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isOverdue ? AppTheme.danger.withOpacity(0.1) : AppTheme.primaryLight.withOpacity(0.2),
          child: Icon(
            isOverdue ? Icons.priority_high : Icons.notifications,
            color: isOverdue ? AppTheme.danger : AppTheme.primary,
            size: AppSpace.s20,
          ),
        ),
        title: Text('客户 #${task.customerId}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.reason),
            const SizedBox(height: AppSpace.s2),
            Text(
              DateFormat('MM-dd HH:mm').format(task.dueAt),
              style: TextStyle(
                fontSize: AppType.tiny,
                color: isOverdue ? AppTheme.danger : Colors.black54,
                fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (task.aiSuggestion != null) ...[
              const SizedBox(height: AppSpace.s4),
              Container(
                padding: const EdgeInsets.all(AppSpace.s6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppRadius.r4),
                ),
                child: Text(
                  '🤖 ${task.aiSuggestion!}',
                  style: const TextStyle(fontSize: AppType.tiny),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            final svc = ref.read(followUpServiceProvider);
            if (action == 'complete') {
              await svc.complete(task.id);
            } else if (action == 'cancel') {
              await svc.cancel(task.id);
            }
            ref.invalidate(pendingFollowUpsProvider);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'complete', child: Text('✓ 完成')),
            PopupMenuItem(value: 'cancel', child: Text('✗ 取消')),
          ],
        ),
        isThreeLine: task.aiSuggestion != null,
        onTap: () => context.push('/customers/${task.customerId}'),
      ),
    );
  }
}

Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
  Customer? selectedCustomer;
  final reasonController = TextEditingController(text: '复购周期提醒');
  final suggestionController = TextEditingController();
  DateTime dueAt = DateTime.now().add(const Duration(days: 7));
  final asyncCustomers = ref.read(customersProvider);

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('创建跟进任务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                asyncCustomers.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpace.s8),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('加载客户失败: $e'),
                  data: (customers) => DropdownButtonFormField<Customer>(
                    value: selectedCustomer,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '选择客户 *'),
                    items: customers
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                        .toList(),
                    onChanged: (c) => setState(() => selectedCustomer = c),
                  ),
                ),
                const SizedBox(height: AppSpace.s12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(labelText: '跟进原因 *'),
                ),
                const SizedBox(height: AppSpace.s12),
                TextField(
                  controller: suggestionController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'AI 建议 (可选)'),
                ),
                const SizedBox(height: AppSpace.s12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('到期时间'),
                  subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(dueAt)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: dueAt,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => dueAt = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedCustomer == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('请先选择客户')),
                  );
                  return;
                }
                try {
                  await ref.read(followUpServiceProvider).create({
                    'customerId': selectedCustomer!.id,
                    'dueAt': dueAt.toIso8601String(),
                    'reason': reasonController.text.trim(),
                    if (suggestionController.text.trim().isNotEmpty)
                      'aiSuggestion': suggestionController.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.invalidate(pendingFollowUpsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已创建')),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('创建失败: $e')),
                    );
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      );
    },
  );
}