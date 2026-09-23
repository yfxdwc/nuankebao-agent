// ============================================
// AppListRow —— 同质列表的唯一行组件 (B 档紧凑)
// ============================================
//
// 用途: 客户列表 / 跟进任务 / 记录列表 / 沙龙列表 等**同质列表**的标准行。
//       后续所有页面重写都必须用这个组件, 不要再自己拼 `Row + Card` + 分隔线。
//
// 设计依据 (docs/ui-principles.md):
//   - 原则 1: 行高 60 (dense=52), 一屏 9 条+
//   - 原则 2: 文字层级 = md+medium+textPrimary / sm+regular+textSecondary / xs+textTertiary
//   - 原则 4: 同质列表 = 1px 分隔线 + 留白, **无卡片、无圆角、无阴影**
//   - 原则 §3.1: 点击热区 ≥ 48×48 (行高 60 天然满足, dense 用 ConstrainedBox 兜底)
//   - §0 (硬规则): 主题里 TextStyle 必显式 color, 不写会被 RawChip 类顶掉默认色 → 真机白字
//
// 视觉规则:
//   - leading: 头像 / 图标, 常见尺寸 = AppSize.avatarMd (44)
//   - title:   主文 (字体略重); 允许 Row 嵌套徽章, 但要保证主名能 ellipsis
//   - subtitle: 副文 (略小、灰)
//   - meta:    右对齐副信息 (时间/计数, 更小、更灰)
//   - trailing: 最右操作 (箭头/按钮); 与 meta 可同时给 (meta 在左, trailing 在右)
//   - 有 leading 时, 分隔线**左缩进**到 leading 之后 (iOS/微信的成熟做法)
//
import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';

/// 同质列表行 (B 档 · 60 / 52)
class AppListRow extends StatelessWidget {
  /// 行高 —— 默认 [AppSize.listRowHeight] (60); dense = 52
  static const double defaultRowHeight = AppSize.listRowHeight;

  /// dense 行高 (40 + 12 上下内边距 = 52) —— 留给次级列表 (如设置项 / 记录)
  static const double denseRowHeight = AppSize.buttonLgHeight + AppSpace.s4;

  /// 左侧头像 / 图标 (尺寸自定, 常见 AppSize.avatarMd)
  final Widget? leading;

  /// 主文 —— 通常 `Text`; 允许 `Row` (放徽章) 但要保证名字 ellipsis 不被挤没
  final Widget title;

  /// 副文 —— 通常 `Text`; null = 不渲染 (节省行高, 列表更密)
  final Widget? subtitle;

  /// 右侧副信息 (时间/计数), 右对齐 + AppType.sm + textTertiary
  final Widget? meta;

  /// 最右操作 (箭头/按钮); 与 meta 同时给时 meta 在左, trailing 在右
  final Widget? trailing;

  /// 点击回调 —— 给 null 时整行不可点 (但仍渲染, 用于只读列表)
  final VoidCallback? onTap;

  /// 是否画底部分隔线 —— 默认 true (列表项风格); 单行卡片风格关掉
  final bool showDivider;

  /// 紧凑行高 (52 vs 60) —— 用于次级列表
  final bool dense;

  /// 内边距 —— 默认水平 pagePadding (16), 垂直 0 (行高由 minHeight 撑)
  final EdgeInsetsGeometry? padding;

  /// 整行背景色 —— 默认透明 (不要在行上铺卡片背景; 列表项就是列表项)
  final Color? backgroundColor;

  /// 文字 maxLines —— 默认 1 (title) / 1 (subtitle); 长标题/长副文场景可显式放宽
  final int titleMaxLines;
  final int subtitleMaxLines;

  const AppListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.meta,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.dense = false,
    this.padding,
    this.backgroundColor,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
  });

  double get _rowHeight => dense ? denseRowHeight : defaultRowHeight;

  /// 主文区: title + 副文纵向排 (副文为空则只画 title, 行高仍由 minHeight 撑)
  Widget _buildPrimaryColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DefaultTextStyle.merge(
          maxLines: titleMaxLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: AppType.md,
            fontWeight: AppWeight.medium,
            color: AppColors.textPrimary,
          ),
          child: title,
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpace.tightGap),
          DefaultTextStyle.merge(
            maxLines: subtitleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppType.sm,
              fontWeight: AppWeight.regular,
              color: AppColors.textSecondary,
            ),
            child: subtitle!,
          ),
        ],
      ],
    );
  }

  /// 右侧区: meta (靠左) + trailing (靠右) —— 中间夹 inlineGap (8)
  Widget? _buildTrailingArea() {
    if (meta == null && trailing == null) return null;
    if (meta == null) return trailing;
    if (trailing == null) return meta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        DefaultTextStyle.merge(
          style: const TextStyle(
            fontSize: AppType.sm,
            color: AppColors.textTertiary,
          ),
          child: meta!,
        ),
        const SizedBox(width: AppSpace.inlineGap),
        trailing!,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dividerColor = t.dividerTheme.color ?? AppColors.divider;
    final dividerThickness = t.dividerTheme.thickness ?? AppSize.borderHairline;
    final dividerSpace = t.dividerTheme.space ?? AppSize.borderHairline;
    final rowHeight = _rowHeight;
    final outerPadding =
        padding ?? const EdgeInsets.symmetric(horizontal: AppSpace.pagePadding);
    final leadingSize = AppSize.avatarMd; // 仅用于 divider 缩进估计 (44 + 8 = 52)

    // 主体 Row
    final Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          const SizedBox(width: AppSpace.inlineGap),
        ],
        Expanded(child: _buildPrimaryColumn()),
        if (_buildTrailingArea() != null) ...<Widget>[
          const SizedBox(width: AppSpace.inlineGap),
          _buildTrailingArea()!,
        ],
      ],
    );

    final Widget constrained = ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowHeight),
      child: Padding(
        padding: outerPadding,
        child: content,
      ),
    );

    final Widget withBackground = backgroundColor == null
        ? constrained
        : ColoredBox(color: backgroundColor!, child: constrained);

    final Widget withDivider = !showDivider
        ? withBackground
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              withBackground,
              // 有 leading 时分隔线左缩进到 leading 之后 (iOS/微信的成熟做法)
              // 缩进 = leadingSize(44) + inlineGap(8) = 52
              // leading 为 null 时整行贯通
              Padding(
                padding: EdgeInsets.only(
                  left: leading == null ? 0 : leadingSize + AppSpace.inlineGap,
                  right: AppSpace.s0,
                ),
                child: Divider(
                  height: dividerSpace,
                  thickness: dividerThickness,
                  color: dividerColor,
                ),
              ),
            ],
          );

    // 可点 / 不可点 —— 用 InkWell 统一涟漪 (直角, 列表行本来就该是直角的;
    // 若以后整行铺满再换 AppRadius)。不可点时不包 InkWell, 避免多余 hit test。
    if (onTap == null) return withDivider;
    return Material(
      color: backgroundColor ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // 直角 + 全宽 —— 列表行就该是直角的
        borderRadius: BorderRadius.circular(AppRadius.r0),
        child: withDivider,
      ),
    );
  }
}
