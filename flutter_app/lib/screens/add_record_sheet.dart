// ============================================
// + 添加记录 弹窗 (Plan F2 极简版)
// 3 选 1: 养生记录 / 联系记录 / 跟进任务
// 中老年: 大按钮 80pt 高, 大字
// 强绑 customer (customerId 必传)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../providers/service_providers.dart';
import '../widgets/big_button.dart';

enum RecordType { wellness, interaction, followUp }

/// 显示底部弹窗 (从客户详情"+"按钮调用)
Future<void> showAddRecordSheet(BuildContext context, {required String customerId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bgWarm,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AddRecordSheet(customerId: customerId),
  );
}

class _AddRecordSheet extends ConsumerWidget {
  final String customerId;
  const _AddRecordSheet({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选择记录类型',
                  style: TextStyle(
                    fontSize: AppTheme.fontLg,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: AppTheme.fontMd),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 3 选 1 大按钮 (每个 80pt 高)
            _recordButton(
              context,
              icon: Icons.favorite,
              iconColor: AppTheme.accent,
              title: '养生记录',
              hint: '选部位 / 服务 / 拍照',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/wellness-records/new?customerId=$customerId');
              },
            ),
            const SizedBox(height: 12),

            _recordButton(
              context,
              icon: Icons.phone_in_talk,
              iconColor: AppTheme.primary,
              title: '联系记录',
              hint: '日期 + 内容',
              onTap: () {
                Navigator.of(context).pop();
                _showInteractionDialog(context, ref, customerId);
              },
            ),
            const SizedBox(height: 12),

            _recordButton(
              context,
              icon: Icons.notifications_active,
              iconColor: AppTheme.franchisee,
              title: '跟进任务',
              hint: '截止时间 + 内容',
              onTap: () {
                Navigator.of(context).pop();
                _showFollowUpDialog(context, ref, customerId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordButton(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(icon, color: iconColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: AppTheme.fontLg,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: const TextStyle(
                        fontSize: AppTheme.fontSm,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 28, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _showInteractionDialog(BuildContext context, WidgetRef ref, String customerId) {
    final summaryCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('联系记录'),
        content: TextField(
          controller: summaryCtrl,
          style: const TextStyle(fontSize: AppTheme.fontMd),
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '联系内容',
            hintText: '如: 问肩颈好点了没',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (summaryCtrl.text.trim().isEmpty) return;
              try {
                await ref.read(interactionServiceProvider).create({
                  'customerId': customerId,
                  'type': 'phone',
                  'summary': summaryCtrl.text.trim(),
                });
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已添加联系记录')),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('保存失败: $e')),
                );
              }
            },
            child: const Text('保存', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
  }

  void _showFollowUpDialog(BuildContext context, WidgetRef ref, String customerId) {
    final reasonCtrl = TextEditingController();
    DateTime dueAt = DateTime.now().add(const Duration(days: 3));
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('跟进任务'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: reasonCtrl,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '跟进内容',
                  hintText: '如: 提醒复购',
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: dueAt,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setSt(() => dueAt = picked);
                },
                icon: const Icon(Icons.calendar_today, size: 24),
                label: Text(
                  '${dueAt.year}-${dueAt.month.toString().padLeft(2, '0')}-${dueAt.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                ),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonCtrl.text.trim().isEmpty) return;
                try {
                  await ref.read(followUpServiceProvider).create({
                    'customerId': customerId,
                    'reason': reasonCtrl.text.trim(),
                    'dueAt': dueAt.toIso8601String(),
                  });
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已添加跟进任务')),
                  );
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('保存失败: $e')),
                  );
                }
              },
              child: const Text('保存', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
          ],
        ),
      ),
    );
  }
}