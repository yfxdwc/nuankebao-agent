// 本机设置单测 (「我的」→ 显示与存储 → 字号)
// 关注点: 默认值 / 切换立即生效 / 真落盘 (重开 App 还在)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _containerWith(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('没有存过 → 默认标准字号', () async {
    final container = await _containerWith({});
    expect(container.read(settingsProvider).fontSize, AppFontSize.standard);
    expect(container.read(settingsProvider).fontScale, 1.0);
  });

  test('存过特大 → 启动就是特大 (不会先画标准再跳)', () async {
    final container = await _containerWith({'settings.font_size': 'xlarge'});
    expect(container.read(settingsProvider).fontSize, AppFontSize.xlarge);
    expect(container.read(settingsProvider).fontScale, 1.3);
  });

  test('脏数据 (手改 / 老版本残留) → 退回标准', () async {
    final container = await _containerWith({'settings.font_size': 'huge'});
    expect(container.read(settingsProvider).fontSize, AppFontSize.standard);
  });

  test('切换字号立即生效 + 落盘', () async {
    final container = await _containerWith({});
    await container.read(settingsProvider.notifier).setFontSize(AppFontSize.large);
    expect(container.read(settingsProvider).fontSize, AppFontSize.large);
    expect(container.read(settingsProvider).fontScale, 1.15);

    // 落盘: 同一个 prefs 再开一个 container (模拟重启)
    final prefs = await SharedPreferences.getInstance();
    final reopened = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(reopened.dispose);
    expect(reopened.read(settingsProvider).fontSize, AppFontSize.large);
  });

  test('字号档位: 单调递增 + 上限 1.3 (再大布局会炸)', () {
    expect(AppFontSize.standard.scale, 1.0);
    expect(AppFontSize.large.scale, greaterThan(AppFontSize.standard.scale));
    expect(AppFontSize.xlarge.scale, greaterThan(AppFontSize.large.scale));
    expect(AppFontSize.xlarge.scale, lessThanOrEqualTo(1.3));
    // 每档都有中文名 (UI 不显示枚举名)
    for (final v in AppFontSize.values) {
      expect(v.label, isNotEmpty);
      expect(v.label, isNot(contains('AppFontSize')));
    }
  });

  test('没 override sharedPreferencesProvider → 明确报错 (不是静默用默认值)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(settingsProvider),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
