import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../models/dashboard.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_theme.dart';
import '../wellness/wellness_records_list_screen.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
final reportOverviewProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  // 简版: 复用 dashboard stats + 字典
  final dashboard = ref.watch(dashboardServiceProvider);
  final dict = ref.watch(dictionaryServiceProvider);
  final stats = await dashboard.stats();
  final dictData = await dict.all();
  return {
    'stats': stats.stats,
    'distribution': stats.distribution,
    'serviceItems': dictData.serviceItems,
  };
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReport = ref.watch(reportOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('报表中心')),
      body: asyncReport.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (data) {
          final stats = data['stats'] as DashboardStats;
          final distribution = data['distribution'] as List<ServiceDistribution>;
          final sItems = data['serviceItems'] as List;
          final sMap = {for (final s in sItems) s.id: s.name};

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 客户活跃度
                Row(
                  children: [
                    _MetricCard(label: '本月新增', value: stats.customerCount),
                    const SizedBox(width: AppSpace.s12),
                    _MetricCard(label: '本月回访', value: stats.thisMonthVisits),
                    const SizedBox(width: AppSpace.s12),
                    _MetricCard(label: '总活跃', value: stats.totalInteractions),
                  ],
                ),
                const SizedBox(height: AppSpace.s24),

                // 项目分布
                if (distribution.isNotEmpty) ...[
                  const Text('本月项目分布', style: TextStyle(fontSize: AppType.sm, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpace.s12),
                  SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        barGroups: distribution.take(5).toList().asMap().entries.map((e) {
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value.count.toDouble(),
                                color: AppTheme.primary,
                                width: AppSpace.s24,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.r4)),
                              ),
                            ],
                          );
                        }).toList(),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= distribution.length) return const SizedBox();
                                return Padding(
                                  padding: const EdgeInsets.only(top: AppSpace.s4),
                                  child: Text(
                                    sMap[distribution[i].serviceItemId] ?? '#${i}',
                                    style: const TextStyle(fontSize: AppType.micro),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final int value;
  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.black54, fontSize: AppType.tiny)),
              const SizedBox(height: AppSpace.s4),
              Text(value.toString(), style: const TextStyle(fontSize: AppType.lg, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ],
          ),
        ),
      ),
    );
  }
}
