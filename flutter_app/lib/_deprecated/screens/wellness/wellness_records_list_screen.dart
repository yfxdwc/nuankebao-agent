import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/wellness_record.dart';
import '../../models/dictionaries.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_theme.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
final wellnessRecordsListProvider = FutureProvider<List<WellnessRecord>>((ref) async {
  return ref.watch(wellnessRecordServiceProvider).list();
});

final dictionariesProvider = FutureProvider<Dictionaries>((ref) async {
  return ref.watch(dictionaryServiceProvider).all();
});

class WellnessRecordsListScreen extends ConsumerWidget {
  const WellnessRecordsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecords = ref.watch(wellnessRecordsListProvider);
    final asyncDict = ref.watch(dictionariesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('养生记录')),
      body: asyncRecords.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (records) {
          if (records.isEmpty) {
            return const Center(child: Text('暂无养生记录'));
          }
          final dict = asyncDict.value;
          final sMap = {for (final s in dict?.serviceItems ?? []) s.id: s.name};
          final bMap = {for (final b in dict?.bodyParts ?? []) b.id: b.name};

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(wellnessRecordsListProvider);
            },
            child: ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, i) {
                final r = records[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s6),
                  child: ListTile(
                    title: Text(r.serviceDate),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppSpace.s4),
                        Text('项目: ${sMap[r.serviceItemId] ?? r.serviceItemId}'),
                        if (r.bodyPartIds.isNotEmpty)
                          Text('部位: ${r.bodyPartIds.map((id) => bMap[id] ?? id).join(', ')}',
                            style: const TextStyle(fontSize: AppType.tiny)),
                        if (r.customerFeedback != null)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpace.s4),
                            child: Text('反馈: ${r.customerFeedback}',
                              style: const TextStyle(fontSize: AppType.tiny, color: Colors.black54)),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/wellness-records/${r.id}'),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/wellness-records/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
