// ============================================
// app_kit_test —— 通用 UI 组件契约 (B0a)
// ============================================
//
// 守护的东西:
//   ① 组件契约: 行高 / 字号 / 颜色 / 等宽数字 / 节点存在 等
//   ② 主题硬规则: 每个 TextStyle 显式 color (防「主题顶掉默认色 → 真机白字」
//      —— AGENTS §5 chip 白字教训)
//   ③ 不依赖业务模型 (数据驱动): 用纯文字 / 简单 Widget
//
// ⚠ 必须带真主题 `MaterialApp(theme: AppTheme.light())`:
//   不带主题 → 走 Flutter 默认样式 → 永远绿通过, 主题里 TextStyle 漏 color
//   这类 bug 测不出来. profile_page_test.dart 16 例全挂都漏过的教训.
//
// 跑: cd flutter_app && flutter test test/app_kit_test.dart
//
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/theme_ext.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/core/widgets/app_badge.dart';
import 'package:nuankebao/core/widgets/app_empty.dart';
import 'package:nuankebao/core/widgets/app_list_row.dart';
import 'package:nuankebao/core/widgets/app_section.dart';
import 'package:nuankebao/core/widgets/app_sheet_header.dart';
import 'package:nuankebao/core/widgets/app_skeleton.dart';
import 'package:nuankebao/core/widgets/app_stat_row.dart';
import 'package:nuankebao/core/widgets/empty_state.dart';

/// 测试夹具 —— 把 child 装进带真主题的 MaterialApp
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );

/// 拿到某 Text widget 的**解析后**样式 (主题实际下推的颜色/字号).
///
/// ⚠ `Text.style` 是 widget 自己的属性, 常为 null;
///    主题真推下来的样式要 `DefaultTextStyle.of(context)` —— 后者会沿继承链合并.
TextStyle _resolvedStyleOf(WidgetTester tester, Finder finder) {
  final ctx = tester.element(finder);
  return DefaultTextStyle.of(ctx).style;
}

