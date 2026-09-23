// ============================================
// AppSheetHeader —— 底部弹层 (Sheet) 统一头部
// ============================================
//
// 配合主题 [BottomSheetThemeData.showDragHandle = true] (app_theme.dart 已配):
//   - 弹层顶部自带 Material drag handle (系统自动画) → 本组件**不**再画手柄
//   - title: lg + semibold + textPrimary
//   - subtitle: sm + textSecondary
//   - 右侧 actions: 横向排列 (一般是「取消 / 确认」两枚文字按钮)
//   - 自带底部 AppSpace.s16 间距 (与正文拉开)
//
// 设计依据 (docs/ui-principles.md):
//   - 原则 4: 不在组件内部画分割线 (让调用方决定)
//   - §0 (硬规则): TextStyle 必须显式写 color
//
import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';

class AppSheetHeader extends StatelessWidget {
  final String title;

  /// 可选副标题 —— 解释这弹层做什么
  final String? subtitle;

  /// 右侧操作 (一般是 TextButton) —— 整组居右
  final List<Widget> actions;

  /// 自定义标题样式
  final TextStyle? titleStyle;

  /// 自定义副标题样式
  final TextStyle? subtitleStyle;

  /// 整个 header 外边距 —— 默认 (pagePadding, s12)
  /// s12 = 12: drag handle 下方先留 12pt, 再写标题; 不要紧贴 handle
  final EdgeInsetsGeometry padding;

  /// 标题与 actions 之间是否画分隔线 —— 默认 false (让调用方决定)
  final bool showDivider;

  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.titleStyle,
    this.subtitleStyle,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.pagePadding,
      AppSpace.s12,
      AppSpace.pagePadding,
      AppSpace.s16,
    ),
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final defaultTitleStyle = const TextStyle(
      fontSize: AppType.lg,
      fontWeight: AppWeight.semibold,
      color: AppColors.textPrimary,
    );
    final defaultSubtitleStyle = const TextStyle(
      fontSize: AppType.sm,
      fontWeight: AppWeight.regular,
      color: AppColors.textSecondary,
    );

    final titleRow = actions.isEmpty
        ? Text(
            title,
            style: titleStyle ?? defaultTitleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: titleStyle ?? defaultTitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpace.inlineGap),
              // actions 横向排, 间距 4
              for (var i = 0; i < actions.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpace.tightGap),
                actions[i],
              ],
            ],
          );

    final t = Theme.of(context);
    final dividerColor = t.dividerTheme.color ?? AppColors.divider;
    final dividerThickness =
        t.dividerTheme.thickness ?? AppSize.borderHairline;
    final dividerSpace = t.dividerTheme.space ?? AppSize.borderHairline;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              titleRow,
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: AppSpace.tightGap),
                Text(
                  subtitle!,
                  style: subtitleStyle ?? defaultSubtitleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: dividerSpace,
            thickness: dividerThickness,
            color: dividerColor,
          ),
      ],
    );
  }
}
