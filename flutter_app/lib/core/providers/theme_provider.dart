// ============================================
// 主题 (换肤) provider —— 运行时可切多主题
// ============================================
//
// 设计边界:
//   `settings_provider.dart` 管的是「功能偏好」(字号档 / 提醒开关);
//   这里管的是「外观令牌」。分开放的理由: 令牌系统的消费方 (context.tokens / AppTheme)
//   都在 core/theme, 让它们跟 settings 互相 import 会把依赖绕起来。
//
// 持久化: shared_preferences (`settings.theme_id`), 与字号档同级 —— 都是"这台手机"的事。
//
// ⚠ 换肤只改**颜色**; 间距/字号/圆角是尺度 (AppSpace/AppType/AppRadius), 不随主题变。
//   要整体调密度 → 改 design-tokens.json 的 scales, 重新 tokens:build。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.g.dart';
import 'settings_provider.dart';

const _kThemeIdKey = 'settings.theme_id';

/// 当前主题 id (存的是字符串而不是 AppTokens: 便于持久化 + 版本容错)
class ThemeIdNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    // resolve() 会把"旧版本遗留的未知 id"安全地回落到默认主题
    return AppThemes.resolve(prefs.getString(_kThemeIdKey)).id;
  }

  Future<void> setTheme(String id) async {
    final next = AppThemes.resolve(id).id;
    if (state == next) return;
    state = next;
    await ref.read(sharedPreferencesProvider).setString(_kThemeIdKey, next);
  }

  /// 恢复默认 (设置页「恢复默认外观」用)
  Future<void> reset() => setTheme(AppThemes.defaultId);
}

final themeIdProvider =
    NotifierProvider<ThemeIdNotifier, String>(ThemeIdNotifier.new);

/// 当前主题的完整令牌 —— `app.dart` 拿它建 ThemeData
final activeTokensProvider = Provider<AppTokens>(
  (ref) => AppThemes.resolve(ref.watch(themeIdProvider)),
);

/// 按分组列出主题 (设置页渲染用: 品牌 / 季节)
final themeGroupsProvider = Provider<Map<String, List<AppTokens>>>((ref) {
  final out = <String, List<AppTokens>>{};
  for (final t in AppThemes.all) {
    out.putIfAbsent(t.group, () => <AppTokens>[]).add(t);
  }
  return out;
});
