// ============================================
// 客户洞察 L0 —— 评分环 + 今日待办 (详情页顶部)
// ============================================
//
// 主人 2026-09-23 拍板 P1 前端。设计依据:
//   · CHARTER §1.4 四要素最后一条「行动输出 = **明确的**跟进指引」
//     → 待办区必须在**永远可见**的位置 (L0), 不是滚到第 8 屏
//   · docs/ui-principles.md 原则 2「层级靠对比不靠放大」
//     → 评分用**环 + 颜色 + 数字**三重编码, 不靠堆字号
//   · 原则 4「容器越少内容越强」
//     → 整个 L0 只用一个浅底容器, 内部靠分隔线 + 留白
//
// 为什么评分是"确定性规则"而不是 AI:
//   销售一定会问「为什么是 78 分」→ 点开维度能看到每个因子的分与人话解释
//   (factor.detail)。AI 答不了这个, 规则引擎可以。AI 只补 action.script (会员)。
//
// ⚠ 健壮性: 详情页的其他 section 不能因为本组件出错而消失 ——
//   所以加载失败 / 无数据时**静默降级** (只显示一句提示), 不抛异常。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/customer_insight.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';

/// L0 洞察头 (评分环 + 今日待办)
class CustomerInsightHeader extends ConsumerWidget {
  const CustomerInsightHeader({
    super.key,
    required this.customerId,
    required this.onBuildTask,
  });

  final String customerId;

  /// 点「建任务」→ 由详情页写 follow_up_task (回写闭环, CHARTER §1.4)
  final Future<void> Function(ActionItem action) onBuildTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerInsightProvider(customerId));

    // 静默降级: 洞察拿不到不影响详情页其他部分
    return async.when(
      loading: () => const _InsightSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (insight) => _InsightBody(
        insight: insight,
        onBuildTask: onBuildTask,
        onRefresh: () => ref.invalidate(customerInsightProvider(customerId)),
      ),
    );
  }
}

// ============================================
// 主体
// ============================================

class _InsightBody extends StatefulWidget {
  const _InsightBody({
    required this.insight,
    required this.onBuildTask,
    required this.onRefresh,
  });

  final CustomerInsight insight;
  final Future<void> Function(ActionItem) onBuildTask;
  final VoidCallback onRefresh;

  @override
  State<_InsightBody> createState() => _InsightBodyState();
}

