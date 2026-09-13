// ============================================
// 养生记录详情 (Plan F2.5)
// 从客户详情时间线 / 全局列表跳入
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/wellness_record.dart';
import '../providers/service_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';

class WellnessRecordDetailPage extends ConsumerWidget {
  final String recordId;
  const WellnessRecordDetailPage({super.key, required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(_recordProvider(recordId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('养生详情'),
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: 28),
            tooltip: '编辑',
            onPressed: () => context.push('/wellness-records/$recordId/edit'),
          ),
        ],
      ),
      body: asyncRecord.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (r) => _buildBody(context, ref, r),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, WellnessRecord r) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final dict = ref.watch(_dictProvider).valueOrNull;
    final bodyPartNames = (dict?.bodyParts ?? [])
        .where((bp) => r.bodyPartIds.contains(bp.id))
        .map((bp) => bp.name)
        .toList();
    final serviceName = dict == null
      ? '未知服务'
      : dict.serviceItems
          .firstWhere(
            (s) => s.id == r.serviceItemId,
            orElse: () => dict.serviceItems.first,
          )
          .name;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 头部
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(Icons.favorite, color: AppTheme.accent, size: 36),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            serviceName,
                            style: const TextStyle(
                              fontSize: AppTheme.fontLg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateFmt.format(DateTime.parse(r.serviceDate)),
                            style: const TextStyle(
                              fontSize: AppTheme.fontSm,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 部位
        if (bodyPartNames.isNotEmpty) ...[
          _section('部位'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: bodyPartNames.map((n) => Chip(
                  label: Text(n, style: const TextStyle(fontSize: AppTheme.fontSm)),
                  backgroundColor: AppTheme.primaryLight.withOpacity(0.3),
                )).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 理疗前状态
        _section('理疗前状态'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _statRow('疼痛', '${r.preCondition['pain_level'] ?? '-'}'),
                _statRow('睡眠', '${r.preCondition['sleep_quality'] ?? '-'}'),
                _statRow('情绪', '${r.preCondition['mood'] ?? '-'}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 理疗后效果
        _section('理疗后效果'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _statRow('疼痛', '${r.postCondition['pain_level'] ?? '-'}'),
                _statRow('睡眠', '${r.postCondition['sleep_quality'] ?? '-'}'),
                _statRow('情绪', '${r.postCondition['mood'] ?? '-'}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (r.processNote != null && r.processNote!.isNotEmpty) ...[
          _section('操作过程'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                r.processNote!,
                style: const TextStyle(fontSize: AppTheme.fontMd),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (r.customerFeedback != null && r.customerFeedback!.isNotEmpty) ...[
          _section('客户反馈'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                r.customerFeedback!,
                style: const TextStyle(fontSize: AppTheme.fontMd),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (r.photos.isNotEmpty) ...[
          _section('部位照片 (${r.photos.length})'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: r.photos.map((url) {
                  final fullUrl = url.startsWith('http')
                      ? url
                      : 'http://192.168.1.200:3003$url'; // TODO: 改 env
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      fullUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100,
                        height: 100,
                        color: AppTheme.bgWarm,
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      );

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(label, style: const TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
            ),
            Text(value, style: const TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

final _recordProvider = FutureProvider.family<WellnessRecord, String>(
  (ref, id) async => ref.watch(wellnessRecordServiceProvider).getById(id),
);

final _dictProvider = FutureProvider(
  (ref) async => ref.watch(dictionaryServiceProvider).all(),
);