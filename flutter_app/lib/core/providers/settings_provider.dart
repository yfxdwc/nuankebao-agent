// ============================================
// 本地设置 (「我的」→ 显示设置)
// ============================================
// 存哪: shared_preferences (设备本地, 不上云)
//   —— 字号是"这台手机看着舒服"的偏好, 不该跟着账号走 (老人机/备用机各调各的)
//
// 为什么单独一个 provider 文件:
//   设置会被 app.dart (全局 textScaler) 和 「我的」页同时读 → 放 core/providers,
//   不放页面里, 免得页面互相 import
//
// 边界: 只放"本机偏好"; 跟账号/业务有关的一律走后端 (如显示名 = /api/me)
//       不引 codegen: 设置项是手写的少数字段, 用 freezed 反而绕

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 字号档位 (中老年用户最记不住"1.15 倍"这种话, 用档位名 + 样例字号)
enum AppFontSize {
  standard,
  large,
  xlarge;

  /// 倍率 —— 保守取值: AppTheme 字号本来就比 Material 默认大 (18pt vs 14pt),
  /// 再叠太多会挤破固定高度的按钮 (56/64pt), 1.3 是实测不炸布局的上限
  double get scale => switch (this) {
        AppFontSize.standard => 1.0,
        AppFontSize.large => 1.15,
        AppFontSize.xlarge => 1.3,
      };

  String get label => switch (this) {
        AppFontSize.standard => '标准',
        AppFontSize.large => '大',
        AppFontSize.xlarge => '特大',
      };

  /// 设置页样例文字 (让用户在选之前就看到效果)
  String get sample => switch (this) {
        AppFontSize.standard => '客户 王女士',
        AppFontSize.large => '客户 王女士',
        AppFontSize.xlarge => '客户 王女士',
      };

  static AppFontSize fromName(String? raw) {
    for (final v in AppFontSize.values) {
      if (v.name == raw) return v;
    }
    return AppFontSize.standard;
  }
}

/// 本机偏好快照 (不可变)
class AppSettings {
  final AppFontSize fontSize;

  const AppSettings({this.fontSize = AppFontSize.standard});

  double get fontScale => fontSize.scale;

  AppSettings copyWith({AppFontSize? fontSize}) =>
      AppSettings(fontSize: fontSize ?? this.fontSize);
}

/// shared_preferences 实例 (main() 里 override)
///
/// 不在 provider 里 `await SharedPreferences.getInstance()` 的原因:
/// 那样首帧拿不到设置 → 先按标准字号画一屏, 再跳成特大 = 闪一下。
/// 在 main() 里 await 完再 runApp, 首帧就是用户选的档位。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider 必须在 main() 里 override '
    '(见 flutter_app/lib/main.dart)',
  ),
);

const _kFontSizeKey = 'settings.font_size';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      fontSize: AppFontSize.fromName(prefs.getString(_kFontSizeKey)),
    );
  }

  Future<void> setFontSize(AppFontSize size) async {
    if (state.fontSize == size) return;
    state = state.copyWith(fontSize: size);
    await ref.read(sharedPreferencesProvider).setString(_kFontSizeKey, size.name);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
