// ============================================
// 客户分析图谱 —— 分析 Tab 的三张图 (P4)
// ============================================
//   ① 三维雷达图   健康 / 温度 / 价值        —— 数据来自 CustomerScore 维度分
//   ② 效果趋势线   pain+sleep 前→后 随时间   —— 数据来自 /charts trend
//   ③ 部位热力条   哪些部位反复出问题 + 止痛  —— 数据来自 /charts bodyParts
//
// 设计依据 (docs/ui-principles.md):
//   · 原则 2「层级靠对比不靠放大」: 图里用**颜色 + 数值标签**表达好坏, 不靠放大
//   · 原则 4「容器越少内容越强」: 一张图一个白底块, 不放边框/阴影叠加
//   · ⚠ 只画**描述性统计**: 出现次数 / 中位止痛幅度。
//     不写"这个部位该用什么方案" —— CHARTER §1.3 不做医疗诊断, 那是技师/店长的判断。
//
// 健壮性: 数据不足时明确说"需要几次记录", 不画一张误导人的空图。
// ============================================

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/customer_charts.dart';
import '../../../core/models/customer_insight.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';

/// 分析 Tab 的图谱区 (雷达 + 趋势 + 部位)
class CustomerAnalysisCharts extends ConsumerWidget {
  const CustomerAnalysisCharts({
    super.key,
    required this.customerId,
    required this.score,
  });

  final String customerId;

