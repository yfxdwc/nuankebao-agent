import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/wellness_record.dart';
import '../../models/dictionaries.dart';
import '../../providers/service_providers.dart';
import '../wellness/wellness_records_list_screen.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
final wellnessRecordDetailProvider = FutureProvider.family<WellnessRecord, String>(
  (ref, id) => ref.watch(wellnessRecordServiceProvider).getById(id),
);

class WellnessRecordDetailScreen extends ConsumerWidget {
  final String recordId;
  const WellnessRecordDetailScreen({super.key, required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(wellnessRecordDetailProvider(recordId));
    final asyncDict = ref.watch(dictionariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('养生记录详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/wellness-records/$recordId/edit'),
          ),
        ],
      ),
      body: asyncRecord.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (r) {
          final dict = asyncDict.value;
          final sName = dict?.serviceItems
                  .where((s) => s.id == r.serviceItemId)
                  .firstOrNull?.name ??
              r.serviceItemId;
          final bNames = r.bodyPartIds
              .map((id) => dict?.bodyParts.where((b) => b.id == id).firstOrNull?.name ?? id)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(AppSpace.s16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.serviceDate, style: const TextStyle(fontSize: AppType.md, fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.s4),
                      Text('项目: $sName'),
                      if (bNames.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.s8),
                        Wrap(
                          spacing: 6,
                          children: bNames.map((n) => Chip(label: Text(n))).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              if (r.preCondition.isNotEmpty || r.postCondition.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('状态对比', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppSpace.s8),
                        ...r.preCondition.entries.map((e) {
                          final post = r.postCondition[e.key];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(e.key),
                                Text('${e.value} → ${post ?? '-'}',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600,
                                  )),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              if (r.processNote != null) ...[
                const SizedBox(height: AppSpace.s12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('理疗过程', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppSpace.s8),
                        Text(r.processNote!),
                      ],
                    ),
                  ),
                ),
              ],
              if (r.customerFeedback != null) ...[
                const SizedBox(height: AppSpace.s12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('客户反馈', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppSpace.s8),
                        Text(r.customerFeedback!),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
