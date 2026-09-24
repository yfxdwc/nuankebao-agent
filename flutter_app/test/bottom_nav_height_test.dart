// ============================================
// 底部导航栏高度契约测试 (2026-09-24 主人拍「压缩一些」)
// ============================================
// 守护的东西:
//   ① M3 NavigationBar **默认 80pt** (SDK 硬编码), 不覆写就白占 3 行列表空间 →
//      断言主题里确实覆写成令牌值 (谁把 height 删了/改错就红)
//   ② 高度不得低于热区下限 48 (docs/ui-principles.md §3.1) —— 压缩不能变成难点
//   ③ 56pt 下**不溢出** (icon 24 + 标签 13 塞得进) —— M3 内部是 Column,
//      高度给太小会 RenderFlex overflow; 这类问题真机上才看得出, 用测试挡住
//   ④ 标签/图标在选中态与未选中态**都有显式 color** (AGENTS §5 白字教训)
//
// 跑: cd flutter_app && flutter test test/bottom_nav_height_test.dart
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';

/// 与 app_router.dart 的 _MainShell 同构的三 tab 底栏
Widget _shellWithNavBar() => Scaffold(
      body: const SizedBox.shrink(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: '客户',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: '沙龙',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );

void main() {
  group('令牌与主题', () {
    test('navBarHeight 令牌已从 design-tokens.json 生成', () {
      expect(AppSize.navBarHeight, 56.0);
    });

    test('navBarHeight 不得低于热区下限 (压缩 ≠ 难点)', () {
      expect(AppSize.navBarHeight, greaterThanOrEqualTo(AppSize.tapMin));
    });

    test('主题里真的覆写了 M3 默认的 80pt', () {
      final theme = AppTheme.light(AppThemes.sage);
      expect(theme.navigationBarTheme.height, AppSize.navBarHeight);
      // 反向断言: 万一有人删了覆写, M3 会回落 80
      expect(theme.navigationBarTheme.height, isNot(80.0));
    });
  });

  group('渲染 (真主题)', () {
    testWidgets('375×812 下底栏实际高度 == 令牌值', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(AppThemes.sage),
        home: _shellWithNavBar(),
      ));
      await tester.pumpAndSettle();

      final h = tester.getSize(find.byType(NavigationBar)).height;
      expect(h, AppSize.navBarHeight,
          reason: '底栏高度必须 == AppSize.navBarHeight (改前是 M3 默认 80)');
    });

    testWidgets('56pt 不溢出 (M3 内部 Column: 图标 + 标签要塞得下)', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(AppThemes.sage),
        home: _shellWithNavBar(),
      ));
      await tester.pumpAndSettle();

      // 溢出会以 FlutterError 形式被 tester 捕获 → takeException 非空即失败
      expect(tester.takeException(), isNull);
      expect(find.text('客户'), findsOneWidget);
      expect(find.text('沙龙'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
    });

    testWidgets('标签与图标在选中/未选中态都有显式 color (防真机白字)', (tester) async {
      final theme = AppTheme.light(AppThemes.sage);
      final nav = theme.navigationBarTheme;

      for (final states in [
        <WidgetState>{},
        <WidgetState>{WidgetState.selected},
      ]) {
        final label = nav.labelTextStyle?.resolve(states);
        final icon = nav.iconTheme?.resolve(states);
        expect(label?.color, isNotNull,
            reason: '$states 下标签 color 为 null → 真机兜底白色 (AGENTS §5)');
        expect(icon?.color, isNotNull, reason: '$states 下图标 color 为 null');
        expect(label?.fontSize, AppType.sm);
      }

      // 选中态用品牌色 + semibold, 未选中用次级文字色 (层级靠对比, 不靠放大)
      final sel = nav.labelTextStyle!.resolve({WidgetState.selected})!;
      final unsel = nav.labelTextStyle!.resolve(<WidgetState>{})!;
      expect(sel.fontWeight, AppWeight.semibold);
      expect(unsel.fontWeight, AppWeight.regular);
      expect(sel.color, isNot(unsel.color));
    });
  });
}
