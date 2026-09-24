// ============================================
// 客户详情页 — 跟进任务 / 互动记录 区 (主人 2026-09-18 拍: 详情页内容要"或更多")
//
// 跟进任务: 该客户待办 (dueAt 最近的在上); 可直接「完成」(PATCH /follow-ups/:id)
// 互动记录: 最近联系流水 (电话/微信/到店/节日问候) + 「记一次互动」入口
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/follow_up.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_events.dart' show UsageEntityType;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import 'ai_insight_cards.dart' show BigActionButton;

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';
// ============================================
// 建跟进任务 弹层 (客户详情页 / AI 跟进卡共用)
//
// 为什么不是独立页面:
//   `modules/follow_up/screens/` 还是空的 (没有 /follow-ups/new 路由),
//   而“从客户详情直接建一条跟进”是最高频入口 → 就地弹层, 不动路由/不动别的模块
// ============================================
Future<void> showAddFollowUpSheet(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
  String? aiSuggestion,
}) async {
  final reasonCtrl = TextEditingController();
  var dueAt = DateTime.now().add(const Duration(days: 1));
  var saving = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: AppSpace.s16,
          right: AppSpace.s16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新建跟进任务',
                style: TextStyle(
                    fontSize: AppTheme.fontLg, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(
                labelText: '跟进什么 *',
                hintText: '例: 打电话问腰疼好点没',
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            const Text('什么时候跟进',
                style: TextStyle(
                    fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
            const SizedBox(height: AppSpace.s8),
            Wrap(
              spacing: 8,
              children: [1, 2, 3, 7, 14]
                  .map((d) => ChoiceChip(
                        label: Text(
                          d == 1 ? '明天' : '${d} 天后',
                          style: const TextStyle(fontSize: AppTheme.fontSm),
                        ),
                        selected: dueAt
                                .difference(DateTime.now())
                                .inDays ==
                            d,
                        onSelected: (_) => setSheetState(
                            () => dueAt = DateTime.now().add(Duration(days: d))),
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppSpace.s16),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (reasonCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('请填写跟进内容')),
                        );
                        return;
                      }
                      setSheetState(() => saving = true);
                      try {
                        await ref.read(followUpServiceProvider).create({
                          'customerId': customerId,
                          'dueAt': dueAt.toUtc().toIso8601String(),
                          'reason': reasonCtrl.text.trim(),
                          if (aiSuggestion != null && aiSuggestion.isNotEmpty)
                            'aiSuggestion': aiSuggestion,
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('跟进任务已创建')),
                          );
                        }
                        ref.read(usageServiceProvider).track(
                              'follow_up_create',
                              props: {'source': 'customer_detail'},
                            );
                        ref.invalidate(
                            customerFollowUpTasksProvider(customerId));
                      } catch (e) {
                        setSheetState(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('保存失败: $e')),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.check, size: AppSize.iconLg),
              label: Text(saving ? '保存中...' : '保存'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, AppSize.buttonLgHeight),
              ),
            ),
            const SizedBox(height: AppSpace.s8),
          ],
        ),
      ),
    ),
  );
}

// ============================================
// 跟进任务 (该客户)
// ============================================

class CustomerFollowUpSection extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerFollowUpSection({super.key, required this.customerId});

  @override
  ConsumerState<CustomerFollowUpSection> createState() =>
      _CustomerFollowUpSectionState();
}

