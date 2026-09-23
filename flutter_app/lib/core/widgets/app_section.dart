// ============================================
// AppSectionHeader + AppSection —— 区块标题与容器 (B 档)
// ============================================
//
// 设计依据 (docs/ui-principles.md):
//   - 原则 4: 区块标题**纯文字 + 小间距**, 禁止装饰条 / 色块 / 图标前缀
//   - 原则 4: 区块之间用 sectionGap (20), 组内用 inlineGap (8)
//   - 原则 5: 颜色是信号, 不用色块当标题
//   - §0 (硬规则): TextStyle 必须显式写 color
//
// 用途:
//   - AppSectionHeader: 单独渲染标题 (如页面里多个并列 section)
//   - AppSection: 标题 + 内容一站式容器 (常见用法)
//
// 注意:
//   - AppSection / AppSectionHeader **不**画边框、**不**画阴影、**不**铺卡片背景
//     —— 留给真的「独立实体」(如客户卡 / 沙龙卡) 才用 [Card]
//
import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';

/// 区块标题 —— 纯文字 + 可选副标题 + 可选右侧操作
class AppSectionHeader extends StatelessWidget {
  final String title;

  /// 可选副标题 —— 出现在标题正下方一行, 字号 sm + textSecondary
  final String? subtitle;

  /// 右侧操作 (通常是 TextButton 或小图标按钮) —— 热区 ≥ 48 (调用方负责)
  final Widget? action;

  /// 自定义标题样式 (允许覆盖字号/字重/颜色); 默认 = lg+semibold+textPrimary
  final TextStyle? titleStyle;

  /// 自定义副标题样式; 默认 = sm+regular+textSecondary
  final TextStyle? subtitleStyle;

  /// 标题区垂直 padding —— 默认 (sectionGap/2, 0) 让上一区块留出 sectionGap
  /// 调用方可以传 EdgeInsets.zero (当标题紧贴在内容上方时)
  final EdgeInsetsGeometry padding;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.titleStyle,
    this.subtitleStyle,
    this.padding =
        const EdgeInsets.symmetric(vertical: AppSpace.s10),
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

    final t = DefaultTextStyle.merge(
      style: titleStyle ?? defaultTitleStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: Text(title),
    );

    final Widget content = action == null
        ? t
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: t),
              const SizedBox(width: AppSpace.inlineGap),
              action!,
            ],
          );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          content,
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
    );
  }
}

/// 区块容器 —— 标题 + 子内容 (组内用 inlineGap 8, 区块间由调用方控制)
class AppSection extends StatelessWidget {
  /// 主标题 (必填)
  final String title;

  /// 可选副标题 —— 解释这区块做什么
  final String? subtitle;

  /// 右侧操作 (TextButton / 图标按钮)
  final Widget? action;

  /// 子内容
  final Widget child;

  /// 内容上下 padding —— 默认 (0, 0); 常见用法 = 区块间由外层 Column 控 sectionGap
  final EdgeInsetsGeometry childPadding;

  /// 自定义标题样式
  final TextStyle? titleStyle;

  /// 自定义副标题样式
  final TextStyle? subtitleStyle;

  /// 整个区块外层 padding —— 默认 (pagePadding, 0); 给页面用的标准水平 padding
  final EdgeInsetsGeometry outerPadding;

  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.childPadding = EdgeInsets.zero,
    this.titleStyle,
    this.subtitleStyle,
    this.outerPadding = const EdgeInsets.symmetric(
      horizontal: AppSpace.pagePadding,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: outerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppSectionHeader(
            title: title,
            subtitle: subtitle,
            action: action,
            titleStyle: titleStyle,
            subtitleStyle: subtitleStyle,
          ),
          Padding(
            padding: childPadding,
            child: child,
          ),
        ],
      ),
    );
  }
}
