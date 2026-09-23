// ============================================
// 运行时主题上下文 (换肤的唯一正确入口)
// ============================================
//
// 为什么需要这层:
//   `AppThemes.sage.primary` 是 **编译期常量** —— 运行时不随用户选择变化。
//   只有从 `Theme.of(context)` 取的令牌才跟着 `MaterialApp.theme` 走。
//   业务代码一律写 `context.tokens.primary`, 不写 `AppThemes.sage.primary`。
//
// 用法:
//   `final t = context.tokens;`
//   `Container(color: t.primarySurface)`
//   `Text('客户', style: TextStyle(color: t.textSecondary, fontSize: AppType.sm))`
//
// 尺度 (间距/字号/圆角) **不随主题变化**, 直接用 `AppSpace.s16` / `AppType.md` 常量即可。
//
// ⚠ 主题里每个组件 TextStyle 都必须显式写 color (主人 2026-09-22 教训):
//   Flutter 拿组件的样式是 `theme.xxx ?? defaults.xxx` —— 只要我们的非空样式漏了 color,
//   就把默认色整个顶掉, 文字变白/黑而看不见。真机 APK 才看得出来 (web CanvasKit 兜底色不同)。

import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// 令牌挂到 ThemeData 上的载体 (让 `Theme.of(context)` 能取到当前主题令牌)
class AppTokensTheme extends ThemeExtension<AppTokensTheme> {
  final AppTokens tokens;

  const AppTokensTheme(this.tokens);

  @override
  AppTokensTheme copyWith({AppTokens? tokens}) =>
      AppTokensTheme(tokens ?? this.tokens);

  /// 不做插值: 换肤是离散切换 (两套品牌色的中间态没有意义, 还会出现脏色)
  @override
  AppTokensTheme lerp(ThemeExtension<AppTokensTheme>? other, double t) =>
      t < 0.5 ? this : (other is AppTokensTheme ? other : this);

  @override
  bool operator ==(Object other) =>
      other is AppTokensTheme && other.tokens.id == tokens.id;

  @override
  int get hashCode => tokens.id.hashCode;
}

/// `context.tokens` —— 当前主题的语义令牌
extension AppTokensContextX on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokensTheme>()?.tokens ??
      AppThemes.resolve(null);

  /// 当前主题 id (设置页高亮选项用)
  String get themeId => tokens.id;
}
