// ============================================
// 「标记完成」弹层 + 「添加联系记录」弹层 (2026-09-24 拍板)
//
// 主人诉求 (2026-09-24 客户详情「记录」Tab 重构):
//   ① 「标记完成」跟进任务后, 应该让用户选择「跟进的方式」(电话/微信/到店…) +
//     可在弹层里备注「聊了什么」, 而不是直接消除任务。
//   ② 客户详情「记录」Tab 「添加联系记录」按钮**复用**完成跟进的弹层, 但只
//     调 `interactionService.create`, 不 complete 任务, 不 track。
//
// 三件事顺序 (仅「标记完成」走, 1 失败 → 弹层**不**关闭, 留在原地可重试;
//                1 成功 + 2 失败 → 弹层关闭, SnackBar 明确说「任务已完成, 但互动记录失败: …」):
//   1. followUpService.complete(id, notes: 备注) —— 任务收尾
//   2. interactionService.create({customerId, type, summary?}) —— 记一条联系
//   3. usageService.track('follow_up_done') —— 用量埋点 (一致收口, 原来两调用方各自 track → 会双报)
//
// 为什么不是独立页面:
//   「从客户详情直接建一条跟进 / 记一条联系」是高频入口 → 就地弹层, 不动路由。
//
// 为什么两个入口共用一份 widget:
//   弹层 UI / 行为差异仅 4 个开关: 标题文案 / 提交按钮文案 / 是否 complete 任务 / 是否 track。
//   抽一个私有 `_InteractionSheet` + `task` 可空 → 一份实现服务两种入口, 避免
//   「修完成跟进的 bug 时忘了同步修添加联系」(同根 §5「并发 session commit」: 一份源码 + 两处复制 → 一改一漏)。
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/follow_up.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_events.dart' show UsageEntityType;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';

/// 「完成跟进」弹层入口 —— 弹出底 sheet, 一次动作 = 三件事 (complete + create interaction + track)。
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
    builder: (ctx) => _InteractionSheet(
      task: task,
      customerName: customerName,
      ref: ref,
      title: customerName == null ? '完成跟进' : '完成跟进 · 「$customerName」',
      submitLabel: '标记完成',
      completeTask: true,
    ),
  );
}

/// 「添加联系记录」弹层入口 (2026-09-24 拍: 复用完成跟进的弹层)。
///
/// 标题「添加联系记录」, 按钮「保存」, 只 `interactionService.create`,
/// 不 complete 任务、不 track。
///
/// 调用方 (客户详情「记录」Tab `_addButtonsRow`) 拿到 `true` 后应自行 invalidate
/// `interactionsForCustomerProvider(customerId)` —— 本弹层已经做了。
Future<bool?> showAddInteractionSheet(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
  String? customerName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _InteractionSheet(
      // task 为 null → 走「不 complete 任务」分支
      task: null,
      customerId: customerId,
      customerName: customerName,
      ref: ref,
      title: customerName == null ? '添加联系记录' : '添加联系记录 · 「$customerName」',
      submitLabel: '保存',
      completeTask: false,
    ),
  );
}

// ============================================
// 私有 widget: 「添加联系记录 / 完成跟进」共用一份 UI
// ============================================

class _InteractionSheet extends StatefulWidget {
  /// 完成跟进时: 必填, 弹层需要 complete 这个任务。
  /// 添加联系记录时: 传 null, 跳过 complete 路径。
  final FollowUpTask? task;

  /// 「添加联系记录」分支用 (task 为 null 时): 直接传 customerId。
  /// 「完成跟进」分支 (task 非 null): 此字段被忽略, 用 `task.customerId`。
  final String? customerId;

  final String? customerName;
  final WidgetRef ref;

  /// 弹层大标题 (有 customerName 时拼上「· 「xxx」」由调用方控制)
  final String title;

  /// 主按钮文案 (「标记完成」 / 「保存」)
  final String submitLabel;

  /// true=「完成跟进」模式 (complete + track + invalidate 两个 provider);
  /// false=「添加联系记录」模式 (只 create interaction + invalidate 一个 provider)
  final bool completeTask;

