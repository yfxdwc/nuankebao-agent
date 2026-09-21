// ============================================
// 客户详情页 — 跟进分析卡 (主人 2026-09-20 拍 P1, 方案 §7.1)
// ============================================
// 位置: 详情页 **AI 区之前** (先看客观事实, 再看 AI 解读)
// 判权 (方案 §11): 客观指标**免费**; AI 解读**会员** → 非会员显示「升级会员看 AI 解读」
//                 (不锁数据, 只锁解读; AI 生成仍走既有「AI 跟进建议」卡, 本卡不烧额度)
//
// 中老年友好: 大字 + 大白话 + 数字在前; 趋势用颜色 + 文字双编码

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/follow_up_info.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';

class FollowUpAnalysisCard extends ConsumerStatefulWidget {
  final String customerId;
  const FollowUpAnalysisCard({super.key, required this.customerId});

  @override
  ConsumerState<FollowUpAnalysisCard> createState() =>
      _FollowUpAnalysisCardState();
}

class _FollowUpAnalysisCardState extends ConsumerState<FollowUpAnalysisCard> {
  FollowUpAnalysis? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(customerServiceProvider)
          .followUpAnalysis(widget.customerId);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, size: 26, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '跟进分析',
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 22),
                  tooltip: '重新计算',
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '客观记录: 联系频次 / 到店节奏 / 待办',
              style: TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 10),
                    Text('正在算跟进情况...',
                        style: TextStyle(
                            fontSize: AppTheme.fontSm,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              )
            else if (_error != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('加载失败: $_error',
                      style: const TextStyle(
                          fontSize: AppTheme.fontXs, color: AppTheme.danger)),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _load, child: const Text('重试')),
                ],
              )
            else if (_data != null)
              _buildBody(_data!),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(FollowUpAnalysis a) {
    final trendColor = a.isColder
        ? AppTheme.danger
        : a.isWarmer
            ? AppTheme.primary
            : AppTheme.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 一句话总结 (免费层, 服务端拼的)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgWarm,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            a.headline,
            style: const TextStyle(
              fontSize: AppTheme.fontSm,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 趋势 (颜色 + 文字双编码)
        if (a.trend != 'unknown')
          Row(
            children: [
              Icon(
                a.isColder
                    ? Icons.trending_down
                    : a.isWarmer
                        ? Icons.trending_up
                        : Icons.trending_flat,
                size: 22,
                color: trendColor,
              ),
              const SizedBox(width: 6),
              Text(
                a.trendText,
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  fontWeight: FontWeight.w600,
                  color: trendColor,
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),

        // 指标网格
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(
              label: '近 30 天联系',
              value: '${a.contactLast30} 次',
              sub: '近 90 天 ${a.contactLast90} 次',
            ),
            _Metric(
              label: '联系间隔',
              value: a.avgContactIntervalDays == null
                  ? '—'
                  : '${a.avgContactIntervalDays} 天',
              sub: a.avgContactIntervalDays == null ? '联系还太少' : '平均一次',
            ),
            _Metric(
              label: '到店次数',
              value: '${a.visitCount} 次',
              sub: a.avgVisitIntervalDays == null
                  ? '暂无规律'
                  : '每 ${a.avgVisitIntervalDays} 天一次',
            ),
            _Metric(
              label: '复购间隔',
              value: a.medianRepurchaseIntervalDays == null
                  ? '—'
                  : '${a.medianRepurchaseIntervalDays} 天',
              sub: '历史中位数',
            ),
            _Metric(
              label: '上次到店',
              value: a.daysSinceLastVisit == null
                  ? '—'
                  : '${a.daysSinceLastVisit} 天前',
              sub: a.lastVisitAt == null
                  ? '还没到过店'
                  : DateFormat('yyyy-MM-dd').format(a.lastVisitAt!.toLocal()),
            ),
            _Metric(
              label: '待办跟进',
              value: '${a.pendingTasks} 条',
              sub: a.overdueTasks > 0
                  ? '逾期 ${a.overdueTasks} 条'
                  : '没有逾期',
              danger: a.overdueTasks > 0,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // AI 解读: 会员提示 (客观指标不锁, 只锁解读)
        if (!a.aiTipAvailable)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '🔒 升级会员可看 AI 解读 (该聊什么 / 开场话术)',
              style: TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// 小指标块 (label / 大字 value / 小字 sub)
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
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: AppTheme.fontXs,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTheme.fontLg,
              fontWeight: FontWeight.w700,
              color: danger ? AppTheme.danger : AppTheme.textPrimary,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 13,
              color: danger ? AppTheme.danger : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
