import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/customer.dart';
import '../../models/wellness_record.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/photo_picker.dart';
import '../../widgets/prediction_widgets.dart';
import '../customers/customers_list_screen.dart';

final customerDetailProvider = FutureProvider.family<Customer, String>(
  (ref, id) => ref.watch(customerServiceProvider).getById(id),
);

final customerWellnessRecordsProvider = FutureProvider.family<List<WellnessRecord>, String>(
  (ref, customerId) => ref.watch(wellnessRecordServiceProvider).list(customerId: customerId),
);

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCustomer = ref.watch(customerDetailProvider(customerId));
    final asyncRecords = ref.watch(customerWellnessRecordsProvider(customerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('客户详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/customers/$customerId/edit'),
          ),
        ],
      ),
      body: asyncCustomer.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (customer) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(customer),
            const SizedBox(height: 16),
            if (customer.healthTags.isNotEmpty) _buildHealthTags(customer),
            const SizedBox(height: 16),
            _buildSectionTitle('养生记录', onTap: () => context.push(
              '/wellness-records/new?customerId=$customerId',
            )),
            asyncRecords.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('加载失败: $e'),
              data: (records) {
                if (records.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无养生记录', style: TextStyle(color: Colors.black54)),
                  );
                }
                return Column(
                  children: records.take(5).map((r) {
                    return Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(r.serviceDate),
                            subtitle: r.customerFeedback != null
                                ? Text('反馈: ${r.customerFeedback}')
                                : null,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/wellness-records/${r.id}'),
                          ),
                          // 照片缩略图
                          if (r.photos.isNotEmpty)
                            SizedBox(
                              height: 80,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: r.photos.length,
                                itemBuilder: (ctx, i) {
                                  final url = r.photos[i].startsWith('http')
                                      ? r.photos[i]
                                      : 'http://192.168.1.200:3003${r.photos[i]}';
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        url,
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 80,
                                          height: 80,
                                          color: Colors.grey[300],
                                          child: const Icon(Icons.broken_image, size: 20),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            // AI 客户画像按钮
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome, color: AppTheme.primary),
                title: const Text('AI 客户画像'),
                subtitle: const Text('基于历史记录生成客户洞察'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/ai?customerId=$customerId'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.chat, color: AppTheme.primary),
                title: const Text('AI 跟进建议'),
                subtitle: const Text('生成跟进入口话术'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/ai?customerId=$customerId'),
              ),
            ),

            // Phase 2: AI 复购预测 (根据历史间隔算下次到店)
            RepurchasePredictionCard(customerId: customer.id),

            // Phase 2: AI 效果分析 (多疗程趋势 + AI 总结)
            EffectAnalysisCard(customerId: customer.id),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Customer c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primaryLight,
                  child: Text(c.name.isNotEmpty ? c.name[0] : '?',
                    style: const TextStyle(fontSize: 24, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      Text(c.phone, style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (c.gender != null || c.birthYear != null)
              Wrap(
                spacing: 8,
                children: [
                  if (c.gender != null) Chip(label: Text(c.gender == 'F' ? '女' : c.gender == 'M' ? '男' : '未知')),
                  if (c.birthYear != null) Chip(label: Text('${c.birthYear}年')),
                ],
              ),
            if (c.diseaseHistory != null && c.diseaseHistory!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('既往病史: ${c.diseaseHistory}', style: const TextStyle(fontSize: 13)),
            ],
            if (c.notes != null && c.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('备注: ${c.notes}', style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthTags(Customer c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('健康标签', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: c.healthTags
                  .map((t) => Chip(label: Text(t), backgroundColor: AppTheme.primaryLight.withOpacity(0.2)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (onTap != null)
            TextButton(onPressed: onTap, child: const Text('+ 添加')),
        ],
      ),
    );
  }
}
