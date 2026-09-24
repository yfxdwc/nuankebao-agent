// ============================================
// 养生记录详情 (B2 换装, 2026-09-25)
//   - 旧 6 处 Card → 全部去边框/去阴影, 用 AppSection + 浅底容器
//   - 区段标题用 AppSectionHeader (原则 4: 纯文字 + 小间距)
//   - 部位 chips + 数字键值对都进 AppStatRow 风格
// 主体行为/字段语义未动
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/http/api_client.dart';
import '../../../core/models/wellness_record.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_section.dart';
import '../../../core/widgets/app_skeleton.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/theme/theme_ext.dart';

class WellnessRecordDetailPage extends ConsumerWidget {
  final String recordId;
  const WellnessRecordDetailPage({super.key, required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(_recordProvider(recordId));

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
        error: (e, _) => ErrorState(error: e),
        data: (r) => _buildBody(context, ref, r),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, WellnessRecord r) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final dict = ref.watch(dictionariesProvider).valueOrNull;
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
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s10),
      children: <Widget>[
        // 头部 (独立实体: 头像 + 名称 + 日期) —— 仍用 1 个无边框容器 + 浅底
        _entitySurface(
          context,
          child: Row(
            children: <Widget>[
              Container(
                width: AppSpace.s64,
                height: AppSpace.s64,
                decoration: BoxDecoration(
                  color: context.tokens.accentSurface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Icon(Icons.favorite,
                    color: context.tokens.accent, size: AppSize.avatarMd),
              ),
              const SizedBox(width: AppSpace.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      serviceName,
                      style: const TextStyle(
                        fontSize: AppType.lg,
                        fontWeight: AppWeight.semibold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpace.tightGap),
                    Text(
                      dateFmt.format(DateTime.parse(r.serviceDate)),
                      style: const TextStyle(
                        fontSize: AppType.sm,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (bodyPartNames.isNotEmpty) ...<Widget>[
          AppSection(
            title: '部位',
            child: _entitySurface(
              context,
              child: Wrap(
                spacing: AppSpace.inlineGap,
                runSpacing: AppSpace.inlineGap,
                children: bodyPartNames
                    .map<Widget>(
                        (n) => AppBadge(label: n, tone: AppBadgeTone.brand))
                    .toList(),
              ),
            ),
          ),
        ],

        AppSection(
          title: '理疗前状态',
          child: _entitySurface(
            context,
            child: Column(
              children: <Widget>[
                _statRow('疼痛', '${r.preCondition['pain_level'] ?? '-'}'),
                _statRow('睡眠', '${r.preCondition['sleep_quality'] ?? '-'}'),
                _statRow('情绪', '${r.preCondition['mood'] ?? '-'}'),
              ],
            ),
          ),
        ),

        AppSection(
          title: '理疗后效果',
          child: _entitySurface(
            context,
            child: Column(
              children: <Widget>[
                _statRow('疼痛', '${r.postCondition['pain_level'] ?? '-'}'),
                _statRow('睡眠', '${r.postCondition['sleep_quality'] ?? '-'}'),
                _statRow('情绪', '${r.postCondition['mood'] ?? '-'}'),
              ],
            ),
          ),
        ),

        if (r.processNote != null && r.processNote!.isNotEmpty)
          AppSection(
            title: '操作过程',
            child: _entitySurface(
              context,
              child: Text(
                r.processNote!,
                style: const TextStyle(
                  fontSize: AppType.md,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

        if (r.customerFeedback != null && r.customerFeedback!.isNotEmpty)
          AppSection(
            title: '客户反馈',
            child: _entitySurface(
              context,
              child: Text(
                r.customerFeedback!,
                style: const TextStyle(
                  fontSize: AppType.md,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

        if (r.photos.isNotEmpty)
          AppSection(
            title: '部位照片 (${r.photos.length})',
            child: _entitySurface(
              context,
              child: Wrap(
                spacing: AppSpace.inlineGap,
                runSpacing: AppSpace.inlineGap,
                children: r.photos.map((url) {
                  final fullUrl =
                      url.startsWith('http') ? url : '${ApiClient.baseOrigin}$url';
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.r8),
                    child: Image.network(
                      fullUrl,
                      width: AppSpace.s100,
                      height: AppSpace.s100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: AppSpace.s100,
                        height: AppSpace.s100,
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
    );
  }

  /// 「实体卡」(无边框 + 浅底) —— 原则 4 认可的「独立实体」容器, 用 tokens 跟随主题
  Widget _entitySurface(BuildContext context,
      {required Widget child, EdgeInsets padding = const EdgeInsets.all(AppSpace.s16)}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pagePadding),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: context.tokens.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: child,
      ),
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: AppSpace.s64,
              child: Text(label,
                  style: const TextStyle(
                    fontSize: AppType.sm,
                    color: AppColors.textSecondary,
                  )),
            ),
            Text(value,
                style: const TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppWeight.medium,
                  color: AppColors.textPrimary,
                )),
          ],
        ),
      );
}

final _recordProvider = FutureProvider.family<WellnessRecord, String>(
  (ref, id) async => ref.watch(wellnessRecordServiceProvider).getById(id),
);
