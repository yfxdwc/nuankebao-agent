// ============================================
// 互动记录详情底部弹层 (2026-09-25 第 5 项)
//
// 主人原话: 时间线互动行点击 → 弹出详情弹层, 可编辑/删除
//   · 查看态: 类型 + 时间 + 内容全文; 操作 [编辑] [删除]
//   · 编辑态: 5 个类型 ChoiceChip + 内容 TextField + [保存]
//   · 删除: AlertDialog 二次确认 (文案「删除后不可恢复」) → service.delete → invalidate → pop + SnackBar
//   · 样式走 AppSheetHeader + tokens; 热区 ≥48; TextStyle 显式 color (AGENTS §5 白字教训)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/follow_up.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_sheet_header.dart';

/// 弹出互动记录详情底部弹层
///
/// [interaction] 当前行记录; [customerId] 用于 invalidate 列表 provider。
Future<void> showInteractionDetailSheet(
  BuildContext context,
  WidgetRef ref, {
  required Interaction interaction,
  required String customerId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
    ),
    builder: (ctx) => _InteractionDetailSheet(
      interaction: interaction,
      customerId: customerId,
    ),
  );
}

class _InteractionDetailSheet extends ConsumerStatefulWidget {
  final Interaction interaction;
  final String customerId;
  const _InteractionDetailSheet({
    required this.interaction,
    required this.customerId,
  });

  @override
  ConsumerState<_InteractionDetailSheet> createState() =>
      _InteractionDetailSheetState();
}

class _InteractionDetailSheetState
    extends ConsumerState<_InteractionDetailSheet> {
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;

  /// 编辑态才用; 初始 = 当前记录的 type / summary
  late String _editType;
  late TextEditingController _editSummaryCtrl;

  @override
  void initState() {
    super.initState();
    _editType = widget.interaction.type;
    _editSummaryCtrl =
        TextEditingController(text: widget.interaction.summary ?? '');
  }

  @override
  void dispose() {
    _editSummaryCtrl.dispose();
    super.dispose();
  }

  /// 转「YYYY-MM-DD HH:mm」, 与互动行视觉保持一致
  String _formatTime(DateTime t) {
    final l = t.toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(l);
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final summary = _editSummaryCtrl.text.trim();
    try {
      await ref.read(interactionServiceProvider).update(
            widget.interaction.id,
            {
              'type': _editType,
              if (summary.isNotEmpty) 'summary': summary,
              // summary 空字符串显式清空 (后端契约: 传 "" = 清空 summary 字段)
              if (summary.isEmpty) 'summary': '',
            },
          );
      ref.invalidate(interactionsForCustomerProvider(widget.customerId));
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('已更新')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条联系记录?'),
        content: const Text(
          '删除后不可恢复, 建议改用「编辑」先看清楚内容再决定。',
          style: TextStyle(
            fontSize: AppType.md,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('deleteDialogCancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppSize.tapMin),
            ),
            child: const Text('取消',
                style: TextStyle(
                    fontSize: AppType.md,
                    color: AppColors.textSecondary)),
          ),
          TextButton(
            key: const ValueKey('deleteDialogConfirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppSize.tapMin),
            ),
            child: const Text('删除',
                style: TextStyle(
                  fontSize: AppType.md,
                  color: AppColors.danger,
                  fontWeight: AppWeight.semibold,
                )),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(interactionServiceProvider)
          .delete(widget.interaction.id);
      ref.invalidate(interactionsForCustomerProvider(widget.customerId));
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('已删除')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger.showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  void _enterEdit() {
    setState(() {
      _editing = true;
      // 重置编辑字段 = 当前值 (防止上次编辑残留)
      _editType = widget.interaction.type;
      _editSummaryCtrl.text = widget.interaction.summary ?? '';
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editType = widget.interaction.type;
      _editSummaryCtrl.text = widget.interaction.summary ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.interaction;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.s16,
          AppSpace.s4,
          AppSpace.s16,
          AppSpace.s20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppSheetHeader(
              title: _editing ? '编辑联系记录' : '联系记录',
              actions: _editing
                  ? <Widget>[]
                  : <Widget>[
                      TextButton(
                        key: const ValueKey('interactionSheetEdit'),
                        onPressed: _enterEdit,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, AppSize.tapMin),
                        ),
                        child: const Text('编辑',
                            style: TextStyle(
                              fontSize: AppType.md,
                              color: AppColors.textSecondary,
                            )),
                      ),
                      TextButton(
                        key: const ValueKey('interactionSheetDelete'),
                        onPressed: _deleting ? null : _confirmDelete,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, AppSize.tapMin),
                        ),
                        child: const Text('删除',
                            style: TextStyle(
                              fontSize: AppType.md,
                              color: AppColors.danger,
                            )),
                      ),
                    ],
            ),
            if (!_editing) ...<Widget>[
              // 类型 + 时间
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      interactionTypeLabels[i.type] ?? i.type,
                      style: const TextStyle(
                        fontSize: AppType.lg,
                        fontWeight: AppWeight.semibold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpace.tightGap),
                    Text(
                      _formatTime(i.createdAt),
                      style: const TextStyle(
                        fontSize: AppType.sm,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpace.s14),
                    // 内容全文 (可能空)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpace.s14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Text(
                        (i.summary == null || i.summary!.isEmpty)
                            ? '（无备注内容）'
                            : i.summary!,
                        style: TextStyle(
                          fontSize: AppType.md,
                          color: (i.summary == null || i.summary!.isEmpty)
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...<Widget>[
              // 编辑态: 类型 chips + 内容 TextField + [取消] [保存]
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('跟进方式',
                        style: TextStyle(
                          fontSize: AppType.sm,
                          color: AppColors.textSecondary,
                        )),
                    const SizedBox(height: AppSpace.s8),
                    Wrap(
                      spacing: AppSpace.s8,
                      runSpacing: AppSpace.s8,
                      children: interactionTypeLabels.entries
                          .map<Widget>((e) => ChoiceChip(
                                key: ValueKey('editType_${e.key}'),
                                label: Text(e.value,
                                    style: const TextStyle(
                                        fontSize: AppType.sm)),
                                selected: _editType == e.key,
                                onSelected: _saving
                                    ? null
                                    : (_) => setState(
                                          () => _editType = e.key,
                                        ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: AppSpace.s16),
                    TextField(
                      key: const ValueKey('editSummaryField'),
                      controller: _editSummaryCtrl,
                      maxLines: 3,
                      minLines: 2,
                      enabled: !_saving,
                      style: const TextStyle(
                          fontSize: AppType.md,
                          color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: '跟进内容',
                        hintText: '可空; 清空 = 删除这段备注',
                      ),
                    ),
                    const SizedBox(height: AppSpace.s20),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextButton(
                            key: const ValueKey('editCancelBtn'),
                            onPressed:
                                _saving ? null : _cancelEdit,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                  0, AppSize.buttonLgHeight),
                            ),
                            child: const Text('取消',
                                style: TextStyle(
                                    fontSize: AppType.md,
                                    color: AppColors.textSecondary)),
                          ),
                        ),
                        const SizedBox(width: AppSpace.s10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            key: const ValueKey('editSaveBtn'),
                            onPressed: _saving ? null : _onSave,
                            icon: _saving
                                ? const SizedBox(
                                    width: AppSize.iconMd,
                                    height: AppSize.iconMd,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check,
                                    size: AppSize.iconLg),
                            label: Text(_saving ? '保存中...' : '保存'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(
                                  0, AppSize.buttonLgHeight),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpace.s8),
          ],
        ),
      ),
    );
  }
}