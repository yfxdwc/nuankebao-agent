// ============================================
// 客户详情页 — 「跟进节奏」卡 (2026-09-25 新)
// ============================================
// 把旧的「FollowUpAnalysisCard」+「RepurchaseCard」合并成一张卡:
//   · 跟进分析 (后端 GET /customers/:id/follow-up-analysis; 客观指标免费)
//   · 复购预测 (后端 GET /ai/repurchase-prediction/:id; 纯 DB 自动加载)
//
// 两段**独立**加载 + 独立错误态 (一个挂了另一个照常显示) —— 「静默降级」精神
// (老 RepurchaseCard 任何阶段报错, 都吃掉整张卡; 现在分两段, 跟进段正常 ≠ 复购段崩)。
//
// 手动刷新 (右上角 IconButton) 保留两个埋点 (复购预测的事件名/props 跟旧 RepurchaseCard
// 一致 → 历史看板不会断): 复购用 _trackRepurchaseClick(), 跟进不发卡埋点
// (旧卡也没发, 只用 dio 单次请求计数)。
//
// 外壳: B2NoChrome + Padding(cardPadding), 无边框; 卡片间距由详情页用
// SizedBox(cardGap) 控制 (B0b 不在内部塞 margin)。
//
// 会员提示: FollowUpAnalysis.aiTipAvailable == false 时, 卡底出琥珀块提示
// 「🔒 升级会员可看 AI 解读」 (跟旧 FollowUpAnalysisCard 同口径)。
//
// ⚠ 所有 TextStyle 都显式给 color (AGENTS §5: 主题里只写字号不写 color →
//   真机白字 bug 防线)。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/ai_insight.dart';
import '../../../core/models/follow_up_info.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_events.dart' show AiCard;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';
import '../../customer/widgets/customer_activity_cards.dart' show showAddFollowUpSheet;
import '../../customer/widgets/ai_insight_cards.dart' show BigActionButton;

/// 「跟进节奏」卡 —— 跟进分析 (免费) + 复购预测 (自动加载) 合并卡
class CustomerRhythmCard extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerRhythmCard({super.key, required this.customerId});

  @override
  ConsumerState<CustomerRhythmCard> createState() => _CustomerRhythmCardState();
}

class _CustomerRhythmCardState extends ConsumerState<CustomerRhythmCard> {
  FollowUpAnalysis? _followUp;
  bool _followUpLoading = true;
  String? _followUpError;

  RepurchasePrediction? _repurchase;
  bool _repurchaseLoading = true;
  String? _repurchaseError;

  @override
  void initState() {
    super.initState();
    // 两个源并发自动加载; 任一抛错另一段照常显示
    _loadBoth();
  }

  Future<void> _loadBoth({bool manual = false}) async {
    if (manual) {
      // 复购预测: 保留旧 RepurchaseCard 埋点 (事件名 + props 一致 → 历史看板不断)
      _trackRepurchaseClick();
    }
    await Future.wait([
      _loadFollowUp(manual: manual),
      _loadRepurchase(manual: manual),
    ]);
  }

  Future<void> _loadFollowUp({bool manual = false}) async {
    _setStateSafe(() {
      _followUpLoading = true;
      _followUpError = null;
    });
    try {
      final d = await ref
          .read(customerServiceProvider)
          .followUpAnalysis(widget.customerId);
      if (mounted) _setStateSafe(() => _followUp = d);
    } catch (e) {
      if (mounted) _setStateSafe(() => _followUpError = '$e');
    } finally {
      if (mounted) _setStateSafe(() => _followUpLoading = false);
    }
  }

  Future<void> _loadRepurchase({bool manual = false}) async {
    _setStateSafe(() {
      _repurchaseLoading = true;
      _repurchaseError = null;
    });
    try {
      final d = await ref
          .read(aiServiceProvider)
          .repurchasePrediction(widget.customerId);
      if (mounted) _setStateSafe(() => _repurchase = d);
    } catch (e) {
      if (mounted) _setStateSafe(() => _repurchaseError = '$e');
    } finally {
      if (mounted) _setStateSafe(() => _repurchaseLoading = false);
    }
  }

  /// 复购预测埋点: 抄原 RepurchaseCard 的实现 (事件名 + props 与看板历史一致)。
  void _trackRepurchaseClick() {
    try {
      ref.read(usageServiceProvider).track(
            'ai_generate_click',
            props: {'card': AiCard.repurchase},
          );
    } catch (_) {
      // 埋点失败静默忽略 (同 ai_insight_cards 的 _trackAiClick)
    }
  }

