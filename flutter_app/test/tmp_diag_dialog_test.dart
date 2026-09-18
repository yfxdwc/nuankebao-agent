import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/customer/screens/customers_page.dart';

void main() {
  testWidgets('diag: 生日月/日 弹层内容', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const CustomerFormPage()),
    ]);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('生日'), 200, scrollable: scroll);
    await tester.pump(const Duration(milliseconds: 200));
    print('DIAG 生日区可见文本: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((d) => d != null).take(30).toList()}');

    await tester.tap(find.text('月 不清楚'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    print('DIAG 月份弹层文本: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((d) => d != null).take(20).toList()}');
  });
}
