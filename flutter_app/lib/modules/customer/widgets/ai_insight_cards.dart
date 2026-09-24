// ============================================
// 客户详情页 — AI 智能卡片
// ============================================
// 设计原则:
//   1. **省钱**: 三张卡 (画像 / 话术 / 效果) 共用**一次**调用 (P5, 主人 2026-09-23 拍);
//      卡片仍是三张 (场景不同), 合的是**调用**不是界面。
//   2. **中老年友好**: 字号 16+ / 大按钮 / 结果用大白话。
//   3. **失败可恢复**: 生成失败给明确文案 + 重试按钮 (不静默吞错; 402 走锁态)。
//
// 2026-09-25 改造 (P0 锁态 / P1 节奏卡 / P2 单入口):
//   · P0 会员锁态: 后端已返回 `customerInsightProvider(scriptAvailable)`,
//     Flutter 模型已解析, 此前没人用。scriptAvailable == false 时:
//     - 第一张 AI 卡 (话术卡) 出「升级会员」按钮 + 一行小字「一次生成: 画像 + 话术 + 效果」;
//     - 画像卡 / 效果分析卡 出同款锁块 (无按钮);
//     - 话术卡的 4 个「跟进理由」ChoiceChip 一并隐藏 (选了就要触发生成, 没意义)。
//   · P1 节奏卡: 旧的 RepurchaseCard 已并入 customer_rhythm_card.dart
//     (跟进分析 + 复购预测合并卡); 本文件只剩 3 张 AI 卡 + 通用部件。
//   · P2 单入口: 三张卡不再各自出「生成」按钮, 只在话术卡 (AiFollowUpCard) 出
//     「生成 AI 解读」+ 一行小字; 画像/效果卡在没数据时改为提示
//     「点上方「生成 AI 解读」，三段一起出」;
//     loading / 已生成 / 重新生成 (三卡各自的 refresh) 行为不变;
//     P5 不变量保持: 三个入口的触发都走同一个 _triggerInsight → 一次调用。
//   · P2 错误态: hasError 分支若是 DioException 402 → 锁块;
//     其他错误 → 主文案「生成失败, 请稍后重试」+ 小字原始信息 + 重试按钮。
//     不再裸出「生成失败: DioException...」。
//   · P0 样本来源: facts 带 dateRange.from/to 时, footer 加一行
//     「数据范围: {from} → {to}」, 让销售知道 AI 看的是哪段历史。
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/models/ai_insight.dart';
import '../../../core/providers/ai_insight_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_events.dart' show AiCard;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';
import '../../../screens/profile_sheets.dart' show showMembershipPurchaseSheet;
import 'customer_activity_cards.dart' show showAddFollowUpSheet;

// ============================================
// 用量埋点 helper (主人 2026-09-22: 用真实数据回答「AI 卡片到底有没有人点」)
// ============================================

/// 埋点一律**不能阻断业务** (2026-09-23 P5 测出来):
///   原先 `_trackAiClick` 直接 `ref.read(usageServiceProvider)`,
///   usageServiceProvider 依赖 sharedPreferencesProvider —— 一旦它没就绪 (测试环境 /
///   插件异常) 就抛错, 而调用处是「先埋点再 generate, 中间无 try」→
///   **用户点了生成但一次请求都没发** (排查半天)。
///   埋点是辅助, 永远不该让主流程静默失败。
void _trackAiClick(WidgetRef ref, String card, {bool regenerate = false}) {
  try {
    ref.read(usageServiceProvider).track(
          regenerate ? 'ai_regenerate' : 'ai_generate_click',
          props: {'card': card},
        );
  } catch (_) {
    // 埋点失败静默忽略
  }
}

void _trackAiResult(
  WidgetRef ref,
  String card, {
  required bool ok,
  required int ms,
}) {
  try {
    ref.read(usageServiceProvider).track(
          'ai_generate_result',
          props: {'card': card},
          success: ok,
          durationMs: ms,
          errorCode: ok ? null : 'generate_failed',
        );
  } catch (_) {
    // 埋点失败静默忽略
  }
}

// ============================================
// AI 客户画像 (无独立入口: 数据由 AiFollowUpCard 的「生成 AI 解读」一次产出)
// ============================================