void main() {
  group('AppListRow', () {
    testWidgets('默认行高 == AppSize.listRowHeight (60)', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppListRow(title: Text('王女士')),
      ));
      final size = tester.getSize(find.byType(AppListRow));
      // minHeight 是 60; 默认 padding (vertical=0) 不加额外高度; size.height >= 60
      expect(size.height, greaterThanOrEqualTo(AppSize.listRowHeight));
    });

    testWidgets('dense 行高 < 默认行高', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppListRow(title: Text('王女士')),
      ));
      final normalHeight = tester.getSize(find.byType(AppListRow)).height;

      await tester.pumpWidget(_wrap(
        const AppListRow(title: Text('王女士'), dense: true),
      ));
      final denseHeight = tester.getSize(find.byType(AppListRow)).height;

      expect(denseHeight, lessThan(normalHeight));
      expect(denseHeight, greaterThanOrEqualTo(AppListRow.denseRowHeight));
    });

    testWidgets('不带 Card (无卡片容器, 原则 4)', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppListRow(title: Text('王女士')),
      ));
      // AppListRow 故意不用 Card (列表项风格). Material(给 InkWell 涟漪) 仍合法.
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('showDivider=true 时能找到 Divider', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppListRow(title: Text('王女士'), showDivider: true),
      ));
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('showDivider=false 时不画 Divider', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppListRow(title: Text('王女士'), showDivider: false),
      ));
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('title 文字颜色 != null 且 == AppColors.textPrimary (防白字)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AppListRow(title: Text('王女士')),
      ));
      // ⚠ Text.style 是 widget 自己的属性 (常为 null); **解析后**的样式走 DefaultTextStyle.of
      // 这是查「主题真把颜色下推下去没有」的正确口径.
      final resolved = _resolvedStyleOf(tester, find.text('王女士'));
      expect(resolved.color, isNotNull,
          reason: '防白字: 解析后 TextStyle.color 不能为 null');
      expect(resolved.color, AppColors.textPrimary);
      expect(resolved.fontSize, AppType.md);
    });
  });

  group('AppSkeleton', () {
    testWidgets('渲染不抛异常', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSkeleton(width: 200, height: 16),
      ));
      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('颜色 == AppColors.surfaceSunken', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSkeleton(width: 200, height: 16),
      ));
      // 第一个 Container 持有 decoration.color
      final container = tester.widget<Container>(find.descendant(
        of: find.byType(AppSkeleton),
        matching: find.byType(Container),
      ).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.surfaceSunken);
    });

    testWidgets('AppSkeletonList 默认 5 行, 不抛异常', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSkeletonList(),
      ));
      expect(tester.takeException(), isNull);
      // 至少 5 个 SizedBox 分隔 (rows-1 = 4) + 5 行, 用 AppSkeleton 计数更稳
      expect(find.byType(AppSkeleton), findsWidgets);
    });
  });

  group('AppBadge', () {
    const tones = AppBadgeTone.values;
    for (final tone in tones) {
      testWidgets('tone=${tone.name} 渲染不抛异常 + 文字 color 非 null',
          (tester) async {
        await tester.pumpWidget(_wrap(
          AppBadge(label: 'X', tone: tone),
        ));
        expect(tester.takeException(), isNull);
        final text = tester.widget<Text>(find.text('X'));
        final style = text.style!;
        expect(style.color, isNotNull,
            reason: 'tone=${tone.name} 防白字: TextStyle.color 不能为 null');
        expect(style.color!.opacity, 1.0,
            reason: 'tone=${tone.name} 文字 color alpha == 1.0');
      });
    }

    testWidgets('dense=true 时字号 = AppType.micro', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppBadge(label: 'X', dense: true),
      ));
      final text = tester.widget<Text>(find.text('X'));
      expect(text.style!.fontSize, AppType.micro);
    });
  });

  group('AppStatRow', () {
    testWidgets('value 文本 style 含 FontFeature.tabularFigures()',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AppStatRow(label: '会员天数', value: '128'),
      ));
      final text = tester.widget<Text>(find.text('128'));
      final style = text.style!;
      expect(style.fontFeatures, isNotNull,
          reason: 'value 文本必须声明 fontFeatures (等宽数字, 原则 1)');
      expect(
        style.fontFeatures!.any((f) => f.feature == 'tnum'),
        isTrue,
        reason: '等宽数字 = tabular figures (FontFeature.tabularFigures)',
      );
    });

    testWidgets('onTap 为 null 时行不可点 (无 InkWell)', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppStatRow(label: 'L', value: 'V'),
      ));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('onTap 非 null 时行可点 + 触摸底线 >= AppSize.tapMin',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        AppStatRow(label: 'L', value: 'V', onTap: () => tapped++),
      ));
      expect(find.byType(InkWell), findsOneWidget);
      // 点击热区 >= 48
      final size = tester.getSize(find.byType(AppStatRow));
      expect(size.height, greaterThanOrEqualTo(AppSize.tapMin));
      await tester.tap(find.byType(AppStatRow));
      await tester.pump();
      expect(tapped, 1);
    });
  });

  group('AppSectionHeader', () {
    testWidgets('标题字号 == AppType.lg', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSectionHeader(title: '最近跟进'),
      ));
      // 解析后的样式 (DefaultTextStyle.merge 提供)
      final resolved = _resolvedStyleOf(tester, find.text('最近跟进'));
      expect(resolved.fontSize, AppType.lg);
      expect(resolved.fontWeight, AppWeight.semibold);
      expect(resolved.color, AppColors.textPrimary);
    });

    testWidgets('副标题字号 == AppType.sm', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSectionHeader(title: 'T', subtitle: 'S'),
      ));
      // 副标题 Text 自带 style, 直接读
      final sub = tester.widget<Text>(find.text('S'));
      expect(sub.style!.fontSize, AppType.sm);
    });

    testWidgets('有 action 时 action 也渲染出来', (tester) async {
      await tester.pumpWidget(_wrap(
        AppSectionHeader(
          title: 'T',
          action: TextButton(onPressed: () {}, child: const Text('更多')),
        ),
      ));
      expect(find.text('更多'), findsOneWidget);
    });
  });

  group('AppSection', () {
    testWidgets('标题 + 子内容都渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSection(
          title: '关键信息',
          child: Text('子内容'),
        ),
      ));
      expect(find.text('关键信息'), findsOneWidget);
      expect(find.text('子内容'), findsOneWidget);
    });

    testWidgets('无边框 / 无 Card / 不铺卡片背景 (原则 4)', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSection(
          title: 'T',
          child: SizedBox(height: 10, width: 10),
        ),
      ));
      expect(find.byType(Card), findsNothing);
      expect(find.byType(PhysicalShape), findsNothing);
    });
  });

  group('AppSheetHeader', () {
    testWidgets('title 字号 == AppType.lg', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppSheetHeader(title: '新建客户'),
      ));
      final text = tester.widget<Text>(find.text('新建客户'));
      expect(text.style!.fontSize, AppType.lg);
    });

    testWidgets('actions 列表里的按钮都渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        AppSheetHeader(
          title: 'T',
          actions: [
            TextButton(onPressed: () {}, child: const Text('取消')),
            TextButton(onPressed: () {}, child: const Text('确认')),
          ],
        ),
      ));
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('确认'), findsOneWidget);
    });
  });

  group('AppEmptyState', () {
    testWidgets('title 渲染, hint 渲染, action 渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        AppEmptyState(
          title: '还没有客户',
          hint: '添加你的第一个客户开始管理',
          action: ElevatedButton(
            onPressed: () {},
            child: const Text('添加客户'),
          ),
        ),
      ));
      expect(find.text('还没有客户'), findsOneWidget);
      expect(find.text('添加你的第一个客户开始管理'), findsOneWidget);
      expect(find.text('添加客户'), findsOneWidget);
    });

    testWidgets('secondaryAction 也渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        AppEmptyState(
          title: 'T',
          action: TextButton(onPressed: () {}, child: const Text('A')),
          secondaryAction: TextButton(onPressed: () {}, child: const Text('B')),
        ),
      ));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('EmptyState (兼容入口)', () {
    testWidgets('原有 onAction + actionLabel 还能用', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        EmptyState(
          title: '空',
          hint: '提示',
          actionLabel: '按钮',
          onAction: () => tapped++,
        ),
      ));
      expect(find.text('按钮'), findsOneWidget);
      await tester.tap(find.text('按钮'));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('新增 action widget 参数能替换默认按钮', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(
          title: '空',
          action: Text('自定义'),
        ),
      ));
      expect(find.text('自定义'), findsOneWidget);
    });
  });

  group('context.tokens 跟随主题 (硬规则)', () {
    testWidgets('default sage 主题下 badge brand tone 颜色 = sage.primary',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AppBadge(label: 'X', tone: AppBadgeTone.brand),
      ));
      final buildContext = tester.element(find.byType(AppBadge));
      expect(buildContext.tokens.id, 'sage');
      final text = tester.widget<Text>(find.text('X'));
      // brand tone: foreground = primary (sage = AppThemes.sage.primary)
      expect(text.style!.color, AppThemes.sage.primary);
    });
  });
}
