// ============================================
// AppBadge —— 统一状态徽章 (色 + 文字双编码, 色弱也能分)
// ============================================
//
// 设计依据 (docs/ui-principles.md):
//   - 原则 5: 颜色是信号, 一屏饱和色 ≤ 3 → 徽章只用 7 种 tone, 一屏别堆
//   - 反 vibe: 不做花哨渐变 / 阴影
//
// tone 列表 (7 种) —— 对应语义令牌:
//   neutral  → badgeNeutral + badgeNeutralSurface     (灰, 默认)
//   brand    → primary    + primarySurface             (品牌色)
//   success  → success    + successSurface             (绿, 完成/确认)
//   warning  → warning    + warningSurface             (黄, 注意/待办)
//   danger   → danger     + dangerSurface              (红, 错误/紧急)
//   info     → info       + infoSurface                (蓝, 提示)
//   gold     → memberGold + memberGoldSurface          (金, 会员)
//
// 视觉:
//   - 圆角 AppRadius.badge (4)
//   - 字号 AppType.xs (12)
//   - 水平内边距 AppSpace.s6 (6) / 垂直 AppSpace.s2 (2)
//   - 标签字重 medium, **color 显式写** (防白字事故)
//   - dense=true 时水平 s4 / 垂直 0 / 字号 = micro (11)
//
// ⚠ 现有 franchise_chip.dart **不**改 —— B2 批次再迁移它; 这里只在注释里
//   说明一句, 不动它的实现 (避免本批影响业务页)
//
import 'package:flutter/material.dart';

import '../theme/theme_ext.dart';
import '../theme/tokens.g.dart';

/// 7 种 tone, 与 AppColors 语义槽一一对应
enum AppBadgeTone {
  neutral,
  brand,
  success,
  warning,
  danger,
  info,
  gold,
}

class AppBadge extends StatelessWidget {
  final String label;
  final AppBadgeTone tone;
  final bool dense;

  /// 自定义前景色 (覆盖 tone 的默认前景) —— 慎用, 通常不需要
  final Color? foreground;

  /// 自定义背景色 (覆盖 tone 的默认背景) —— 慎用, 通常不需要
  final Color? background;

  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.dense = false,
    this.foreground,
    this.background,
  });

  /// 取 tone 对应的 (前景, 背景) —— 用 context.tokens 跟随换肤 (即使中性槽
  /// 跨主题不变, 也走 tokens 路径统一)
  (Color, Color) _resolveColors(BuildContext context) {
    final t = context.tokens;
    switch (tone) {
      case AppBadgeTone.brand:
        return (t.primary, t.primarySurface);
      case AppBadgeTone.success:
        return (t.success, t.successSurface);
      case AppBadgeTone.warning:
        return (t.warning, t.warningSurface);
      case AppBadgeTone.danger:
        return (t.danger, t.dangerSurface);
      case AppBadgeTone.info:
        return (t.info, t.infoSurface);
      case AppBadgeTone.gold:
        return (t.memberGold, t.memberGoldSurface);
      case AppBadgeTone.neutral:
        return (t.badgeNeutral, t.badgeNeutralSurface);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _resolveColors(context);
    final fg = foreground ?? colors.$1;
    final bg = background ?? colors.$2;
    final padding = dense
        ? const EdgeInsets.symmetric(
            horizontal: AppSpace.s4,
            vertical: AppSpace.s0,
          )
        : const EdgeInsets.symmetric(
            horizontal: AppSpace.s6,
            vertical: AppSpace.s2,
          );
    final fontSize = dense ? AppType.micro : AppType.xs;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: AppWeight.medium,
          // ⚠ 必显式写 color, 不写会被 TextTheme.bodyMedium 默认色顶掉 → 真机白字
          color: fg,
        ),
      ),
    );
  }
}
