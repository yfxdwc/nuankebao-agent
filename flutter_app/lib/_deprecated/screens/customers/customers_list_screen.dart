import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/customer.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_theme.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
final customersProvider = FutureProvider<List<Customer>>((ref) async {
  return ref.watch(customerServiceProvider).list();
});

class CustomersListScreen extends ConsumerStatefulWidget {
  const CustomersListScreen({super.key});

  @override
  ConsumerState<CustomersListScreen> createState() => _CustomersListScreenState();
}

class _CustomersListScreenState extends ConsumerState<CustomersListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final asyncCustomers = ref.watch(customersProvider);
    final filtered = _search.isEmpty
        ? null
        : ref.watch(customerServiceProvider)
            .list(search: _search)
            .then((list) => list);

    return Scaffold(
      appBar: AppBar(title: const Text('客户')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.s12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索姓名 / 手机号',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: asyncCustomers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
              data: (customers) {
                if (customers.isEmpty) {
                  return const Center(child: Text('暂无客户'));
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(customersProvider.future),
                  child: ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, i) {
                      final c = customers[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryLight,
                          child: Text(c.name.isNotEmpty ? c.name[0] : '?'),
                        ),
                        title: Text(c.name),
                        subtitle: Text(_maskPhone(c.phone)),
                        trailing: c.healthTags.isNotEmpty
                            ? Text(c.healthTags.first, style: const TextStyle(fontSize: AppType.tiny))
                            : null,
                        onTap: () => context.push('/customers/${c.id}'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/customers/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}****${phone.substring(7)}';
    }
    return phone;
  }
}