class _CustomerFollowUpSectionState
    extends ConsumerState<CustomerFollowUpSection> {
  String? _completingId;

  Future<void> _complete(FollowUpTask t) async {
    setState(() => _completingId = t.id);
    try {
      await ref.read(followUpServiceProvider).complete(t.id);
      ref.read(usageServiceProvider).track(
            'follow_up_done',
            entityType: UsageEntityType.followUp,
            entityId: t.id,
          );
      if (!mounted) return;
      // invalidate → 列表重拉 (provider 驱动, 不用本地 state)
      ref.invalidate(customerFollowUpTasksProvider(widget.customerId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已标记完成')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _completingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd');
    final async = ref.watch(customerFollowUpTasksProvider(widget.customerId));

    return B2NoChrome(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.task_alt, size: AppSize.iconLg, color: AppTheme.primary),
                const SizedBox(width: AppSpace.s8),
                const Expanded(
                  child: Text('跟进任务',
                      style: TextStyle(
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w700)),
                ),
                async.maybeWhen(
                  data: (tasks) => Flexible(
                    child: Text('${tasks.length} 条待办',
                        style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            async.when(
              loading: () => const _SectionLoading('加载跟进任务...'),
              error: (e, _) => _SectionError(
                message: '$e',
                onRetry: () => ref
                    .invalidate(customerFollowUpTasksProvider(widget.customerId)),
              ),
              data: (tasks) => tasks.isEmpty
                  ? const Text('没有待办跟进',
                      style: TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textSecondary))
                  : Column(children: tasks.map((t) => _tile(t, fmt)).toList()),
            ),
            const SizedBox(height: AppSpace.s8),
            BigActionButton(
              icon: Icons.add_task,
              label: '新建跟进任务',
              compact: true,
              onTap: () => showAddFollowUpSheet(context, ref,
                  customerId: widget.customerId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(FollowUpTask t, DateFormat fmt) {
    // 2026-09-24 用户反馈修: 旧逻辑 `t.dueAt.isBefore(DateTime.now())` 按时间戳比,
    //   建完下一秒就误判"已过期"。改走日期口径 (`isFollowUpOverdue` = 与后端
    //   `urgency.ts::daysBetween > 0` 同口径), 今天 / 明天 / 更远 文案分开。
    final overdue = isFollowUpOverdue(t.dueAt);
    final daysUntil = followUpDaysUntilDue(t.dueAt);
    final dueLabel = overdue
        ? '${fmt.format(t.dueAt.toLocal())} · 已过期'
        : daysUntil == 0
            ? '今天到期'
            : daysUntil == 1
                ? '明天到期'
                : '${fmt.format(t.dueAt.toLocal())} 到期';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.s8),
      padding: const EdgeInsets.all(AppSpace.s12),
      decoration: BoxDecoration(
        color: overdue ? AppTheme.danger.withOpacity(0.06) : AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(AppRadius.r10),
        border: Border.all(
          color: overdue
              ? AppTheme.danger.withOpacity(0.3)
              : AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.reason,
                  style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpace.s4),
                Text(
                  dueLabel,
                  style: TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: overdue ? AppTheme.danger : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_completingId == t.id)
            const SizedBox(
              width: AppSpace.s20,
              height: AppSpace.s20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_circle_outline, size: AppSize.iconLg),
              tooltip: '标记完成',
              color: AppTheme.primary,
              onPressed: () => _complete(t),
            ),
        ],
      ),
    );
  }
}

// ============================================
// 互动记录 (该客户)
// ============================================

class CustomerInteractionSection extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerInteractionSection({super.key, required this.customerId});

  @override
  ConsumerState<CustomerInteractionSection> createState() =>
      _CustomerInteractionSectionState();
}

class _CustomerInteractionSectionState
    extends ConsumerState<CustomerInteractionSection> {
  static const _typeLabel = {
    'phone': '电话',
    'wechat': '微信',
    'visit': '到店',
    'holiday_greeting': '节日问候',
    'other': '其他',
  };

  static const _typeIcon = {
    'phone': Icons.phone,
    'wechat': Icons.chat,
    'visit': Icons.storefront,
    'holiday_greeting': Icons.card_giftcard,
    'other': Icons.more_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd');
    final async = ref.watch(interactionsForCustomerProvider(widget.customerId));
    final items = async.valueOrNull ?? const <Interaction>[];

    return B2NoChrome(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.forum_outlined, size: AppSize.iconLg, color: AppTheme.accent),
                const SizedBox(width: AppSpace.s8),
                const Expanded(
                  child: Text('互动记录',
                      style: TextStyle(
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w700)),
                ),
                if (items.isNotEmpty)
                  Flexible(
                    child: Text('共 ${items.length} 次',
                        style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            async.when(
              loading: () => const _SectionLoading('加载互动记录...'),
              error: (e, _) => _SectionError(
                message: '$e',
                onRetry: () => ref
                    .invalidate(interactionsForCustomerProvider(widget.customerId)),
              ),
              data: (items) => items.isEmpty
                  ? const Text('还没记过联系',
                      style: TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textSecondary))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: items
                          .take(5)
                          .map((i) => Padding(
                                padding: const EdgeInsets.only(bottom: AppSpace.s8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(_typeIcon[i.type] ?? Icons.more_horiz,
                                        size: AppSize.iconMd, color: AppTheme.textSecondary),
                                    const SizedBox(width: AppSpace.s8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${_typeLabel[i.type] ?? i.type} · ${fmt.format(i.createdAt)}',
                                            style: const TextStyle(
                                                fontSize: AppTheme.fontSm,
                                                fontWeight: FontWeight.w600),
                                          ),
                                          if (i.summary != null &&
                                              i.summary!.isNotEmpty)
                                            Text(i.summary!,
                                                style: const TextStyle(
                                                    fontSize: AppTheme.fontXs,
                                                    color: AppTheme
                                                        .textSecondary)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// 小块 (加载 / 错误)
// ============================================

class _SectionLoading extends StatelessWidget {
  final String label;
  const _SectionLoading(this.label);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
              width: AppSpace.s18, height: AppSpace.s18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppSpace.s10),
          Text(label,
              style: const TextStyle(
                  fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
        ],
      );
}

class _SectionError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SectionError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('加载失败: $message',
              style: const TextStyle(
                  fontSize: AppTheme.fontSm, color: AppTheme.danger)),
          const SizedBox(height: AppSpace.s8),
          BigActionButton(
              icon: Icons.refresh, label: '重试', compact: true, onTap: onRetry),
        ],
      );
}
