// ============================================
// 空态族: AppEmptyState (主用) + EmptyState (兼容) + LoadingState + ErrorState
// 收编自老 empty_state.dart (B2 合并, 2026-09-25)
// ============================================
//
// 用法:
//   - 新代码一律用 AppEmptyState (B 档, 视觉/语义按 docs/ui-principles.md 原则 8)
//   - 旧 EmptyState 调用点同步迁到 AppEmptyState (onAction+actionLabel 改 action: FilledButton)
//   - LoadingState / ErrorState 仍可用; 它们内部已迁到 AppEmptyState
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

/// 加载中 (大圆圈) —— 业务侧有用到 (admin_tools_page, salon 页面, my_referrals 等)
///   sm = 16 (按钮内 / 列表右侧 inline)
///   md = 48 (页面级 / 卡片级, 默认)
///   lg = 64 (空态 hero 区)
///
/// ⚠ 按钮内 (高度 20-26) 不要用 LoadingState -- 它的 Center 包装会破坏按钮布局。
class LoadingState extends StatelessWidget {
  final double? size;
  final double? strokeWidth;
  final Color? color;
  const LoadingState({super.key, this.size, this.strokeWidth, this.color});

  @override
  Widget build(BuildContext context) {
    final s = size ?? AppSize.buttonLgHeight; // md 默认 48
    return Center(
      child: SizedBox(
        width: s,
        height: s,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth ?? 3,
          color: color,
        ),
      ),
    );
  }
}

/// 加载失败 → 套 [AppEmptyState], 自动给「重试」按钮
class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.cloud_off,
      title: '网络不太好',
      hint: '请检查网络后重试一下',
      action: onRetry == null
          ? null
          : FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                minimumSize: const Size(160, AppSize.buttonLgHeight),
              ),
              child: const Text('重试'),
            ),
    );
  }
}

/// ============================================
/// 空态 (EmptyState) —— 向后兼容别名.
///
/// 已合并 (B2, 2026-09-25) ——
///   - 旧代码用 `EmptyState(title, hint, onAction, actionLabel)` 直接换成 AppEmptyState
///   - onAction + actionLabel 自动折成 `action: FilledButton`
///   - 已无调用点; 保留到下次大版本, 不再写新代码
/// ============================================
// ignore: deprecated_member_use_from_same_package
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;

  /// 旧字段 onAction + actionLabel: 折成 FilledButton
  final VoidCallback? onAction;
  final String? actionLabel;

  /// 新字段: 自定义主操作 widget (允许自定义样式)
  final Widget? action;
  final Widget? secondaryAction;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.hint,
    this.onAction,
    this.actionLabel,
    this.action,
    this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: icon,
      title: title,
      hint: hint,
      action: action ??
          (onAction != null && actionLabel != null
              ? FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, AppSize.buttonLgHeight),
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(fontSize: AppType.md),
                  ),
                )
              : null),
      secondaryAction: secondaryAction,
    );
  }
}
