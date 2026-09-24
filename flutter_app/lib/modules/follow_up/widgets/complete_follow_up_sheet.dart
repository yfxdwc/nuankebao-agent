// ============================================
// 「标记完成」弹层 (主人 2026-09-24 拍板)
//
// 主人诉求: 跟进任务点「标记完成」后, 应该让用户选择「跟进的方式」(电话/微信/到店…)
//   + 可在弹层里备注「聊了什么」, 而不是直接消除任务。
//
// 为什么独立成 widget 而不是塞进 customer_activity_cards / follow_ups_page:
//   两处调用方 (客户详情「跟进任务」区 + 全局「跟进待办」页) 共用同一份交互:
//   · PATCH /api/follow-ups/:id (action=complete, notes?: 备注)
//   · POST /api/interactions (customerId, type, summary)
//   · track('follow_up_done') + invalidate 两个 provider + SnackBar 反馈
//   抽出来后: 调用方只 await Future<bool>, 自身再按返回值决定 invalidate 自己独有的
//   provider (e.g. follow_ups_page 的 pendingFollowUpsProvider —— 不在本文件内 import,
//   避免 widget→screen 反向依赖)。
//
// 三件事顺序 (交互完整后才算业务完成):
//   1. followUpService.complete(id, notes: 备注) —— 任务收尾
//   2. interactionService.create({customerId, type, summary?}) —— 记一条联系
//   3. usageService.track('follow_up_done') —— 用量埋点 (一致收口, 原来两个调用方各自 track → 会双报)
//   1 失败 → 弹层**不**关闭, 留在原地可重试;
//   1 成功 + 2 失败 → 弹层关闭, SnackBar 明确说「任务已完成, 但互动记录失败: …」(不撒谎)
//   取消 / 全部成功 → 弹层关闭, SnackBar「已标记完成 · 已记一条${type}互动」。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/follow_up.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_events.dart' show UsageEntityType;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';

/// 弹出「完成跟进」弹层, 一次动作 = 三件事 (complete + create interaction + track)。
///
/// 返回:
///   `true`  业务完成 (含"任务完成 + 互动失败"的**部分成功**, 见上文说明)
///   `false` 用户取消
///   `null`  弹层异常 / 用户从系统返回手势关闭
///
/// 调用方拿到 `true` 后应自行 invalidate **自己独有的** provider —— 本弹层不知道
/// 调用方是谁, 不能跨 widget→screen 反向依赖。
Future<bool?> showCompleteFollowUpSheet(
  BuildContext context,
  WidgetRef ref, {
  required FollowUpTask task,
  String? customerName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CompleteFollowUpSheet(
      task: task,
      customerName: customerName,
      ref: ref,
    ),
  );
}

class _CompleteFollowUpSheet extends StatefulWidget {
  final FollowUpTask task;
  final String? customerName;
  final WidgetRef ref;
  const _CompleteFollowUpSheet({
    required this.task,
    required this.customerName,
    required this.ref,
  });

  @override
  State<_CompleteFollowUpSheet> createState() => _CompleteFollowUpSheetState();
}

class _CompleteFollowUpSheetState extends State<_CompleteFollowUpSheet> {
  /// 选中的跟进方式 (默认「电话」)
  String _selectedType = 'phone';

  /// 备注 / 跟进内容 (可选)
  final TextEditingController _summaryCtrl = TextEditingController();

  /// 提交中 —— 防止重复点 / 双报
  bool _saving = false;

  @override
  void dispose() {
    _summaryCtrl.dispose();
    super.dispose();
  }

  /// 「标记完成」按钮回调 —— 一次动作三件事 (顺序见文件头注释)
  Future<void> _onSubmit(StateSetter setSheetState) async {
    if (_saving) return;
    setSheetState(() => _saving = true);

    // 提前捕获 messenger —— Navigator.pop 后 ctx.mounted 可能为 false, 但 messenger
    // 来自父 Scaffold, 一直活着, 这是 ShowSnackBar 的正确姿势。
    final messenger = ScaffoldMessenger.of(context);
    final summary = _summaryCtrl.text.trim();
    final hasNotes = summary.isNotEmpty;

    // 1. 跟进任务标完成 (notes 透传 — 完成备注跟 Interaction 后口同步)
    try {
      await widget.ref.read(followUpServiceProvider).complete(
            widget.task.id,
            notes: hasNotes ? summary : null,
          );
    } catch (e) {
      // 1 失败 → 留在弹层里, 不关弹层, 留 saving=false 让用户重试
      if (mounted) {
        setSheetState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(content: Text('标记完成失败: $e')),
        );
      }
      return;
    }

