// ============================================
// AppSkeleton + AppSkeletonList —— 加载占位 (骨架屏)
// ============================================
//
// 设计依据 (docs/ui-principles.md):
//   - 原则 7: 加载用骨架屏不用转圈 (减少感知等待时间)
//   - 反 vibe: 不要炫技动画 → **本组件故意不做动画** (成熟做法; 静止骨架块)
//   - 原则 4: 骨架与真列表**结构一致** (行高 60 / dense 52, 避免加载完成后内容跳动)
//
// 颜色: 底色 = surfaceSunken (中性灰) —— AppColors 跨主题恒定
// 圆角: 默认 r6 (通用) —— 也允许外部覆盖
//
// ⚠ 不用 shimmer (脉动) 动画: 跟项目「不要炫技动画」反 vibe; 静止骨架已被
//   Linear / Things 3 等成熟应用验证 OK
//
import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';
import 'app_list_row.dart';

/// 单块骨架占位
class AppSkeleton extends StatelessWidget {
  final double? width;
  final double height;

  /// 圆角 —— 默认 r6
  final double radius;

  /// 底色 —— 默认 surfaceSunken (跨主题恒定的中性灰)
  final Color? color;

  const AppSkeleton({
    super.key,
    this.width,
    this.height = AppSize.buttonMinHeight,
    this.radius = AppRadius.r6,
    this.color,
  });

  /// 文本骨架 (短行) —— 高度跟 xs 字号一致
  const AppSkeleton.text({
    super.key,
    this.width,
    this.radius = AppRadius.r4,
    this.color,
    double height = AppType.xs,
  }) : height = height;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final box = Container(
      width: w == double.infinity ? null : w,
      height: height,
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    // 整宽撑开
    if (w == double.infinity) {
      return FractionallySizedBox(
        widthFactor: 1,
        child: box,
      );
    }
    return box;
  }
}

/// 模拟 [AppListRow] 的骨架列表 —— 行高与真列表一致, 避免加载完成后内容跳动
///
/// 默认 5 行; 默认带 leading (44) + subtitle; 末行不画分隔线 (避免与下一组重复)
class AppSkeletonList extends StatelessWidget {
  /// 行数 —— 默认 5
  final int rows;

  /// 是否画左侧头像占位 (44×44)
  final bool showLeading;

  /// 是否画副标题占位
  final bool showSubtitle;

  /// dense 行高 (52) —— 默认 false = 60
  final bool dense;

  /// 外层 padding —— 默认 0; 由调用方控制
  final EdgeInsetsGeometry padding;

  const AppSkeletonList({
    super.key,
    this.rows = 5,
    this.showLeading = true,
    this.showSubtitle = true,
    this.dense = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final rowHeight = dense ? AppListRow.denseRowHeight : AppListRow.defaultRowHeight;
    final t = Theme.of(context);
    final dividerColor = t.dividerTheme.color ?? AppColors.divider;
    final dividerThickness =
        t.dividerTheme.thickness ?? AppSize.borderHairline;
    final dividerSpace = t.dividerTheme.space ?? AppSize.borderHairline;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < rows; i++) ...<Widget>[
            _buildSkeletonRow(
              rowHeight: rowHeight,
              showLeading: showLeading,
              showSubtitle: showSubtitle,
              isLast: i == rows - 1,
              dividerColor: dividerColor,
              dividerThickness: dividerThickness,
              dividerSpace: dividerSpace,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeletonRow({
    required double rowHeight,
    required bool showLeading,
    required bool showSubtitle,
    required bool isLast,
    required Color dividerColor,
    required double dividerThickness,
    required double dividerSpace,
  }) {
    final leadingBlock = showLeading
        ? const AppSkeleton(
            width: AppSize.avatarMd,
            height: AppSize.avatarMd,
            radius: AppRadius.full,
          )
        : null;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // title: 60% 宽, xs 字号高度
        const FractionallySizedBox(
          widthFactor: 0.6,
          alignment: Alignment.centerLeft,
          child: AppSkeleton(height: AppType.md),
        ),
        if (showSubtitle) ...<Widget>[
          const SizedBox(height: AppSpace.tightGap),
          const FractionallySizedBox(
            widthFactor: 0.4,
            alignment: Alignment.centerLeft,
            child: AppSkeleton(height: AppType.sm),
          ),
        ],
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: rowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.pagePadding,
              vertical: AppSpace.s10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                if (leadingBlock != null) ...<Widget>[
                  leadingBlock,
                  const SizedBox(width: AppSpace.inlineGap),
                ],
                Expanded(child: column),
              ],
            ),
          ),
        ),
        // 末行不画分隔线
        if (!isLast)
          Padding(
            padding: EdgeInsets.only(
              left: showLeading
                  ? AppSize.avatarMd + AppSpace.inlineGap
                  : 0,
            ),
            child: Divider(
              height: dividerSpace,
              thickness: dividerThickness,
              color: dividerColor,
            ),
          ),
      ],
    );
  }
}
