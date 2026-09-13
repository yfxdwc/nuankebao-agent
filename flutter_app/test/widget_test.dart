// 暖客宝 app smoke test
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/app.dart';

void main() {
  testWidgets('暖客宝 app smoke test', (WidgetTester tester) async {
    // main.dart 里 NuankeBaoApp 外面包了 ProviderScope, 测试保持一致
    await tester.pumpWidget(
      const ProviderScope(child: NuankeBaoApp()),
    );
    expect(find.text('暖客宝'), findsOneWidget);
  });
}