  const _InteractionSheet({
    required this.task,
    required this.ref,
    required this.title,
    required this.submitLabel,
    required this.completeTask,
    this.customerId,
    this.customerName,
  });

  @override
  State<_InteractionSheet> createState() => _InteractionSheetState();
}

class _InteractionSheetState extends State<_InteractionSheet> {
  /// 选中的跟进方式 (默认「电话」)
  String _selectedType = 'phone';

  /// 备注 / 跟进内容 (可选)
  final TextEditingController _summaryCtrl = TextEditingController();

  /// 提交中 —— 防止重复点 / 双报
  bool _saving = false;

  /// 真正要操作的客户 ID (归一化: task 优先 → 显式 customerId 兜底)
  String get _customerId => widget.task?.customerId ?? widget.customerId!;

  /// 副标题行内容 (有 task 时显示任务 reason; 无则不显示 ——
  ///   「添加联系记录」是临时自由记录, 没绑定具体任务)
  String? get _reason => widget.task?.reason;

  @override
  void dispose() {
    _summaryCtrl.dispose();
    super.dispose();
  }

  /// 「标记完成」/「保存」按钮回调 —— 根据 `completeTask` 走两条路径
  Future<void> _onSubmit(StateSetter setSheetState) async {
    if (_saving) return;
    setSheetState(() => _saving = true);

    // 提前捕获 messenger —— Navigator.pop 后 ctx.mounted 可能为 false, 但 messenger
    // 来自父 Scaffold, 一直活着, 这是 ShowSnackBar 的正确姿势。
    final messenger = ScaffoldMessenger.of(context);
    final summary = _summaryCtrl.text.trim();
    final hasNotes = summary.isNotEmpty;

    // =============== 「完成跟进」分支 (complete + interaction + track) ===============
    if (widget.completeTask) {
      final task = widget.task!;
      // 1. 跟进任务标完成 (notes 透传 — 完成备注跟 Interaction 后口同步)
      try {
        await widget.ref.read(followUpServiceProvider).complete(
              task.id,
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
      bool interactionMembership = false;
      try {
        await widget.ref.read(interactionServiceProvider).create({
          'customerId': _customerId,
          'type': _selectedType,
          if (hasNotes) 'summary': summary,
        });
      } catch (e) {
        // 2026-09-25: 402 (会员功能) 不弹裸异常 —— 全局 onMembershipRequired 已有人话提示,
        //   这里是「任务已完成 + 互动需会员」的**部分成功**, 给友好提示就够了。
        if (_isMembershipRequired(e)) {
          interactionMembership = true;
        } else {
          interactionError = e.toString();
        }
      }

      // 3. 用量埋点 (1 成功后就 track —— follow_up_done 跟 Interaction 后口成败解耦,
      //    因为 task 本身确实完成了; 部分成功用 SnackBar 文案区分, 不动埋点)
      widget.ref.read(usageServiceProvider).track(
            'follow_up_done',
            entityType: UsageEntityType.followUp,
            entityId: task.id,
          );

      // 4. 失效两个 provider (弹层内就 commit, 调用方拿 true 后再 invalidate 自己独有的)
      widget.ref.invalidate(customerFollowUpTasksProvider(_customerId));
      widget.ref.invalidate(interactionsForCustomerProvider(_customerId));

      // 5. 关弹层 + 反馈
      Navigator.pop(context, true);
      final typeLabel = interactionTypeLabels[_selectedType] ?? _selectedType;
      if (interactionError == null && !interactionMembership) {
        messenger.showSnackBar(
          SnackBar(content: Text('已标记完成 · 已记一条${typeLabel}互动')),
        );
      } else if (interactionMembership) {
        // 部分成功: 任务已标完成 (不可逆); 互动是会员功能, 不让记录这单
        //   —— 明确告知, 全局提示已有人话说明, 这里不再重复「会员」字样
        messenger.showSnackBar(
          const SnackBar(
            content: Text('任务已完成（互动记录是会员功能, 本次未记录）'),
          ),
        );
      } else {
        // 部分成功: 任务确实完成了 (不可逆), 但互动没记上 —— 明确告知, 不让用户以为全好
        // 2026-09-26: interactionError 可能是 dio 抓出来的 500 / network 原始文
        // (「DioException (... 500)...」 人读不慬) —— 人话化一下, 让用户知道是哪里挂了
        final human = _humanizeInteractionError(interactionError ?? '未知错误');
        messenger.showSnackBar(
          SnackBar(content: Text('任务已完成, 但互动记录未保存: $human')),
        );
      }
      return;
    }

    // =============== 「添加联系记录」分支 (只 create interaction) ===============
    try {
      await widget.ref.read(interactionServiceProvider).create({
        'customerId': _customerId,
        'type': _selectedType,
        if (hasNotes) 'summary': summary,
      });
      // 失效一个 provider (本弹层就 commit)
      widget.ref.invalidate(interactionsForCustomerProvider(_customerId));
      Navigator.pop(context, true);
      final typeLabel = interactionTypeLabels[_selectedType] ?? _selectedType;
      messenger.showSnackBar(
        SnackBar(content: Text('已记一条${typeLabel}互动')),
      );
    } catch (e) {
      if (mounted) {
        setSheetState(() => _saving = false);
        // 2026-09-25: 402 → 全局 onMembershipRequired 已负责人话说明, 这里不再
        //   弹裸「保存失败: DioException(...402)」让人看不懂。
        if (_isMembershipRequired(e)) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('互动记录是会员功能, 本次未保存'),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text('保存失败: $e')),
          );
        }
      }
    }
  }

  /// 异常是不是 402 (Payment Required, 后端用会员门槛)
  ///
  /// 2026-09-25: 之前状态是全弹一层把 DioException(...402) 原样丢给用户, 全局
  ///   onMembershipRequired 已经弹了一条「这是会员功能」提示, 但本弹层**再**贴一条
  ///   「保存失败: DioException(...402)」就重了 + 用户看不懂「Payment Required」。
  ///   兜两类来源: dio 直抛 / 包装过的 ApiException (测试替身常用)。
  bool _isMembershipRequired(Object e) {
    if (e is DioException) {
      return e.response?.statusCode == 402;
    }
    return false;
  }

  /// 部分成功分支 (任务已完成 + 互动未保存) 的友好文案
  ///
  /// 2026-09-26: reviewer 报原本「$interactionError」裸贴 dio 原始文, 用户看不慬。
  /// 修法: 让人话代替 dio stack:
  ///   - 会员 (402): 交由 会员提示 (上方另一分支处理), 本函数不重复
  ///   - 网络/服务器: 取 status code + 接限友好前缀
  ///   - 其他: 保留原文, 但裁车长度, 避免 SnackBar 被 push 出屏
  String _humanizeInteractionError(String raw) {
    // 优先从 dio 异常里抢 statusCode (原串里有 "...502..." 也能挑出来)
    final codeMatch = RegExp(r'\b(\d{3})\b').firstMatch(raw);
    final code = codeMatch?.group(1);
    switch (code) {
      case '500':
      case '502':
      case '503':
        return '服务器暂不可用 ($code), 联系记录稍后补';
      case '408':
      case '504':
        return '请求超时, 联系记录稍后补';
      case '429':
        return '请求太频繁, 联系记录稍后补';
      case '401':
      case '403':
        return '身份过期, 联系记录稍后补';
    }
    // 默认: 保留原文但裁到 60 字 + 友好前缀, 避免 SnackBar 过长被裁
    final trimmed = raw.length > 60 ? '${raw.substring(0, 60)}…' : raw;
    return '稍后补 ($trimmed)';
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
              widget.title,
              style: const TextStyle(
                fontSize: AppTheme.fontLg,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 「完成跟进」分支: 副标题 = 任务 reason (让用户知道完成的是哪条)
            // 「添加联系记录」分支: _reason = null, 不画
            if (_reason != null) ...[
              const SizedBox(height: AppSpace.s6),
              Text(
                _reason!,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
            // 取消 + 主操作 双按钮 (取消 = TextButton, 主操作 = FilledButton)
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
                    label: Text(_saving ? '保存中...' : widget.submitLabel),
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