// ============================================
// B2 风格契约测试 —— 验「换装到位」(2026-09-25)
//
// 守护什么:
//   ① 真主题渲染不抛异常 (验收换装没引入新 bug)
//   ② 结构断言: 换装模块首屏存在关键新组件
//
// ⚠ 必须带真主题 AppTheme.light —— 不带主题走 Flutter 默认样式,
//   主题里 TextStyle 漏 color 这类 bug 永远测不出来 (AGENTS §5 chip 白字教训).
//
// 跑: flutter test test/b2_style_contract_test.dart
//
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/widgets/app_list_row.dart';
import 'package:nuankebao/core/widgets/app_section.dart';
import 'package:nuankebao/modules/auth/screens/login_screen.dart';
import 'package:nuankebao/modules/auth/screens/register_screen.dart';
import 'package:nuankebao/modules/follow_up/screens/follow_ups_page.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

void main() {
  group('B2 换装模块 — 真主题渲染冒烟', () {
    testWidgets('FollowUpsPage 渲染不抛异常 (真主题下)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const FollowUpsPage(),
          ),
        ),
      );
      await tester.pump();
      // 不抛异常 + 显示标题 (loading/error/data 三态之一)
      expect(find.text('跟进待办'), findsOneWidget);
      // 让未完成的 Timer (搜孯 debounce) 走完, 不留 pending assertions
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('LoginScreen 渲染不抛异常 (真主题下)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('暖客宝'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
    });

    testWidgets('RegisterScreen 渲染不抛异常 (真主题下)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const RegisterScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('注册'), findsOneWidget);
    });
  });

  group('B2 换装模块 — 结构断言', () {
    testWidgets('AppListRow 在真主题下渲染不抛 + 行高 >= 60', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppListRow(
          title: Text('标题'),
          subtitle: Text('副文'),
        ),
      ));
      expect(find.text('标题'), findsOneWidget);
      expect(find.text('副文'), findsOneWidget);
      // 行高 >= AppListRow.defaultRowHeight (60)
      final size = tester.getSize(find.byType(AppListRow));
      expect(size.height, greaterThanOrEqualTo(60));
    });

    testWidgets('AppSection 渲染标题与子内容', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSection(
          title: '区块',
          child: Text('内容'),
        ),
      ));
      expect(find.text('区块'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
    });
  });
}
