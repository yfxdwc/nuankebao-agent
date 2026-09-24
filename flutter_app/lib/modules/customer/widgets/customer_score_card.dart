// ============================================
// 客户评分卡 —— 分析 Tab 的顶部 (主人 2026-09-24 拍)
//
// 「评分卡」从 L0 搬到「分析」Tab 的诉求原话 (P2 收尾):
//   三个 Tab 顶部都有评分环 = 「要看分数总要滚到顶」= 反 vibe;
//   评分是"参考值", 行动才是"产出值", 应该**分析才需要看评分**。
//
// 设计依据 (docs/ui-principles.md):
//   · 原则 1「密度 = 尊重用户时间」: 评分环 + 三维条 + 展开 = 一屏内能扫完
//   · 原则 2「层级靠对比不靠放大」: 环 + 颜色 + 数字 三重编码, 不靠堆字号
//   · 原则 4「容器越少内容越强」: 单 Container (surfaceCard + divider 边框), 内部靠分隔线
//
// 为什么「行动输出」不搬过来 (这次没动的部分):
//   CHARTER §1.4 四要素最后一条「行动输出 = **明确的**跟进指引」必须**切 Tab 也可见**。
//   它放在 L0 (CustomerInsightActions, 切 Tab 可见);
//   评分卡放分析 Tab (要看分数才看), 互不抢位 —— 见 AGENTS §5「贴告示 ≠ 修复」同根,
//   不该因本次诉求把"现在该做"也顺手移走 (那是已经拍过的板)。
//
// 健壮性: 拿不到洞察数据 → 整块 SizedBox.shrink(), 不炸分析 Tab 的其他图表。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/customer_insight.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';

/// 评分卡 (评分环 + 三维度小条 + 可展开因子明细)
/// 仅出现在「分析」Tab 顶部 —— 详情页其他 Tab 不渲染
class CustomerScoreCard extends ConsumerWidget {
  const CustomerScoreCard({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerInsightProvider(customerId));

    // 静默降级: 洞察拿不到时整块隐藏, 不影响分析 Tab 的图表 / AI 区
    return async.when(
      loading: () => const _ScoreCardSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (insight) => _ScoreCardBody(score: insight.score),
    );
  }
}

// ============================================
// 主体 (评分环行 + 可展开维度明细)
// ============================================

class _ScoreCardBody extends StatefulWidget {
  const _ScoreCardBody({required this.score});
  final CustomerScore score;

  @override
  State<_ScoreCardBody> createState() => _ScoreCardBodyState();
}

class _ScoreCardBodyState extends State<_ScoreCardBody> {
  /// 评分明细是否展开 (默认收起 —— 分析 Tab 要克制, 想看细节再点)
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.score;

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
// 骨架 (加载中, 与真实内容同高, 不跳动)
// ============================================

class _ScoreCardSkeleton extends StatelessWidget {
  const _ScoreCardSkeleton();

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