// ============================================
// P5: 三张 AI 卡 (画像 / 话术 / 效果) 共用**一次**调用
//
// 主人 2026-09-23 拍「AI 4 卡合并成 1 次调用」。
//   · 三张卡不再是 3 个 StatefulWidget 各持一份 state, 而是 watch 同一个
//     `aiInsightProvider(customerId)` —— 任意一张卡的「生成」都会让三张卡同时出内容。
//   · 卡片仍是三张 (场景不同: 早上看画像了解人 / 打电话看话术 / 复盘看效果),
//     合的是**调用**, 不是界面。
//   · 「复购预测」已并入 customer_rhythm_card.dart (P1)。
//
// ⚠ 谁都不许在这里直接调 aiService.insight —— 必须走 notifier,
//   否则又退回"每张卡各打一次" (P5 白做)。
//
// 2026-09-25 P2: 只有 AiFollowUpCard 出「生成 AI 解读」入口; 画像/效果
//   在没有数据时改为提示「点上方「生成 AI 解读」, 三段一起出」。
//   已生成的卡片**仍**有自己的 refresh 按钮 (重新生成, 走 _triggerInsight)。
// ============================================

class AiProfileCard extends ConsumerWidget {
  final String customerId;
  const AiProfileCard({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(customerInsightProvider(customerId)).valueOrNull;
    final isMember = insight?.scriptAvailable ?? true;

    return _AiSectionCard(
      customerId: customerId,
      icon: Icons.auto_awesome,
      iconColor: AppTheme.franchisee,
      title: 'AI 客户画像',
      subtitle: '把健康标签 + 历史记录读一遍, 总结这位客户是谁',
      emptyLabel: '生成客户画像',
      emptyIcon: Icons.auto_awesome,
      loadingLabel: 'AI 正在总结客户画像...',
      section: (r) => r.sections.profile,
      isMember: isMember,
    );
  }
}

class AiFollowUpCard extends ConsumerWidget {
  final String customerId;
  const AiFollowUpCard({super.key, required this.customerId});

