// ============================================
// 客户详情页 — 跟进任务 区 (2026-09-24 拍「记录 Tab 重构」)
//
// 本文件**只**保留「跟进任务」区: 互动的展示/记录已迁移到 `customer_timeline_section.dart`
// (混合列表 + 胶囊过滤); 旧 `CustomerInteractionSection` 已删除。
//
// 跟进任务区变化 (2026-09-24):
//   · header 右上角加紧凑「+ 新建」按钮 (不换行不溢出), 沿用原 `showAddFollowUpSheet`
//   · 底部「新建跟进任务」BigActionButton 已删 (原独占一行, 反 vibe;
//     同时跟「两个添加按钮在混合列表上方」重复 —— 删其一)
//   · 「N 条待办」计数保留
//
// 「标记完成」 → 弹出新弹层 (主人 2026-09-24 拍: 选跟进方式 + 记内容)。
//   弹层自己管 saving 转圈 → 本 widget 回归 ConsumerWidget,
//   去掉没用的状态和 setState。 (为什么这么改: 2026-09-24 反馈
//   「点击跟进后只看到任务没了」—— 一闪而过的 spinner 不解决"不知道怎么跟进的"问题,
//   弹层才对。)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/follow_up.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';
import '../../follow_up/widgets/complete_follow_up_sheet.dart';

// ============================================
// 建跟进任务 弹层 (客户详情页 / AI 跟进卡共用)
//
// 为什么不是独立页面:
//   `modules/follow_up/screens/` 还是空的 (没有 /follow-ups/new 路由),
//   而"从客户详情直接建一条跟进"是最高频入口 → 就地弹层, 不动路由/不动别的模块
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

class CustomerFollowUpSection extends ConsumerWidget {
  final String customerId;
  const CustomerFollowUpSection({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('MM-dd');
    final async = ref.watch(customerFollowUpTasksProvider(customerId));

    return B2NoChrome(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header: 标题 + 「N 条待办」计数 + 右上角紧凑「新建」按钮 (2026-09-24 拍)
            //   原底部 BigActionButton 已删; 此处一行内同时容纳:
            //   · 标题 (固定左)
            //   · 「N 条待办」(Flexible, 窄屏省略, 中老年放大字号不撑破 Row)
            //   · 「+ 新建」按钮 (固定右, TextButton.icon 风格, **不换行不独占行**)
            Row(
              children: [
                const Icon(Icons.task_alt,
                    size: AppSize.iconLg, color: AppTheme.primary),
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
                const SizedBox(width: AppSpace.s8),
                TextButton.icon(
                  // 「+ 新建」紧凑按钮 (header 行右侧, 不换行不溢出)
                  //   visualDensity: compact 缩 padding 让按钮更紧, 避免中老年字号下被挤到下一行
                  onPressed: () => showAddFollowUpSheet(context, ref,
                      customerId: customerId),
                  icon: const Icon(Icons.add, size: AppSize.iconMd),
                  label: const Text('新建',
                      style: TextStyle(fontSize: AppTheme.fontSm)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.s8, vertical: AppSpace.s4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            async.when(
              loading: () => const _SectionLoading('加载跟进任务...'),
              error: (e, _) => _SectionError(
                message: '$e',
                onRetry: () => ref
                    .invalidate(customerFollowUpTasksProvider(customerId)),
              ),
              data: (tasks) => tasks.isEmpty
                  ? const Text('没有待办跟进',
                      style: TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textSecondary))
                  : Column(
                      children: tasks
                          .map((t) => _tile(context, ref, t, fmt))
                          .toList()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    FollowUpTask t,
    DateFormat fmt,
  ) {
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
          IconButton(
            icon: const Icon(Icons.check_circle_outline, size: AppSize.iconLg),
            tooltip: '标记完成',
            color: AppTheme.primary,
            onPressed: () async {
              // 2026-09-24 弹层接手: complete + 记互动 + track + invalidate +
              // SnackBar 都收进 showCompleteFollowUpSheet。返回值: true=业务完成 (含部分成功),
              // false=用户取消, null=异常。返回 false 时什么也不动 (本来就是用户的本意)。
              await showCompleteFollowUpSheet(context, ref, task: t);
            },
          ),
        ],
      ),
    );
  }
}

// ============================================
// 小块 (加载 / 错误)
//
// 跟进任务还在用, 保留; 旧的互动 section 跟随整体删除后, 这两个 helper 仍被
// CustomerFollowUpSection 引用 —— 不删。
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
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: AppSize.iconMd),
            label: const Text('重试', style: TextStyle(fontSize: AppTheme.fontSm)),
            onPressed: onRetry,
          ),
        ],
      );
}