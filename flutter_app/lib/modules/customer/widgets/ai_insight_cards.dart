// ============================================
// 客户详情页 — AI 智能卡片 (主人 2026-09-18 拍: 详情页要"养生记录 + AI 画像 +
// AI 跟进建议 + 复购预测 + 效果分析 或更多")
//
// 设计原则:
//   1. **省钱**: 复购预测是纯 DB 计算 → 自动加载; 其余 3 个烧 MiniMax 额度 → 点了才生成
//      (按钮文案写清「点一下生成」, 生成后缓存, 可重新生成)
//   2. **中老年友好**: 字号 16+ / 大按钮 / 结果用大白话 + 一眼能看到的关键数字
//   3. **失败可恢复**: 生成失败给明确文案 + 重试按钮 (不静默吞错)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/models/ai_insight.dart';
import '../../../core/providers/ai_insight_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_events.dart' show AiCard;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_activity_cards.dart' show showAddFollowUpSheet;

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';
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
// 复购预测 (自动加载, 不烧 AI)
// ============================================

class RepurchaseCard extends ConsumerStatefulWidget {
  final String customerId;
  const RepurchaseCard({super.key, required this.customerId});

  @override
  ConsumerState<RepurchaseCard> createState() => _RepurchaseCardState();
}

class _RepurchaseCardState extends ConsumerState<RepurchaseCard> {
  RepurchasePrediction? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool manual = false}) async {
    if (manual) _trackAiClick(ref, AiCard.repurchase);
    final sw = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(aiServiceProvider)
          .repurchasePrediction(widget.customerId);
      if (mounted) setState(() => _data = d);
      if (manual) {
        _trackAiResult(ref, AiCard.repurchase,
            ok: true, ms: sw.elapsedMilliseconds);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      if (manual) {
        _trackAiResult(ref, AiCard.repurchase,
            ok: false, ms: sw.elapsedMilliseconds);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AiCardShell(
      icon: Icons.autorenew,
      iconColor: AppTheme.primary,
      title: '复购预测',
      subtitle: '根据历史到店间隔算下次该什么时候约',
      trailing: IconButton(
        icon: const Icon(Icons.refresh, size: AppSize.iconMd),
        tooltip: '重新计算',
        onPressed: _loading ? null : () => _load(manual: true),
      ),
      child: _loading
          ? const _AiLoading('正在算复购周期...')
          : _error != null
              ? _AiError(message: _error!, onRetry: () => _load(manual: true))
              : _data == null
                  ? const _AiHint('暂无数据')
                  : _buildResult(_data!),
    );
  }

  Widget _buildResult(RepurchasePrediction d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric('距上次到店',
                d.daysSinceLastVisit == null ? '—' : '${d.daysSinceLastVisit} 天'),
            _metric('平均复购周期',
                d.avgIntervalDays == null ? '—' : '${d.avgIntervalDays} 天'),
            _metric('预计下次', d.predictedNextVisit ?? '—',
                highlight: d.isDue),
          ],
        ),
        const SizedBox(height: AppSpace.s10),
        Row(
          children: [
            _confidenceChip(d.confidence),
            const SizedBox(width: AppSpace.s8),
            if (d.daysUntilPredicted != null)
              Text(
                d.daysUntilPredicted! < 0
                    ? '已过 ${-d.daysUntilPredicted!} 天'
                    : '还有 ${d.daysUntilPredicted} 天',
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  fontWeight: FontWeight.w600,
                  color: d.isDue ? AppTheme.danger : AppTheme.textSecondary,
                ),
              ),
          ],
        ),
        if (d.reason.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          _AiBody(text: d.reason),
        ],
        if (d.isDue) ...[
          const SizedBox(height: AppSpace.s12),
          BigActionButton(
            icon: Icons.add_task,
            label: '建一条跟进任务',
            onTap: () => showAddFollowUpSheet(context, ref,
                customerId: widget.customerId),
          ),
        ],
      ],
    );
  }

  Widget _metric(String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s8),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.danger.withOpacity(0.08)
            : AppTheme.primaryLight.withOpacity(0.35),
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
          const SizedBox(height: AppSpace.s2),
          Text(value,
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w700,
                color: highlight ? AppTheme.danger : AppTheme.primaryDark,
              )),
        ],
      ),
    );
  }

  Widget _confidenceChip(String c) {
    final (label, color) = switch (c) {
      'high' => ('数据充分', AppTheme.primary),
      'medium' => ('数据一般', AppTheme.accent),
      _ => ('数据较少', AppTheme.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: AppTheme.fontXs, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ============================================
// AI 客户画像 (点一下生成)
// ============================================

// ============================================
// P5: 三张 AI 卡 (画像 / 话术 / 效果) 共用**一次**调用
//
// 主人 2026-09-23 拍「AI 4 卡合并成 1 次调用」。
//   · 三张卡不再是 3 个 StatefulWidget 各持一份 state, 而是 watch 同一个
//     `aiInsightProvider(customerId)` —— 任意一张卡的「生成」都会让三张卡同时出内容。
//   · 卡片仍是三张 (场景不同: 早上看画像了解人 / 打电话看话术 / 复盘看效果),
//     合的是**调用**, 不是界面。
//   · 「复购预测」保持独立 (纯 DB 计算, 自动加载, 不烧 AI)。
//
// ⚠ 谁都不许在这里直接调 aiService.insight —— 必须走 notifier,
//   否则又退回"每张卡各打一次" (P5 白做)。
// ============================================

class AiProfileCard extends ConsumerWidget {
  final String customerId;
  const AiProfileCard({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    );
  }
}

class AiFollowUpCard extends ConsumerWidget {
  final String customerId;
  const AiFollowUpCard({super.key, required this.customerId});

  static const _reasonOptions = ['好久没来了', '想约她到店', '生日/节日问候', '该复购了'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _reasonOptions
                .map((r) => ChoiceChip(
                      label: Text(r,
                          style: const TextStyle(fontSize: AppTheme.fontSm)),
                      selected: notifier.reason == r,
                      onSelected: (v) => _triggerInsight(
                        ref,
                        customerId,
                        reason: v ? r : null,
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpace.s12),
          ..._buildInsightBody(
            context: context,
            ref: ref,
            customerId: customerId,
            async: async,
            pick: (r) => r.sections.followUp,
            emptyLabel: '生成跟进话术',
            emptyIcon: Icons.chat,
            loadingLabel: 'AI 正在写话术...',
            onGenerated: (r, context) => [
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

/// 生成后统一展示的东西: 事实底稿 pills + 内容 + mock 标记
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
        style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
      ),
    ],
    if (r.aiMock) ...[
      const SizedBox(height: AppSpace.s8),
      const _AiMockBadge(),
    ],
  ];
}

/// 生成后统一拼 body 段落 (loading / error / 未生成 / 已生成)
List<Widget> _buildInsightBody({
  required BuildContext context,
  required WidgetRef ref,
  required String customerId,
  required AsyncValue<AiInsightResult?> async,
  required String Function(AiInsightResult) pick,
  required String emptyLabel,
  required IconData emptyIcon,
  required String loadingLabel,
  List<Widget> Function(AiInsightResult r, BuildContext context)? onGenerated,
}) {
  final data = async.valueOrNull;

  if (async.isLoading) return [const _AiLoadingInline()];
  if (async.hasError) {
    return [
      _AiError(
        message: '${async.error}',
        onRetry: () => _triggerInsight(ref, customerId),
      ),
    ];
  }
  if (data == null) {
    return [
      _GenerateButton(
        label: emptyLabel,
        icon: emptyIcon,
        onTap: () => _triggerInsight(ref, customerId),
      ),
    ];
  }

  final text = pick(data).trim();
  return [
    if (text.isEmpty)
      const Text(
        '这次没有生成这一段, 可以点右上角重新生成',
        style: TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
      )
    else
      _AiBody(text: text),
    ..._insightFooter(context, ref, data),
    if (onGenerated != null) ...[
      const SizedBox(height: AppSpace.s12),
      ...onGenerated(data, context),
    ],
  ];
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
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s10, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: AppTheme.bgWarm,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
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
          Text('AI 正在生成 (画像 + 话术 + 效果 一起)...',
              style: TextStyle(
                  fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
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
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
            const SizedBox(height: AppSpace.s12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AiLoading extends StatelessWidget {
  final String label;
  const _AiLoading(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: AppSpace.s20,
          height: AppSpace.s20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: AppSpace.s12),
        Text(label,
            style: const TextStyle(
                fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _AiError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _AiError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('生成失败: $message',
            style: const TextStyle(
                fontSize: AppTheme.fontSm, color: AppTheme.danger)),
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

class _AiHint extends StatelessWidget {
  final String text;
  const _AiHint(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: AppTheme.fontSm, color: AppTheme.textSecondary));
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
        color: AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.divider),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontSize: AppTheme.fontSm,
          height: 1.6,
          color: AppTheme.textPrimary,
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
      child: const Text('示例数据 (AI 未接入时)',
          style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
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
        label: Text(label, style: TextStyle(fontSize: compact ? AppTheme.fontSm : AppTheme.fontMd)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryDark,
          side: const BorderSide(color: AppTheme.primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r12)),
        ),
      ),
    );
  }
}
