// ============================================
// AppEmptyState —— 空态 (EmptyState 的现代封装, B 档)
// ============================================
//
// 用途: 业务页面空态统一走这个; 旧的 [EmptyState] 保留 (存量调用点太多, 不破坏),
//       新代码优先用 [AppEmptyState] —— 视觉/语义都按 [docs/ui-principles.md] 原则 8 收敛.
//
// 原则 8: 每屏必须回答「下一步做什么」 —— 空态尤其要
//   (例: 「还没有客户 → 添加第一个客户」)
//   所以本组件要求**至少**给 title; hint + action 都强烈建议.
//
// 视觉规则:
//   - icon: AppSize.avatarLg (64), 默认三级文字色 (语义: 空)
//   - title: md + medium + textPrimary (与 AppListRow.title 统一层级)
//   - hint: sm + textSecondary
//   - action: 主按钮 (buttonLgHeight = 48, 触摸底线 ≥48)
//   - 整块居中, padding 24
//
// 与 EmptyState 的区别:
//   - 新增 optional `action` widget 参数 (允许自定义按钮样式, 比如「TextButton」+ 副按钮)
//   - 默认带 action 后**不**再重复画「下一步文字」(避免双 CTA 困惑)
//   - 视觉间距对齐 B 档 (s16 → s8 → s16)
//
import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';

/// B 档空态组件 —— 业务页面优先用这个; 旧 [EmptyState] 保留兼容
class AppEmptyState extends StatelessWidget {
  /// 顶部图标 —— 默认「inbox」语义; 业务可换 (cloud_off / person_add ...)
  final IconData icon;

  /// 主标题 —— 必填 (原则 8: 必须告诉用户「现在是什么状态」)
  final String title;

  /// 副标题 —— 强烈建议给 (解释「为什么空」或「下一步做什么」)
  final String? hint;

  /// 主操作按钮 —— 比如「添加第一个客户」
  final Widget? action;

  /// 副操作 (可选) —— 比如「导入」/「了解详情」(用 TextButton)
  final Widget? secondaryAction;

  /// 自定义整块 padding —— 默认 24
  final EdgeInsetsGeometry padding;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.hint,
    this.action,
    this.secondaryAction,
    this.padding = const EdgeInsets.all(AppSpace.s24),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: AppSize.avatarLg,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpace.s16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppType.md,
                fontWeight: AppWeight.medium,
                color: AppColors.textPrimary,
              ),
            ),
            if (hint != null) ...<Widget>[
              const SizedBox(height: AppSpace.inlineGap),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppType.sm,
                  fontWeight: AppWeight.regular,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpace.s16),
              action!,
            ],
            if (secondaryAction != null) ...<Widget>[
              const SizedBox(height: AppSpace.inlineGap),
              secondaryAction!,
            ],
          ],
        ),
      ),
    );
  }
}
