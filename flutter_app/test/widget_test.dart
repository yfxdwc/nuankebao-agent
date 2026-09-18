// 暖客宝 app smoke test
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nuankebao/app.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';

void main() {
  testWidgets('暖客宝 app smoke test', (WidgetTester tester) async {
    // 本机设置走 shared_preferences, 测试里用 mock 值
    // (2026-09-18 加字号设置后, 不 override 会在 build 时抛 UnimplementedError)
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // main.dart 里 NuankeBaoApp 外面包了 ProviderScope (+ sharedPreferences override), 测试保持一致
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const NuankeBaoApp(),
      ),
    );
    expect(find.text('暖客宝'), findsOneWidget);
  });
}