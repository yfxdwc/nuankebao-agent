// ============================================
// AppStatRow + AppStatGroup —— 详情页关键信息区 (B 档)
// ============================================
//
// 设计依据 (docs/ui-principles.md):
//   - 原则 1: 数字/状态用等宽对齐, 一眼可扫 → 用 `FontFeature.tabularFigures()`
//   - 原则 4: 键值对用 1px 分隔线 (无卡片); 组内行距 8, 组间 20
//   - 原则 §3.1: 点击热区 ≥ 48 (有 onTap 时整行 48 高; 纯展示可以 40)
//
// 用途: 详情页「关键信息」多行键值对 (客户档案 / 加盟节点 / 我的资料 等)
//       左边 label (sm+secondary) / 右边 value (md+medium+primary)
//       value 必走等宽数字 → 数字列纵向对齐, 一眼能扫.
//
//   AppStatGroup({children}) 把多行包成一个视觉块 (组内 8 行距, 组间 20)
//   → 一组 = 一个语义单元 (例: 联系方式 / 节点信息 / 积分)
//
import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';

/// 一行键值对 —— label (左) / value (右)
class AppStatRow extends StatelessWidget {
  final String label;
  final String value;

  /// value 颜色 —— 默认 textPrimary; 可被 success/warning/danger 覆盖
  final Color? valueColor;

  /// 额外右侧内容 (通常是图标按钮 / 复制按钮) —— 热区 ≥48 由调用方负责
  final Widget? trailing;

  /// 点击回调 —— 给 null 时行不可点 (纯展示)
  final VoidCallback? onTap;

  /// 紧凑行高 (40 vs 48) —— 仅当**纯展示**时可开 dense (有 onTap 必须 ≥48)
  final bool dense;

  /// 自定义 value 样式 (默认 md+medium+textPrimary+tabular)
  final TextStyle? valueStyle;

  /// 自定义 label 样式 (默认 sm+regular+textSecondary)
  final TextStyle? labelStyle;

  /// 是否画底部分隔线 —— 默认 true (列表风格)
  final bool showDivider;

  /// value 文本最大行数 —— 默认 2 (允许两行地址这种)
  final int valueMaxLines;

  const AppStatRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.valueStyle,
    this.labelStyle,
    this.showDivider = true,
    this.valueMaxLines = 2,
  });

  /// 触摸底线: 纯展示可紧凑 (40), 可点必须 ≥ 48 (WCAG 2.5.5 / 原则 §3.1)
  double get _rowHeight {
    if (onTap == null && dense) return AppSize.buttonMinHeight;
    return AppSize.tapMin;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dividerColor = t.dividerTheme.color ?? AppColors.divider;
    final dividerThickness =
        t.dividerTheme.thickness ?? AppSize.borderHairline;
    final dividerSpace = t.dividerTheme.space ?? AppSize.borderHairline;

    final defaultValueStyle = TextStyle(
      fontSize: AppType.md,
      fontWeight: AppWeight.medium,
      color: valueColor ?? AppColors.textPrimary,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final defaultLabelStyle = const TextStyle(
      fontSize: AppType.sm,
      fontWeight: AppWeight.regular,
      color: AppColors.textSecondary,
    );

    final Widget content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: _rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.pagePadding,
          vertical: AppSpace.tightGap,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              flex: 4,
              child: Text(
                label,
                style: labelStyle ?? defaultLabelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpace.inlineGap),
            Expanded(
              flex: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      value,
                      style: valueStyle ?? defaultValueStyle,
                      maxLines: valueMaxLines,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: AppSpace.inlineGap),
                    trailing!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final Widget withDivider = !showDivider
        ? content
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              content,
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.pagePadding,
                ),
                child: Divider(
                  height: dividerSpace,
                  thickness: dividerThickness,
                  color: dividerColor,
                ),
              ),
            ],
          );

    if (onTap == null) return withDivider;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r0),
        child: withDivider,
      ),
    );
  }
}

/// 一组 AppStatRow —— 组内行距 8, 组间由外层 Column 控 sectionGap
///
/// 用法:
/// ```
/// AppStatGroup(children: [
///   AppStatRow(label: '手机', value: '138****8000'),
///   AppStatRow(label: '上次到店', value: '3 天前'),
/// ])
/// ```
class AppStatGroup extends StatelessWidget {
  final List<AppStatRow> children;

  /// 整组上下 padding —— 默认 0; 上下区块负责 sectionGap
  final EdgeInsetsGeometry padding;

  /// 组内行距 —— 默认 inlineGap (8)
  final double gap;

  const AppStatGroup({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.gap = AppSpace.inlineGap,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final widgets = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) widgets.add(SizedBox(height: gap));
      // 末行不画分隔线 (避免与下一组重复); 中间行画分隔线
      widgets.add(children[i]);
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: widgets,
      ),
    );
  }
}
