// ============================================
// 养生记录详情 body (2026-09-25 第 13/14 项)
//
// 从原 wellness_record_detail_page.dart::_buildBody **原样**抽出, 视觉/字段
// 语义/区段顺序零修改 —— 仅搬位置 + 接受外部 [WellnessRecord] 与可选 [scrollController]
// (供 DraggableScrollableSheet 的 ListView 用)。
//
// 复用处: 详情页 (WellnessRecordDetailPage) + 底部弹层 (wellness_record_detail_sheet)
// 共用同一份 body, 单一真相源。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/http/api_client.dart';
import '../../../core/models/wellness_record.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_section.dart';

class WellnessRecordDetailBody extends ConsumerWidget {
  final WellnessRecord record;

  /// 可选: 给外层 DraggableScrollableSheet 的 ListView 用 (内容与滚动节流统一管理)
  final ScrollController? scrollController;

  const WellnessRecordDetailBody({
    super.key,
    required this.record,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final dict = ref.watch(dictionariesProvider).valueOrNull;
    final bodyPartNames = (dict?.bodyParts ?? [])
        .where((bp) => record.bodyPartIds.contains(bp.id))
        .map((bp) => bp.name)
        .toList();
    final serviceName = dict == null
        ? '未知服务'
        : dict.serviceItems
            .firstWhere(
              (s) => s.id == record.serviceItemId,
              orElse: () => dict.serviceItems.first,
            )
            .name;

    return ListView(
      controller: scrollController,
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
                      dateFmt.format(DateTime.parse(record.serviceDate)),
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
                _statRow('疼痛', '${record.preCondition['pain_level'] ?? '-'}'),
                _statRow('睡眠', '${record.preCondition['sleep_quality'] ?? '-'}'),
                _statRow('情绪', '${record.preCondition['mood'] ?? '-'}'),
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
                _statRow('疼痛', '${record.postCondition['pain_level'] ?? '-'}'),
                _statRow('睡眠', '${record.postCondition['sleep_quality'] ?? '-'}'),
                _statRow('情绪', '${record.postCondition['mood'] ?? '-'}'),
              ],
            ),
          ),
        ),

        if (record.processNote != null && record.processNote!.isNotEmpty)
          AppSection(
            title: '操作过程',
            child: _entitySurface(
              context,
              child: Text(
                record.processNote!,
                style: const TextStyle(
                  fontSize: AppType.md,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

        if (record.customerFeedback != null && record.customerFeedback!.isNotEmpty)
          AppSection(
            title: '客户反馈',
            child: _entitySurface(
              context,
              child: Text(
                record.customerFeedback!,
                style: const TextStyle(
                  fontSize: AppType.md,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

        if (record.photos.isNotEmpty)
          AppSection(
            title: '部位照片 (${record.photos.length})',
            child: _entitySurface(
              context,
              child: Wrap(
                spacing: AppSpace.inlineGap,
                runSpacing: AppSpace.inlineGap,
                children: record.photos.map((url) {
                  final fullUrl = url.startsWith('http')
                      ? url
                      : '${ApiClient.baseOrigin}$url';
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
      {required Widget child,
      EdgeInsets padding = const EdgeInsets.all(AppSpace.s16)}) {
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