  static const _reasonOptions = ['好久没来了', '想约她到店', '生日/节日问候', '该复购了'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(customerInsightProvider(customerId)).valueOrNull;
    final isMember = insight?.scriptAvailable ?? true;

    final notifier = ref.read(aiInsightProvider(customerId).notifier);
    final async = ref.watch(aiInsightProvider(customerId));
    final data = async.valueOrNull;

    return _AiCardShell(
      icon: Icons.chat_bubble_outline,
      iconColor: AppTheme.accent,
      title: 'AI 跟进建议',
      subtitle: '按她的情况写一段可以直接发的开口话术',
      trailing: data == null
          ? null
          : IconButton(
              icon: const Icon(Icons.refresh, size: AppSize.iconMd),
              tooltip: '重新生成',
              onPressed: async.isLoading
                  ? null
                  : () => _triggerInsight(ref, customerId, regenerate: true),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 跟进原因 (可选): 选了话术更贴场景
          //
          // 理由存在 notifier 上 (不是本卡 local state) —— 三张卡共用一次调用,
          // 理由必须统一, 否则"在跟进卡选了理由, 去点画像卡的重新生成"会丢掉理由。
          //
          // 锁态时隐藏: 选了就要触发生成 → 锁态下点了会白出锁块, 体验差。
          if (isMember)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _reasonOptions
                  .map((r) => ChoiceChip(
                        label: Text(r,
                            style: const TextStyle(fontSize: AppType.sm)),
                        selected: notifier.reason == r,
                        onSelected: (v) => _triggerInsight(
                          ref,
                          customerId,
                          reason: v ? r : null,
                        ),
                      ))
                  .toList(),
            ),
          if (isMember) const SizedBox(height: AppSpace.s12),
          ..._buildInsightBody(
            context: context,
            ref: ref,
            customerId: customerId,
            async: async,
            pick: (r) => r.sections.followUp,
            emptyLabel: '生成跟进话术',
            emptyIcon: Icons.chat,
            loadingLabel: 'AI 正在写话术...',
            isMember: isMember,
            primaryEntry: true, // 话术卡 = 三段卡中**唯一**的生成入口
            onGenerated: (r, context, ref) => [
              // 话术段独有: 一键复制 + 建任务 (闭环, CHARTER §1.4)
              Row(
                children: [
                  Expanded(
                    child: BigActionButton(
                      icon: Icons.copy_all,
                      label: '复制话术',
                      compact: true,
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: r.sections.followUp));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('话术已复制')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpace.s8),
                  Expanded(
                    child: BigActionButton(
                      icon: Icons.add_task,
                      label: '建跟进任务',
                      compact: true,
                      onTap: () => showAddFollowUpSheet(context, ref,
                          customerId: customerId,
                          aiSuggestion: r.sections.followUp),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class EffectAnalysisCard extends ConsumerWidget {
  final String customerId;
  const EffectAnalysisCard({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(customerInsightProvider(customerId)).valueOrNull;
    final isMember = insight?.scriptAvailable ?? true;

    return _AiSectionCard(
      customerId: customerId,
      icon: Icons.trending_up,
      iconColor: AppTheme.primaryDark,
      title: 'AI 效果分析',
      subtitle: '几疗程下来到底有没有用, 趋势 + 建议',
      emptyLabel: '生成效果分析',
      emptyIcon: Icons.insights,
      loadingLabel: 'AI 正在分析效果...',
      section: (r) => r.sections.effect,
      isMember: isMember,
    );
  }
}

// ============================================
// P5 共用部件: 「生成」入口 + 事实底稿 + 通用卡壳
// ============================================

/// 唯一的 AI 触发入口
///
/// 三张卡的按钮/芯片都走这里 —— 保证「一次生成 = 一次调用」。
/// 埋点也在这里: 一次生成只报一条 `ai_generate_click` (card=insight),
/// 不再像 P5 之前那样三张卡各报各的 (看板会把一次行为算成三次)。
void _triggerInsight(
  WidgetRef ref,
  String customerId, {
  String? reason,
  bool regenerate = false,
}) {
  _trackAiClick(ref, AiCard.insight, regenerate: regenerate);
  final sw = Stopwatch()..start();
  ref
      .read(aiInsightProvider(customerId).notifier)
      .generate(reason: reason, regenerate: regenerate)
      .then((_) {
    final failed = ref.read(aiInsightProvider(customerId)).hasError;
    _trackAiResult(ref, AiCard.insight,
        ok: !failed, ms: sw.elapsedMilliseconds);
  });
}

/// 锁块 (复用): 锁态时所有 AI 卡用它替掉「生成」按钮 / 卡片空态。
///
/// 设计:
///   · 琥珀底色 (warningSurface) —— 警示而不抢主体
///   · 主文案「🔒 升级会员可看 AI 解读」
///   · 只有第一张卡 (话术卡, primaryEntry=true) 才出「升级会员」按钮:
///     销售只需要一个行动入口, 三张卡各出按钮 = 视觉噪音 + 用户选哪个
///   · 画像/效果分析卡复用同样的锁块, 但**不**出按钮
///
/// 需要 ref: 「升级会员」按钮调 showMembershipPurchaseSheet(context, ref, ...),
///   ref 来自 ConsumerWidget 的 build context。
Widget _memberLockBlockWithRef(
  BuildContext context,
  WidgetRef ref, {
  bool showCta = false,
}) {
  final t = context.tokens;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpace.s12),
    decoration: BoxDecoration(
      color: t.warningSurface,
      borderRadius: BorderRadius.circular(AppRadius.r10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🔒 升级会员可看 AI 解读',
          style: TextStyle(
            fontSize: AppType.sm,
            color: AppColors.warning,
            fontWeight: AppWeight.semibold,
          ),
        ),
        if (showCta) ...[
          const SizedBox(height: AppSpace.s10),
          BigActionButton(
            icon: Icons.workspace_premium,
            label: '升级会员',
            onTap: () => showMembershipPurchaseSheet(context, ref,
                isMember: false),
          ),
        ],
      ],
    ),
  );
}

/// 生成后统一展示的东西: 事实底稿 pills + 内容 + mock 标记 + 样本来源
List<Widget> _insightFooter(
  BuildContext context,
  WidgetRef ref,
  AiInsightResult r,
) {
  final f = r.facts;
  final pills = <String>[
    if (f.totalVisits > 0) '累计 ${f.totalVisits} 次',
    if (f.daysSinceLastVisit != null) '距上次 ${f.daysSinceLastVisit} 天',
    if (f.avgIntervalDays != null) '平均 ${f.avgIntervalDays} 天一次',
    if (f.trend != 'unknown') '趋势 ${f.trendLabel}',
  ];

  return [
    if (pills.isNotEmpty) ...[
      const SizedBox(height: AppSpace.s10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: pills.map((t) => _InsightPill(text: t)).toList(),
      ),
    ],
    // 模型没按分隔符输出: 全文都挤在「画像」里, 提示一句免得用户以为其他卡坏了
    if (!r.sectionsParsed) ...[
      const SizedBox(height: AppSpace.s8),
      const Text(
        '提示: 这次 AI 没按分段格式回复, 完整内容已放在「客户画像」卡里',
        style: TextStyle(fontSize: AppType.xs, color: AppColors.textSecondary),
      ),
    ],
    if (r.aiMock) ...[
      const SizedBox(height: AppSpace.s8),
      const _AiMockBadge(),
    ],
    // 样本来源 (P0): facts.dateRange.from/to 都非空才显示
    //   让销售知道 AI 看的是哪段历史 (例: "近 90 天" → "2026-06-25 → 2026-09-25")。
    //   字号 micro (11) + textTertiary —— 是不重要的辅助信息, 但能消除
    //   「AI 是不是用了最近的数据」这种怀疑。
    if (f.dateFrom != null && f.dateTo != null) ...[
      const SizedBox(height: AppSpace.s6),
      Text(
        '数据范围: ${f.dateFrom} → ${f.dateTo}',
        style: const TextStyle(
          fontSize: AppType.micro,
          color: AppColors.textTertiary,
        ),
      ),
    ],
  ];
}

/// 生成后统一拼 body 段落 (loading / error / 未生成 / 已生成)
///
/// 锁态 (isMember=false) 时:
///   · primaryEntry=true (话术卡) → 锁块 + 「升级会员」按钮 + 一行小字「一次生成: ...」
///   · primaryEntry=false (画像/效果) → 锁块 (无按钮) ——
///     「点上方「生成 AI 解读」」的提示挂在锁块正上方
List<Widget> _buildInsightBody({
  required BuildContext context,
  required WidgetRef ref,
  required String customerId,
  required AsyncValue<AiInsightResult?> async,
  required String Function(AiInsightResult) pick,
  required String emptyLabel,
  required IconData emptyIcon,
  required String loadingLabel,
  required bool isMember,
  bool primaryEntry = false,
  List<Widget> Function(AiInsightResult r, BuildContext context, WidgetRef ref)?
      onGenerated,
}) {
  // 锁态: 已生成的内容不受影响 (老客户付款后还能看到历史洞察); 仅未生成时显示锁块
  if (!isMember && async.valueOrNull == null) {
    return [
      if (primaryEntry) ...[
        const Text(
          'AI 画像 / 跟进话术 / 效果分析 · 一次生成',
          style: TextStyle(
            fontSize: AppType.xs,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpace.s10),
      ] else ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpace.s8),
          child: Text(
            '点上方「生成 AI 解读」, 三段一起出',
            style: TextStyle(
              fontSize: AppType.xs,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
      _memberLockBlockWithRef(context, ref, showCta: primaryEntry),
    ];
  }

  final data = async.valueOrNull;

  if (async.isLoading) return [const _AiLoadingInline()];
  if (async.hasError) {
    // 错误分支:
    //   402 = 会员权限, 落到锁块 (同 P0 锁态, 用户体验一致);
    //   其他 = 主文案 + 小字原始信息 + 重试 (不裸出 DioException)
    if (_isPaymentRequired(async.error)) {
      return [
        _memberLockBlockWithRef(context, ref, showCta: primaryEntry),
      ];
    }
    return [
      _AiError(
        message: '生成失败, 请稍后重试',
        detail: '${async.error}',
        onRetry: () => _triggerInsight(ref, customerId),
      ),
    ];
  }
  if (data == null) {
    // 已生成的分支走这里: data == null + !isMember 已被前置拦截;
    // 这里只可能是 !isMember 的非空 async / 正常未生成 / 已生成
    if (primaryEntry) {
      return [
        _GenerateButton(
          label: '生成 AI 解读',
          icon: emptyIcon,
          onTap: () => _triggerInsight(ref, customerId),
        ),
      ];
    }
    return [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.s8),
        child: Text(
          '点上方「生成 AI 解读」, 三段一起出',
          style: TextStyle(
            fontSize: AppType.xs,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    ];
  }

  final text = pick(data).trim();
  return [
    if (text.isEmpty)
      const Text(
        '这次没有生成这一段, 可以点右上角重新生成',
        style: TextStyle(fontSize: AppType.sm, color: AppColors.textSecondary),
      )
    else
      _AiBody(text: text),
    ..._insightFooter(context, ref, data),
    if (onGenerated != null) ...[
      const SizedBox(height: AppSpace.s12),
      ...onGenerated(data, context, ref),
    ],
  ];
}

/// 错误是不是 402 (Payment Required, 后端用会员门槛)
///
/// 用 try-match 不抛: 任何类型 / null 都当 false 处理, 不让错误分类炸主流程。
bool _isPaymentRequired(Object? error) {
  if (error is DioException) {
    return error.response?.statusCode == 402;
  }
  return false;
}

/// 只有一段内容的卡 (画像 / 效果分析) 的统一壳
class _AiSectionCard extends ConsumerWidget {
  final String customerId;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String emptyLabel;
  final IconData emptyIcon;
  final String loadingLabel;
  final String Function(AiInsightResult) section;
  final bool isMember;

  const _AiSectionCard({
    required this.customerId,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.emptyLabel,
    required this.emptyIcon,
    required this.loadingLabel,
    required this.section,
    required this.isMember,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aiInsightProvider(customerId));
    final data = async.valueOrNull;

    return _AiCardShell(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      trailing: data == null
          ? null
          : IconButton(
              icon: const Icon(Icons.refresh, size: AppSize.iconMd),
              tooltip: '重新生成',
              onPressed: async.isLoading
                  ? null
                  : () => _triggerInsight(ref, customerId, regenerate: true),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildInsightBody(
          context: context,
          ref: ref,
          customerId: customerId,
          async: async,
          pick: section,
          emptyLabel: emptyLabel,
          emptyIcon: emptyIcon,
          loadingLabel: loadingLabel,
          isMember: isMember,
          primaryEntry: false, // 画像/效果卡不是入口; 让位给话术卡
        ),
      ),
    );
  }
}

class _InsightPill extends StatelessWidget {
  final String text;
  const _InsightPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s10, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: t.surfaceSubtle,
        border: Border.all(color: t.borderStrong),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: AppType.micro,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// 内联 loading (不带整卡骨架, 免得三张卡同时闪)
class _AiLoadingInline extends StatelessWidget {
  const _AiLoadingInline();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpace.s12),
      child: Row(
        children: [
          SizedBox(
            width: AppSize.iconMd,
            height: AppSize.iconMd,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpace.s10),
          Text(
            'AI 正在生成 (画像 + 话术 + 效果 一起)...',
            style: TextStyle(
              fontSize: AppType.sm,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCardShell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _AiCardShell({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return B2NoChrome(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppSize.iconLg, color: iconColor),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: AppType.md,
                      fontWeight: AppWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: AppType.micro,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AiError extends StatelessWidget {
  final String message;
  final String detail;
  final VoidCallback onRetry;
  const _AiError({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: const TextStyle(
            fontSize: AppType.sm,
            color: AppColors.danger,
          ),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s4),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppType.micro,
              color: AppColors.textTertiary,
            ),
          ),
        ],
        const SizedBox(height: AppSpace.s8),
        BigActionButton(
          icon: Icons.refresh,
          label: '重试',
          compact: true,
          onTap: onRetry,
        ),
      ],
    );
  }
}

class _AiBody extends StatelessWidget {
  final String text;
  const _AiBody({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.divider),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontSize: AppType.sm,
          height: 1.6,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _AiMockBadge extends StatelessWidget {
  const _AiMockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.r6),
      ),
      child: const Text(
        '示例数据 (AI 未接入时)',
        style: TextStyle(
          fontSize: AppType.micro,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _GenerateButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BigActionButton(icon: icon, label: label, onTap: onTap);
  }
}

/// 详情页大按钮 (64pt 高, 中老年好点)
class BigActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const BigActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 48 : 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: compact ? 20 : 24),
        label: Text(
          label,
          style: TextStyle(fontSize: compact ? AppType.sm : AppType.md),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryDark,
          side: const BorderSide(color: AppTheme.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
        ),
      ),
    );
  }
}