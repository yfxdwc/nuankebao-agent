import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';

// ============================================
// 「危险操作」卡 (管理 Tab 底部, P8, 主人 2026-09-23)
// ============================================
// 放的是**不可逆 / 影响归属**的操作。集中一处而不是散在页面里, 理由:
//   ① 用户心理上需要"这是危险区"的信号, 混在普通卡片里会被误点;
//   ② 以后再加危险操作 (合并/转移) 有明确的家, 不用每次找地方。
//
// 归档口径 (必须对用户诚实):
//   后端 `DELETE /api/customers/[id]` = **软删** (`deleted_at` 打时间戳),
//   数据行还在库里 —— 但 **App 里没有任何恢复入口** (全仓 grep 无 undelete)。
//   所以确认框**不能写"可恢复"** —— 那是骗人。写清"要找管理员从数据库恢复"。
// ============================================

class CustomerDangerZoneCard extends ConsumerStatefulWidget {
  final String customerId;
  final String customerName;
  const CustomerDangerZoneCard({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  ConsumerState<CustomerDangerZoneCard> createState() =>
      _CustomerDangerZoneCardState();
}

class _CustomerDangerZoneCardState
    extends ConsumerState<CustomerDangerZoneCard> {
  bool _busy = false;

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('归档「${widget.customerName}」？',
            style: const TextStyle(fontSize: AppTheme.fontLg)),
        content: const Text(
          '归档后她不会出现在任何客户列表里，也不会再有跟进提醒。\n\n'
          '养生记录、跟进任务、互动记录**都不会删除**，但 App 里'
          '没有恢复入口 —— 要恢复得联系系统管理员从数据库处理。\n\n'
          '确定归档吗？',
          style: TextStyle(fontSize: AppTheme.fontSm, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('确定归档', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(customerServiceProvider).delete(widget.customerId);
      ref.invalidate(customersProvider);
      ref.invalidate(customerTypeCountsProvider);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('已归档「${widget.customerName}」')),
      );
      // 客户已不在列表里, 停在详情页没有意义 → 退回上一页 (列表)
      navigator.pop();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('归档失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Card(
      margin: EdgeInsets.zero,
      // 危险区视觉: 淡红底 + 红边, 与普通卡片区分开
      color: t.dangerSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: t.danger.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: AppSize.iconMd, color: t.danger),
                const SizedBox(width: AppSpace.s6),
                Text(
                  '危险操作',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                    color: t.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
            Text(
              '归档后她从客户列表消失，且 App 内无法撤销。',
              style: TextStyle(fontSize: AppTheme.fontXs, color: t.textSecondary),
            ),
            const SizedBox(height: AppSpace.s10),
            SizedBox(
              width: double.infinity,
              height: AppSize.controlLg,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _archive,
                icon: _busy
                    ? SizedBox(
                        width: AppSize.iconSm,
                        height: AppSize.iconSm,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.archive_outlined, size: AppSize.iconLg),
                label: const Text('归档这位客户',
                    style: TextStyle(fontSize: AppTheme.fontMd)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.danger,
                  side: BorderSide(color: t.danger.withOpacity(0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
