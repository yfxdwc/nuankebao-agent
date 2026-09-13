import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/follow_up.dart';
import '../../providers/service_providers.dart';

final interactionsListProvider = FutureProvider<List<Interaction>>((ref) async {
  // TODO: 实际应该有 all recent 接口, 先空 list
  return [];
});

class InteractionsScreen extends ConsumerWidget {
  const InteractionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('联系记录')),
      body: const Center(
        child: Text('请从客户详情页查看联系记录\n\n(Phase 1.5: 列表聚合中)'),
      ),
    );
  }
}