  void _setStateSafe(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final anyLoading = _followUpLoading || _repurchaseLoading;

    return B2NoChrome(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 头部 ──
            Row(
              children: [
                Icon(Icons.insights, size: AppSize.iconMd, color: t.primary),
                const SizedBox(width: AppSpace.s8),
                const Expanded(
                  child: Text(
                    '跟进节奏',
                    style: TextStyle(
                      fontSize: AppType.md,
                      fontWeight: AppWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: AppSize.iconMd),
                  tooltip: '重新计算',
                  onPressed: anyLoading ? null : () => _loadBoth(manual: true),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            const Text(
              '客观记录: 联系频次 / 到店节奏 / 复购预测',
              style: TextStyle(
                fontSize: AppType.micro,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.s12),

            // ── 跟进分析段 ──
            _buildFollowUpSection(),
            const SizedBox(height: AppSpace.s14),

            // ── 分隔 ──
            Container(
              height: AppSize.borderHairline,
              color: t.divider,
            ),
            const SizedBox(height: AppSpace.s14),

            // ── 复购预测段 ──
            _buildRepurchaseSection(),

            // ── 卡底: 会员提示 (跟旧 FollowUpAnalysisCard 同口径) ──
            if (_followUp != null && !_followUp!.aiTipAvailable) ...[
              const SizedBox(height: AppSpace.s12),
              const _MemberLockHint(),
            ],
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // 跟进分析段 (免费层)
  // ────────────────────────────────────────────────────────────
  Widget _buildFollowUpSection() {
    if (_followUpLoading) {
      return _loadingRow('正在算跟进情况...');
    }
    if (_followUpError != null) {
      // ⚠ 不要把 DioException 原文丢给销售: 人话 + 重试按钮
      return _errorRow(
        label: '跟进数据没加载出来',
        onRetry: () => _loadFollowUp(manual: false),
      );
    }
    return _FollowUpBody(data: _followUp!);
  }

  // ────────────────────────────────────────────────────────────
  // 复购预测段 (纯 DB, 自动加载)
  // ────────────────────────────────────────────────────────────
  Widget _buildRepurchaseSection() {
    if (_repurchaseLoading) {
      // 小字 inline loading (整张卡已加载好, 这里只是等这一段的数据)
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.s8),
        child: Text(
          '正在算复购预测...',
          style: TextStyle(
            fontSize: AppType.xs,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }
    if (_repurchaseError != null) {
      // 不拦整卡; 给一句人话 + 提示点右上刷新
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.s8),
        child: Text(
          '复购预测暂时算不出来 (点右上角可重试)',
          style: TextStyle(
            fontSize: AppType.xs,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }
    return _RepurchaseBody(data: _repurchase!);
  }

  // ────────────────────────────────────────────────────────────
  // 复用小部件
  // ────────────────────────────────────────────────────────────
  Widget _loadingRow(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      child: Row(
        children: [
          const SizedBox(
            width: AppSpace.s20,
            height: AppSpace.s20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: AppSpace.s10),
          Text(
            label,
            style: const TextStyle(
              fontSize: AppType.sm,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorRow({required String label, required VoidCallback onRetry}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: AppType.xs,
            color: AppColors.danger,
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

// ============================================
// 跟进分析段: headline + 趋势 + 6 指标
// ============================================

class _FollowUpBody extends StatelessWidget {
  const _FollowUpBody({required this.data});
  final FollowUpAnalysis data;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final trendColor = data.isColder
        ? t.danger
        : data.isWarmer
            ? t.primary
            : t.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 一句话总结 (免费层)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpace.s8),
          decoration: BoxDecoration(
            color: t.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.r10),
          ),
          child: Text(
            data.headline,
            style: const TextStyle(
              fontSize: AppType.sm,
              fontWeight: AppWeight.semibold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s8),

        // 趋势 (颜色 + 图标 + 文字三编码)
        if (data.trend != 'unknown')
          Row(
            children: [
              Icon(
                data.isColder
                    ? Icons.trending_down
                    : data.isWarmer
                        ? Icons.trending_up
                        : Icons.trending_flat,
                size: AppSize.iconMd,
                color: trendColor,
              ),
              const SizedBox(width: AppSpace.s6),
              Text(
                data.trendText,
                style: TextStyle(
                  fontSize: AppType.sm,
                  fontWeight: AppWeight.semibold,
                  color: trendColor,
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpace.s8),

        // 6 个指标 (去重: 不再单独列「距上次到店」「平均复购周期」 ——
        //   已经在下方复购段里有「上次到店 / 复购间隔」,
        //   同口径重复两次 = 视觉噪音)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(
              label: '近 30 天联系',
              value: '${data.contactLast30} 次',
              sub: '近 90 天 ${data.contactLast90} 次',
            ),
            _Metric(
              label: '联系间隔',
              value: data.avgContactIntervalDays == null
                  ? '—'
                  : '${data.avgContactIntervalDays} 天',
              sub: data.avgContactIntervalDays == null ? '联系还太少' : '平均一次',
            ),
            _Metric(
              label: '到店次数',
              value: '${data.visitCount} 次',
              sub: data.avgVisitIntervalDays == null
                  ? '暂无规律'
                  : '每 ${data.avgVisitIntervalDays} 天一次',
            ),
            _Metric(
              label: '复购间隔',
              value: data.medianRepurchaseIntervalDays == null
                  ? '—'
                  : '${data.medianRepurchaseIntervalDays} 天',
              sub: '历史中位数',
            ),
            _Metric(
              label: '上次到店',
              value: data.daysSinceLastVisit == null
                  ? '—'
                  : '${data.daysSinceLastVisit} 天前',
              sub: data.lastVisitAt == null
                  ? '还没到过店'
                  : DateFormat('yyyy-MM-dd').format(data.lastVisitAt!.toLocal()),
            ),
            _Metric(
              label: '待办跟进',
              value: '${data.pendingTasks} 条',
              sub: data.overdueTasks > 0
                  ? '逾期 ${data.overdueTasks} 条'
                  : '没有逾期',
              danger: data.overdueTasks > 0,
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================
// 复购预测段: 预计下次 + 置信度 + reason + 大动作按钮 (isDue)
// ============================================
// 用 ConsumerWidget —— showAddFollowUpSheet 要 (ctx, ref), ref 在 StatelessWidget
// 里拿不到 (需要 ConsumerWidget.build 的 ref 参数).
class _RepurchaseBody extends ConsumerWidget {
  const _RepurchaseBody({required this.data});
  final RepurchasePrediction data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final customerId = (context.findAncestorWidgetOfExactType<CustomerRhythmCard>()
            ?.customerId) ??
        '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 预计下次 (高亮: 该催了)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.s12,
                vertical: AppSpace.s8,
              ),
              decoration: BoxDecoration(
                color: data.isDue
                    ? t.danger.withOpacity(0.08)
                    : t.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppRadius.r10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '预计下次',
                    style: TextStyle(
                      fontSize: AppType.micro,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.s2),
                  Text(
                    data.predictedNextVisit ?? '—',
                    style: TextStyle(
                      fontSize: AppType.md,
                      fontWeight: AppWeight.bold,
                      color: data.isDue ? t.danger : t.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s10),

        // 「还有 N 天 / 已过 N 天」 + 置信度 chip
        Row(
          children: [
            if (data.daysUntilPredicted != null)
              Text(
                data.daysUntilPredicted! < 0
                    ? '已过 ${-data.daysUntilPredicted!} 天'
                    : '还有 ${data.daysUntilPredicted} 天',
                style: TextStyle(
                  fontSize: AppType.sm,
                  fontWeight: AppWeight.semibold,
                  color: data.isDue ? t.danger : t.textSecondary,
                ),
              ),
            const SizedBox(width: AppSpace.s8),
            _ConfidenceChip(confidence: data.confidence),
          ],
        ),

        // reason 小字
        if (data.reason.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpace.s10),
            decoration: BoxDecoration(
              color: t.surfaceSubtle,
              borderRadius: BorderRadius.circular(AppRadius.r8),
            ),
            child: Text(
              data.reason,
              style: const TextStyle(
                fontSize: AppType.xs,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],

        // 该催了 → 建任务 (大动作按钮)
        if (data.isDue) ...[
          const SizedBox(height: AppSpace.s12),
          BigActionButton(
            icon: Icons.add_task,
            label: '建一条跟进任务',
            onTap: () => showAddFollowUpSheet(
              context,
              ref,
              customerId: customerId,
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});
  final String confidence;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (label, color) = switch (confidence) {
      'high' => ('数据充分', t.primary),
      'medium' => ('数据一般', t.warning),
      _ => ('数据较少', t.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s10,
        vertical: AppSpace.s4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppType.micro,
          color: color,
          fontWeight: AppWeight.semibold,
        ),
      ),
    );
  }
}

// ============================================
// 小指标块 (label / 大字 value / 小字 sub)
// ============================================

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final bool danger;

  const _Metric({
    required this.label,
    required this.value,
    required this.sub,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: AppType.micro,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpace.s2),
          Text(
            value,
            style: TextStyle(
              fontSize: AppType.lg,
              fontWeight: AppWeight.bold,
              color: danger ? t.danger : AppColors.textPrimary,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: AppType.xs,
              color: danger ? t.danger : t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// 会员锁提示 (跟旧 FollowUpAnalysisCard 同口径, 卡底)
// ============================================

class _MemberLockHint extends StatelessWidget {
  const _MemberLockHint();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: t.warningSurface,
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: const Text(
        '🔒 升级会员可看 AI 解读 (该聊什么 / 开场话术)',
        style: TextStyle(
          fontSize: AppType.xs,
          color: AppColors.warning,
          fontWeight: AppWeight.semibold,
        ),
      ),
    );
  }
}