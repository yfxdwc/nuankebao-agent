// ============================================
// + 添加记录 弹窗 (Plan F2 极简版)
// 2 选 1: 养生记录 / 联系记录
// 中老年: 大按钮 80pt 高, 大字
// 强绑 customer (customerId 必传)
//
// 跟进任务入口 (2026-09-24 删除):
//   原 3 选 1 含「跟进任务」, 但与
//   `customer_activity_cards.dart::showAddFollowUpSheet` 功能重复,
//   且老实现更弱: ① 居中 AlertDialog 老风格 ② 只有日期选择器
//   (无快捷 chip) ③ 默认 3 天硬编码 ④ 建完不 invalidate 跟进任务列表
//   ⑤ 无 usage.track 埋点。
//   唯一跟进入口 = 客户详情「跟进任务」卡的「新建跟进任务」 +
//   AI 卡片复用 showAddFollowUpSheet (二者都走快捷 chip + AI 建议 +
//   track + invalidate, 见 customer_activity_cards.dart:showAddFollowUpSheet)。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/service_providers.dart';

import '../../../core/theme/tokens.g.dart';

/// 显示底部弹窗 (从客户详情"+"按钮调用)
Future<void> showAddRecordSheet(BuildContext context, {required String customerId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bgWarm,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
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
        padding: const EdgeInsets.fromLTRB(AppSpace.s20, 20, 20, 24),
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
            const SizedBox(height: AppSpace.s8),

            // 2 选 1 大按钮 (每个 80pt 高)
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
            const SizedBox(height: AppSpace.s12),

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
      borderRadius: BorderRadius.circular(AppRadius.r16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r16),
        child: Container(
          height: AppSpace.s80,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s20),
          child: Row(
            children: [
              Container(
                width: AppSpace.s56,
                height: AppSpace.s56,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppRadius.r28),
                ),
                child: Icon(icon, color: iconColor, size: AppSize.iconXl),
              ),
              const SizedBox(width: AppSpace.s16),
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
                    const SizedBox(height: AppSpace.s4),
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
              const Icon(Icons.chevron_right, size: AppSize.iconXl, color: AppTheme.textSecondary),
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
}