// ============================================
// 养生记录详情 (B2 换装, 2026-09-25 拆分)
//   - 旧 6 处 Card → 全部去边框/去阴影, 用 AppSection + 浅底容器
//   - 区段标题用 AppSectionHeader (原则 4: 纯文字 + 小间距)
//   - 部位 chips + 数字键值对都进 AppStatRow 风格
//   - body 内容抽进 wellness_record_detail_body.dart, 详情页 = 顶部 AppBar + body
//     (底部弹层复用同一份 body, 单一真相源)
// 主体行为/字段语义未动
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../widgets/wellness_record_detail_body.dart';

class WellnessRecordDetailPage extends ConsumerWidget {
  final String recordId;
  const WellnessRecordDetailPage({super.key, required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(wellnessRecordByIdProvider(recordId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('养生详情'),
        toolbarHeight: AppSize.appBarHeight,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit, size: AppSize.iconLg),
            tooltip: '编辑',
            onPressed: () => context.push('/wellness-records/$recordId/edit'),
          ),
        ],
      ),
      body: asyncRecord.when(
        loading: () => const AppSkeletonList(rows: 5),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(wellnessRecordByIdProvider(recordId)),
        ),
        data: (r) => WellnessRecordDetailBody(record: r),
      ),
    );
  }
}