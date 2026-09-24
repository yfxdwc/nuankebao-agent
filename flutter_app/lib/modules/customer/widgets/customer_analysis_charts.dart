// ============================================
// 客户分析图谱 —— 分析 Tab 的两张图 (P1 砍雷达后, 2026-09-24)
// ============================================
//   ① 效果趋势线   pain+sleep 前→后 随时间   —— 数据来自 /charts trend
//   ② 部位热力条   哪些部位反复出问题 + 止痛  —— 数据来自 /charts bodyParts
//
// ⚠ 2026-09-24 主人拍板砍掉「能力雷达图」——
//   三条理由:
//   · 与评分卡三维条**同源重复** (评分卡已经有 effect/engagement/value 三维条 + 分,
//     雷达只是把同样数据换种画法, 信息密度没增)
//   · 3 维雷达可读性差 (RadarChart 在窄屏尤其糊, 网格 + 标签挤在一起, 销售
//     看不出"哪个维度突出", 反而要人脑重新解读)
//   · 分析 Tab 太长 (评分卡 + AI 4 张卡已经把分析 Tab 顶到 2 屏以上, 再加
//     雷达 = 销售滑到底都看不到第二张)
//   砍雷达后, 评分卡的三维条就是「这三维度怎样」的唯一视觉入口 —— 唯一性更好。
//
// 设计依据 (docs/ui-principles.md):
//   · 原则 2「层级靠对比不靠放大」: 图里用**颜色 + 数值标签**表达好坏, 不靠放大
//   · 原则 4「容器越少内容越强」: 一张图一个白底块 (无边框/阴影)
//   · ⚠ 只画**描述性统计**: 出现次数 / 中位止痛幅度。
//     不写"这个部位该用什么方案" —— CHARTER §1.3 不做医疗诊断, 那是技师/店长的判断。
//
// 健壮性:
//   · 数据不足时按 recordCount 给**进度** (0 条 / 有条但没填评分 / 还差 1 条)
//   · charts 请求失败 → 轻量错误块 + 「重新加载」按钮 (不再静默消失)
// ============================================

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/customer_charts.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';

/// 分析 Tab 的图谱区 (趋势 + 部位)
class CustomerAnalysisCharts extends ConsumerWidget {
  const CustomerAnalysisCharts({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerChartsProvider(customerId));

    // ⚠ 不要用 CrossAxisAlignment.stretch ——
    //   本组件是「分析 Tab 的 ListView」的直接子节点, 拿到的是**无界高度**;
    //   stretch 会让 Column 尝试撑满交叉轴, 在无界约束下布局塌成 **0 高**:
    //   不抛任何异常, 但整块图完全不可见, 连语义树里都没有 (排查了很久)。
    //   子组件自己决定宽度的话用 start 即可 (它们本来就是 block 级, 会占满可用宽度)。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        async.when(
          loading: () => const _ChartsSkeleton(),
          // 错误 → 轻量错误块 + 重新加载 (不再静默 SizedBox.shrink)
          error: (_, __) => _ChartsError(customerId: customerId),
          data: (c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
// 错误态: 轻量错误块 + 「重新加载」
// ============================================

class _ChartsError extends ConsumerWidget {
  const _ChartsError({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return B2NoChrome(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: AppSize.iconMd,
                  color: t.danger,
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: Text(
                    '图表没加载出来',
                    style: TextStyle(
                      fontSize: AppType.sm,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s10),
            Text(
              '稍后再试, 或点下面的按钮重试',
              style: TextStyle(
                fontSize: AppType.xs,
                color: t.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpace.s10),
            InkWell(
              onTap: () =>
                  ref.invalidate(customerChartsProvider(customerId)),
              borderRadius: BorderRadius.circular(AppRadius.button),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.s14,
                  vertical: AppSpace.s8,
                ),
                decoration: BoxDecoration(
                  color: t.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                constraints: const BoxConstraints(
                  minHeight: AppSize.tapMin,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh,
                      size: AppSize.iconSm,
                      color: t.primaryDark,
                    ),
                    const SizedBox(width: AppSpace.s6),
                    Text(
                      '重新加载',
                      style: TextStyle(
                        fontSize: AppType.sm,
                        color: t.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// ① 效果趋势线 (pain + sleep, pre 虚线 / post 实线)
// ============================================

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.charts});
  final CustomerCharts charts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pts = charts.trend.where((p) => p.hasPain).toList();

    if (pts.length < 2) {
      // 进度化空态 (P0, 2026-09-24):
      //   pts==1 → 差一条就有图; pts==0 + 有记录 → 缺的是疼痛评分;
      //   pts==0 + 没记录 → 先去做一条。
      final String hint;
      if (pts.length == 1) {
        hint = '已有 1 次, 再记 1 次就能画';
      } else if (charts.recordCount > 0) {
        hint = '已有 ${charts.recordCount} 条记录, 但都还没填疼痛评分';
      } else {
        hint = '还没有养生记录, 先记一次';
      }
      return _chartCard(
        context,
        title: '效果趋势',
        subtitle: '疼痛评分随时间的变化',
        child: _EmptyHint(
          icon: Icons.show_chart,
          text: '至少 2 次带疼痛评分的记录才能画趋势',
          hint: hint,
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
// ② 部位热力 (次数 + 中位止痛)
// ============================================

class _BodyPartCard extends StatelessWidget {
  const _BodyPartCard({required this.charts});
  final CustomerCharts charts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!charts.hasBodyParts) {
      // 进度化空态 (P0, 2026-09-24):
      //   recordCount>0 → 记录做了, 但没勾部位; recordCount==0 → 还没做记录。
      final String hint;
      if (charts.recordCount > 0) {
        hint = '已有 ${charts.recordCount} 条记录, 但都还没勾部位';
      } else {
        hint = '还没有养生记录, 先记一次';
      }
      return _chartCard(
        context,
        title: '部位分布',
        subtitle: '哪些部位反复出现',
        child: _EmptyHint(
          icon: Icons.accessibility_new,
          text: '记录里还没选过身体部位',
          hint: hint,
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
// 共用外壳 (无边框, 跟分析 Tab 其他卡片同风格, B2NoChrome 同款)
// ============================================

Widget _chartCard(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Widget child,
}) {
  return B2NoChrome(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: AppType.md,
              fontWeight: AppWeight.semibold,
              color: context.tokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpace.s2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: AppType.micro,
              color: context.tokens.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpace.s12),
          child,
        ],
      ),
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