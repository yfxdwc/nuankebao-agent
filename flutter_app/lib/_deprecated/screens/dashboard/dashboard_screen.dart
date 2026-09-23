import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../models/dashboard.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
class DashboardData {
  final DashboardStats stats;
  final List<ServiceDistribution> distribution;
  DashboardData(this.stats, this.distribution);
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final dashboard = ref.watch(dashboardServiceProvider);
  final stats = await dashboard.stats();
  return DashboardData(stats.stats, stats.distribution);
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('仪表盘'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (data) => _buildBody(context, ref, data),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, DashboardData data) {
    final stats = data.stats;
    final distribution = data.distribution;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                StatCard(
                  label: '客户总数',
                  value: stats.customerCount,
                  icon: Icons.people,
                  color: AppTheme.primary,
                  onTap: () => context.push('/customers'),
                ),
                StatCard(
                  label: '本月到店',
                  value: stats.thisMonthVisits,
                  icon: Icons.favorite,
                  color: AppTheme.accent,
                  onTap: () => context.push('/wellness-records'),
                ),
                StatCard(
                  label: '待跟进',
                  value: stats.pendingFollowUps,
                  icon: Icons.notifications,
                  color: Colors.orange,
                  onTap: () => context.push('/follow-ups'),
                ),
                StatCard(
                  label: '联系记录',
                  value: stats.totalInteractions,
                  icon: Icons.chat,
                  color: Colors.blue,
                  onTap: () => context.push('/interactions'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s24),
            const Text('快捷操作', style: TextStyle(fontSize: AppType.sm, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.s12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.person_add,
                    title: '新增客户',
                    onTap: () => context.push('/customers/new'),
                  ),
                ),
                const SizedBox(width: AppSpace.s12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.favorite,
                    title: '新增养生记录',
                    onTap: () => context.push('/wellness-records/new'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.auto_awesome,
                    title: 'AI 助手',
                    onTap: () => context.push('/ai'),
                  ),
                ),
                const SizedBox(width: AppSpace.s12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.bar_chart,
                    title: '报表中心',
                    onTap: () => context.push('/reports'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s24),
            if (distribution.isNotEmpty) ...[
              const Text('本月项目分布', style: TextStyle(fontSize: AppType.sm, fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.s12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.s16),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 200,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 50,
                            sections: distribution.take(5).toList().asMap().entries.map((e) {
                              final colors = [
                                AppTheme.primary,
                                AppTheme.primaryLight,
                                AppTheme.accent,
                                Colors.orange,
                                Colors.purple,
                              ];
                              return PieChartSectionData(
                                value: e.value.count.toDouble(),
                                color: colors[e.key % colors.length],
                                title: '${e.value.count}',
                                titleStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppType.xs,
                                ),
                                radius: 60,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.s12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: distribution.take(5).toList().asMap().entries.map((e) {
                          final colors = [
                            AppTheme.primary,
                            AppTheme.primaryLight,
                            AppTheme.accent,
                            Colors.orange,
                            Colors.purple,
                          ];
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: AppSpace.s12,
                                height: AppSpace.s12,
                                decoration: BoxDecoration(
                                  color: colors[e.key % colors.length],
                                  borderRadius: BorderRadius.circular(AppRadius.r2),
                                ),
                              ),
                              const SizedBox(width: AppSpace.s4),
                              Text(
                                '#${e.value.serviceItemId} (${e.value.count})',
                                style: const TextStyle(fontSize: AppType.tiny),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s20),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: AppSpace.s28),
              const SizedBox(width: AppSpace.s12),
              Text(title, style: const TextStyle(fontSize: AppType.sm, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}