  /// 雷达图直接吃 L0 的评分 (不重复请求) —— 由详情页从 insight 传下来
  final CustomerScore score;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerChartsProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ① 雷达: 数据来自 score, 无需等 charts
        _RadarCard(score: score),
        const SizedBox(height: AppSpace.cardGap),
        // ②③ 需要 charts
        async.when(
          loading: () => const _ChartsSkeleton(),
          error: (_, __) => const SizedBox.shrink(), // 静默降级, 不拖垮分析 Tab
          data: (c) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TrendCard(charts: c),
              const SizedBox(height: AppSpace.cardGap),
              _BodyPartCard(charts: c),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================
// ① 三维雷达图
// ============================================

class _RadarCard extends StatelessWidget {
  const _RadarCard({required this.score});
  final CustomerScore score;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dims = score.dimensions;
    final withScore = dims.where((d) => d.hasScore).toList();

    // fl_chart 的 RadarDataSet assert: 至少 3 个 entry。
    //   维度不足 3 个有分 → 不画 (画出来必然误导: 空维度落到 0 看着像"极差")
    if (withScore.length < 3) {
      return _chartCard(
        context,
        title: '能力雷达',
        subtitle: '三个维度都有数据后才能生成',
        child: _EmptyHint(
          icon: Icons.radar_outlined,
          text: '还差 ${3 - withScore.length} 个维度的数据',
          hint: withScore.map((d) => '${d.label} ✓').join(' · '),
        ),
      );
    }

    return _chartCard(
      context,
      title: '能力雷达',
      subtitle: '三个维度对比一眼看清',
      child: SizedBox(
        height: 230,
        child: RadarChart(
          RadarChartData(
            dataSets: [
              RadarDataSet(
                dataEntries: dims
                    .map((d) => RadarEntry(value: d.score ?? 0))
                    .toList(),
                fillColor: t.primary.withOpacity(0.18),
                borderColor: t.primary,
                borderWidth: 2,
                entryRadius: 3,
              ),
            ],
            radarBackgroundColor: Colors.transparent,
            radarBorderData: BorderSide(color: t.divider, width: 1),
            gridBorderData: BorderSide(color: t.divider, width: 1),
            tickBorderData: BorderSide(color: t.divider, width: 1),
            tickCount: 4,
            ticksTextStyle: TextStyle(color: Colors.transparent, fontSize: AppType.micro),
            titleTextStyle: TextStyle(
              color: t.textPrimary,
              fontSize: AppType.xs,
              fontWeight: AppWeight.medium,
            ),
            getTitle: (index, angle) => RadarChartTitle(
              text: dims[index].label,
              angle: angle,
            ),
            titlePositionPercentageOffset: 0.16,
          ),
        ),
      ),
    );
  }
}

// ============================================
// ② 效果趋势线 (pain + sleep, pre 虚线 / post 实线)
// ============================================

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.charts});
  final CustomerCharts charts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pts = charts.trend.where((p) => p.hasPain).toList();

    if (pts.length < 2) {
      return _chartCard(
        context,
        title: '效果趋势',
        subtitle: '疼痛评分随时间的变化',
        child: _EmptyHint(
          icon: Icons.show_chart,
          text: '至少 2 次带疼痛评分的记录才能画趋势',
          hint: '当前 ${pts.length} 次',
        ),
      );
    }

    return _chartCard(
      context,
      title: '效果趋势',
      subtitle: '疼痛评分: 虚线=做之前 · 实线=做之后',
      child: SizedBox(
        height: 210,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: 10,
            minX: 0,
            maxX: (pts.length - 1).toDouble(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 2,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: t.divider, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 2,
                  reservedSize: 26,
                  getTitlesWidget: (v, _) => Text(
                    v.toInt().toString(),
                    style: TextStyle(fontSize: AppType.micro, color: t.textTertiary),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 22,
                  // 点多了就隔一个显示一次, 免得日期叠在一起
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= pts.length) return const SizedBox.shrink();
                    if (pts.length > 5 && i.isOdd) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpace.s4),
                      child: Text(
                        pts[i].shortDate,
                        style: TextStyle(fontSize: AppType.micro, color: t.textTertiary),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              // 做之前 (虚线)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < pts.length; i++)
                    FlSpot(i.toDouble(), pts[i].prePain!),
                ],
                color: t.textTertiary,
                barWidth: 2,
                isCurved: true,
                dashArray: const [5, 4],
                dotData: const FlDotData(show: false),
              ),
              // 做之后 (实线, 主题色)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < pts.length; i++)
                    FlSpot(i.toDouble(), pts[i].postPain!),
                ],
                color: t.primary,
                barWidth: 3,
                isCurved: true,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 3.5,
                    color: t.primary,
                    strokeWidth: 1.5,
                    strokeColor: t.surfaceCard,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: t.primary.withOpacity(0.10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// ③ 部位热力 (次数 + 中位止痛)
// ============================================

class _BodyPartCard extends StatelessWidget {
  const _BodyPartCard({required this.charts});
  final CustomerCharts charts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!charts.hasBodyParts) {
      return _chartCard(
        context,
        title: '部位分布',
        subtitle: '哪些部位反复出现',
        child: _EmptyHint(
          icon: Icons.accessibility_new,
          text: '记录里还没选过身体部位',
          hint: '下次记录时勾一下部位即可',
        ),
      );
    }

    final maxCount = charts.bodyParts
        .map((e) => e.count)
        .reduce((a, b) => a > b ? a : b);

    return _chartCard(
      context,
      title: '部位分布',
      subtitle: '次数条越长 = 该部位越常被处理',
      child: Column(
        children: [
          for (final p in charts.bodyParts.take(6)) ...[
            if (p != charts.bodyParts.first) const SizedBox(height: AppSpace.s10),
            _BodyPartRow(stat: p, maxCount: maxCount),
          ],
          if (charts.bodyParts.length > 6) ...[
            const SizedBox(height: AppSpace.s8),
            Text(
              '还有 ${charts.bodyParts.length - 6} 个部位没显示',
              style: TextStyle(fontSize: AppType.micro, color: t.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _BodyPartRow extends StatelessWidget {
  const _BodyPartRow({required this.stat, required this.maxCount});
  final BodyPartStat stat;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 止痛幅度决定条的颜色 (正=改善→主色, 0/负→警示)
    final drop = stat.medianPainDrop;
    final barColor = drop == null
        ? t.borderStrong
        : drop >= 3
            ? t.success
            : drop > 0
                ? t.primary
                : t.warning;

    return Row(
      children: [
        // ⚠ 列宽用 flex 比例而不是固定像素 (同 customer_insight_header 的做法):
        //   同一 Row 内各行 flex 一致 → 列仍严格对齐; 且随字号档位伸缩。
        Expanded(
          flex: 4,
          child: Text(
            stat.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppType.xs, color: t.textPrimary),
          ),
        ),
        const SizedBox(width: AppSpace.s8),
        Expanded(
          flex: 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.r4),
            child: LinearProgressIndicator(
              value: maxCount == 0 ? 0 : stat.count / maxCount,
              minHeight: 8,
              backgroundColor: t.surfaceSunken,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.s8),
        Expanded(
          flex: 4,
          child: Text(
            '${stat.count} 次',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: AppType.xs,
              color: t.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            // 只说统计事实, 不给建议 (CHARTER §1.3)
            drop == null
                ? '—'
                : drop > 0
                    ? '↓${drop.toStringAsFixed(1)}'
                    : drop == 0
                        ? '持平'
                        : '↑${(-drop).toStringAsFixed(1)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: AppType.xs,
              fontWeight: AppWeight.medium,
              color: barColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================
// 共用外壳
// ============================================

Widget _chartCard(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Widget child,
}) {
  final t = context.tokens;
  return Container(
    padding: const EdgeInsets.all(AppSpace.cardPadding),
    decoration: BoxDecoration(
      color: t.surfaceCard,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: t.divider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppWeight.semibold,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpace.s2),
        Text(subtitle, style: TextStyle(fontSize: AppType.micro, color: t.textTertiary)),
        const SizedBox(height: AppSpace.s12),
        child,
      ],
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text, this.hint});
  final IconData icon;
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s16),
      child: Column(
        children: [
          Icon(icon, size: AppSize.iconXl, color: t.borderStrong),
          const SizedBox(height: AppSpace.s8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.sm, color: t.textSecondary),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppSpace.s2),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.xs, color: t.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartsSkeleton extends StatelessWidget {
  const _ChartsSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.cardGap),
          Container(
            height: AppSpace.s96,
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
          ),
        ],
      ],
    );
  }
}
