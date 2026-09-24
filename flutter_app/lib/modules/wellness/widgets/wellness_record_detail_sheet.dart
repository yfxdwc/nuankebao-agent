// ============================================
// 养生记录详情底部弹层 (2026-09-25 第 13/14 项)
//
// 主人原话: 「点开养生记录查看页改底部弹窗, 高度可以高一些, 少跳页;
//            内容/显示方式与最新详情页同步」
//
// 设计决策:
//   · **高度更高**: DraggableScrollableSheet(0.5 / 0.9 / 0.96) —— 默认开 90% 屏高,
//     留 50% 作「下拉收一半」的便利位, 上推极限 96% (键盘顶起还有 4% 安全)
//   · **body 与详情页同步**: WellnessRecordDetailBody 共用一份 widget, 数据来自
//     wellnessRecordByIdProvider; 编辑保存后表单 invalidate by-id → 弹层/详情页
//     双向自动刷新
//   · **顶部 AppSheetHeader**: 标题「养生详情」 + 右侧「编辑」入口 (推路由到
//     /wellness-records/:id/edit); 编辑是 P1 高频动作, 不再藏在右上角 IconButton
//   · **加载 / 错误 态**: 与详情页同口径 (AppSkeletonList 5 行 / ErrorState 重试)
//   · **不走路由**: showModalBottomSheet 直接拿, 详情页路由 `/wellness-records/:id`
//     仍保留 (深链 / 兼容旧分享)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/app_sheet_header.dart';
import '../../../core/widgets/app_skeleton.dart';
import 'wellness_record_detail_body.dart';

/// 弹出养生记录详情底部弹层
///
/// [recordId] 后端 id; provider 自动加载, 无需传 WellnessRecord。
Future<void> showWellnessRecordDetailSheet(
  BuildContext context,
  WidgetRef ref, {
  required String recordId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
    ),
    builder: (ctx) => _WellnessRecordDetailSheet(recordId: recordId),
  );
}

class _WellnessRecordDetailSheet extends ConsumerWidget {
  final String recordId;
  const _WellnessRecordDetailSheet({required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(wellnessRecordByIdProvider(recordId));

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: <Widget>[
            // 顶部统一头部 (AppSheetHeader + Material drag handle 来自主题)
            AppSheetHeader(
              title: '养生详情',
              actions: <Widget>[
                TextButton(
                  key: const ValueKey('wellnessSheetEditBtn'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.push('/wellness-records/$recordId/edit');
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppSize.tapMin),
                  ),
                  child: const Text('编辑',
                      style: TextStyle(
                        fontSize: AppType.md,
                        color: AppColors.textSecondary,
                      )),
                ),
              ],
            ),
            Expanded(
              child: asyncRecord.when(
                loading: () => const AppSkeletonList(rows: 5),
                error: (e, _) => ErrorState(
                  error: e,
                  onRetry: () => ref
                      .invalidate(wellnessRecordByIdProvider(recordId)),
                ),
                data: (r) => WellnessRecordDetailBody(
                  record: r,
                  scrollController: scrollController,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}