class _InsightBodyState extends State<_InsightBody> {
  /// 评分明细是否展开 (默认收起 —— L0 要克制, 想看细节再点)
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.insight.score;
    final todos = widget.insight.topActions;

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 第一行: 评分环 + 维度摘要 + 展开按钮 ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.cardPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ScoreRing(score: s),
                  const SizedBox(width: AppSpace.s14),
                  Expanded(child: _DimensionBars(score: s)),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: AppSize.iconMd,
                    color: t.textTertiary,
                  ),
                ],
              ),
            ),
          ),

          // ── 展开: 每个维度的因子明细 (可解释性) ──
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.cardPadding,
                AppSpace.s10,
                AppSpace.cardPadding,
                AppSpace.s14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final d in s.dimensions) _DimensionDetail(dim: d),
                ],
              ),
            ),
          ],

          // ── 待办区 (§1.4 行动输出; 永远可见) ──
          if (todos.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.cardPadding,
                AppSpace.s10,
                AppSpace.cardPadding,
                AppSpace.s12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.checklist_rtl,
                          size: AppSize.iconSm, color: t.textSecondary),
                      const SizedBox(width: AppSpace.s6),
                      Text(
                        '现在该做 (${todos.length})',
                        style: TextStyle(
                          fontSize: AppType.sm,
                          fontWeight: AppWeight.semibold,
                          color: t.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (widget.insight.actions.length > todos.length)
                        Text(
                          '共 ${widget.insight.actions.length} 条',
                          style: TextStyle(
                              fontSize: AppType.xs, color: t.textTertiary),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s8),
                  for (var i = 0; i < todos.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpace.s8),
                    _ActionRow(
                      action: todos[i],
                      onBuildTask: () => widget.onBuildTask(todos[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // ── 无待办: 明确告诉销售"没事做" (而不是一片空白) ──
          if (todos.isEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.cardPadding,
                AppSpace.s10,
                AppSpace.cardPadding,
                AppSpace.s12,
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: AppSize.iconSm, color: t.success),
                  const SizedBox(width: AppSpace.s6),
                  Text(
                    '节奏正常, 暂无该做的事',
                    style: TextStyle(fontSize: AppType.sm, color: t.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================
// 评分环
// ============================================

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score});
  final CustomerScore score;

  static const double _size = AppSize.avatarLg;

  Color _ringColor(AppTokens t, double? v) {
    if (v == null) return t.borderStrong;
    if (v >= 80) return t.success;
    if (v >= 60) return t.primary;
    if (v >= 40) return t.warning;
    return t.danger;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = score.overall;
    final color = _ringColor(t, v);

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 环 (有分才画进度, 没分画一圈灰)
          SizedBox(
            width: _size,
            height: _size,
            child: CircularProgressIndicator(
              value: v == null ? 0 : (v / 100).clamp(0, 1),
              strokeWidth: 6,
              backgroundColor: t.surfaceSunken,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                v == null ? '—' : v.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: AppType.lg,
                  fontWeight: AppWeight.bold,
                  color: color,
                  height: 1.1,
                ),
              ),
              Text(
                score.overallBandLabel,
                style: TextStyle(
                  fontSize: AppType.micro,
                  color: t.textSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================
// 三个维度小条 (收起态)
// ============================================

class _DimensionBars extends StatelessWidget {
  const _DimensionBars({required this.score});
  final CustomerScore score;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in score.dimensions) ...[
          if (d != score.dimensions.first) const SizedBox(height: AppSpace.s6),
          Row(
            children: [
              // ⚠ 用 flex 比例而不是固定像素宽:
              //   · 同一 Row 内各行的 flex 一致 → 列仍然严格对齐
              //   · 字号档位调大时列宽跟着长 (固定 62px 会被"特大"档挤爆)
              Expanded(
                flex: 4,
                child: Text(
                  d.label,
                  style: TextStyle(fontSize: AppType.xs, color: t.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 7,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.r4),
                  child: LinearProgressIndicator(
                    value: (d.score ?? 0) / 100,
                    minHeight: 6,
                    backgroundColor: t.surfaceSunken,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _barColor(t, d.score),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              Expanded(
                flex: 2,
                child: Text(
                  d.hasScore ? d.score!.toStringAsFixed(0) : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AppType.xs,
                    fontWeight: AppWeight.semibold,
                    color: _barColor(t, d.score),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Color _barColor(AppTokens t, double? v) {
    if (v == null) return t.borderStrong;
    if (v >= 80) return t.success;
    if (v >= 60) return t.primary;
    if (v >= 40) return t.warning;
    return t.danger;
  }
}

// ============================================
// 维度明细 (展开态) —— 可解释性: 每个因子带人话
// ============================================

class _DimensionDetail extends StatelessWidget {
  const _DimensionDetail({required this.dim});
  final ScoreDimension dim;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                dim.label,
                style: TextStyle(
                  fontSize: AppType.sm,
                  fontWeight: AppWeight.semibold,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              Text(
                dim.hasScore
                    ? '${dim.score!.toStringAsFixed(0)} 分 · ${dim.bandLabel}'
                    : dim.bandLabel,
                style: TextStyle(fontSize: AppType.xs, color: t.textTertiary),
              ),
            ],
          ),
          // 数据不足时说明缺什么 (而不是显示一堆 0)
          if (!dim.hasScore && dim.missingReason != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s2),
              child: Text(
                dim.missingReason!,
                style: TextStyle(
                    fontSize: AppType.xs,
                    color: t.textTertiary,
                    fontStyle: FontStyle.italic),
              ),
            ),
          for (final f in dim.factors)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // flex 比例 (理由同行上): 列对齐 + 随字号档位伸缩
                  Expanded(
                    flex: 5,
                    child: Text(
                      f.label,
                      style:
                          TextStyle(fontSize: AppType.xs, color: t.textSecondary),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${f.score.toStringAsFixed(0)}/${f.max.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: AppType.xs,
                        fontWeight: AppWeight.medium,
                        color: t.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 8,
                    child: Text(
                      f.detail,
                      style: TextStyle(fontSize: AppType.xs, color: t.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================
// 一条行动 (带"建任务"闭环)
// ============================================

class _ActionRow extends StatefulWidget {
  const _ActionRow({required this.action, required this.onBuildTask});

  final ActionItem action;
  final Future<void> Function() onBuildTask;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _busy = false;
  bool _done = false;

  Future<void> _build() async {
    if (_busy || _done) return;
    setState(() => _busy = true);
    try {
      await widget.onBuildTask();
      if (mounted) setState(() => _done = true);
    } catch (_) {
      // ⚠ 错误提示由**回调自己**负责 (它知道业务上下文, 能说清"网络"还是"重复建")。
      //   这里吞掉只是**不让异常冒泡崩掉整个详情页** —— 洞察区坏了不该拖垮其他 section。
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = widget.action;
    final dot = a.isHigh
        ? t.danger
        : a.priority == 'medium'
            ? t.accent
            : t.textTertiary;

    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: a.isHigh ? t.dangerSurface : t.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: AppSpace.s6,
                height: AppSpace.s6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
              ),
              const SizedBox(width: AppSpace.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            a.title,
                            style: TextStyle(
                              fontSize: AppType.md,
                              fontWeight: AppWeight.semibold,
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.s6),
                        Text(
                          '${a.when} · ${a.channelLabel}',
                          style:
                              TextStyle(fontSize: AppType.xs, color: t.textTertiary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s2),
                    // why 是可核对的数字, 不是"AI 觉得"
                    Text(
                      a.why,
                      style: TextStyle(fontSize: AppType.xs, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '做完预期: ${a.expected}',
                  style: TextStyle(fontSize: AppType.micro, color: t.textTertiary),
                ),
              ),
              if (_done)
                Row(
                  children: [
                    Icon(Icons.check, size: AppSize.iconSm, color: t.success),
                    const SizedBox(width: AppSpace.s2),
                    Text('已建任务',
                        style: TextStyle(fontSize: AppType.xs, color: t.success)),
                  ],
                )
              else
                TextButton(
                  onPressed: _busy ? null : _build,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppSize.controlSm),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: _busy
                      ? SizedBox(
                          width: AppSize.iconSm,
                          height: AppSize.iconSm,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('建任务'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================
// 骨架 (加载中, 与真实内容同高, 不跳动)
// ============================================

class _InsightSkeleton extends StatelessWidget {
  const _InsightSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      // 骨架高度 = 收起态的真实身高 (环 + 上下内边距)
      //   推导而不是写 92: 改 AppSize.avatarLg 或 cardPadding 时自动跟着变
      height: AppSize.avatarLg + AppSpace.cardPadding * 2,
      decoration: BoxDecoration(
        color: t.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: AppSize.iconLg,
        height: AppSize.iconLg,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