    // 2. 记一条互动 (可能失败)
    String? interactionError;
    try {
      await widget.ref.read(interactionServiceProvider).create({
        'customerId': widget.task.customerId,
        'type': _selectedType,
        if (hasNotes) 'summary': summary,
      });
    } catch (e) {
      interactionError = e.toString();
    }

    // 3. 用量埋点 (1 成功后就 track —— follow_up_done 跟 Interaction 后口成败解耦,
    //    因为 task 本身确实完成了; 部分成功用 SnackBar 文案区分, 不动埋点)
    widget.ref.read(usageServiceProvider).track(
          'follow_up_done',
          entityType: UsageEntityType.followUp,
          entityId: widget.task.id,
        );

    // 4. 失效两个 provider (弹层内就 commit, 调用方拿 true 后再 invalidate 自己独有的)
    widget.ref.invalidate(customerFollowUpTasksProvider(widget.task.customerId));
    widget.ref.invalidate(interactionsForCustomerProvider(widget.task.customerId));

    // 5. 关弹层 + 反馈
    Navigator.pop(context, true);
    final typeLabel = interactionTypeLabels[_selectedType] ?? _selectedType;
    if (interactionError == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('已标记完成 · 已记一条${typeLabel}互动')),
      );
    } else {
      // 部分成功: 任务确实完成了 (不可逆), 但互动没记上 —— 明确告知, 不让用户以为全好
      messenger.showSnackBar(
        SnackBar(content: Text('任务已完成, 但互动记录失败: $interactionError')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
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
            // 标题 + 客户名 (有就显示, 没有就只标题 —— 同 B 档「不堆叠」原则)
            Text(
              widget.customerName == null
                  ? '完成跟进'
                  : '完成跟进 · 「${widget.customerName}」',
              style: const TextStyle(
                fontSize: AppTheme.fontLg,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 副标题 = 任务 reason (context, 让用户知道完成的是哪条)
            const SizedBox(height: AppSpace.s6),
            Text(
              widget.task.reason,
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpace.s16),
            // 跟进方式 (5 个 ChoiceChip, 默认「电话」)
            const Text(
              '跟进方式',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.s8),
            Wrap(
              spacing: AppSpace.s8,
              runSpacing: AppSpace.s8,
              children: interactionTypeLabels.entries
                  .map((e) => ChoiceChip(
                        label: Text(
                          e.value,
                          style: const TextStyle(fontSize: AppTheme.fontSm),
                        ),
                        selected: _selectedType == e.key,
                        onSelected: _saving
                            ? null
                            : (_) => setSheetState(
                                  () => _selectedType = e.key,
                                ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppSpace.s16),
            // 跟进内容 (可选, 多行)
            TextField(
              controller: _summaryCtrl,
              maxLines: 3,
              enabled: !_saving,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(
                labelText: '跟进内容 (可选)',
                hintText: '例: 腰疼好多了, 约下周三到店',
              ),
            ),
            const SizedBox(height: AppSpace.s20),
            // 取消 + 标记完成 双按钮 (取消 = TextButton, 主操作 = FilledButton)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      minimumSize:
                          const Size(0, AppSize.buttonLgHeight),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(fontSize: AppTheme.fontMd),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.s10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _onSubmit(setSheetState),
                    icon: _saving
                        ? const SizedBox(
                            width: AppSize.iconMd,
                            height: AppSize.iconMd,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: AppSize.iconLg),
                    label: Text(_saving ? '保存中...' : '标记完成'),
                    style: FilledButton.styleFrom(
                      minimumSize:
                          const Size(0, AppSize.buttonLgHeight),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
          ],
        ),
      ),
    );
  }
}