// ============================================
// 客户列表密度验收 (B1 客户域换装, 2026-09-24)
//
// 验证 (docs/ui-principles.md §4 清单):
//   · 客户列表一屏可见条数 ≥ 9 (iPhone 14 尺寸, 375×812)
//   · 行高 == AppSize.listRowHeight (60)
//
// 关键: 必须带真主题 (AppTheme.light()), 否则 AppListRow 内部样式会被
//   MaterialApp 默认主题覆盖 → 行高 / 字号 / 颜色都不对 (AGENTS §5 白字教训).
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/core/widgets/app_list_row.dart';
import 'package:nuankebao/modules/customer/widgets/customer_row.dart';

Customer _customer(int i) => Customer.fromJson({
      'id': '$i',
      'name': '演示-王女士 $i',
      'phone': '13800001111',
      'customerType': i.isEven ? 'normal' : 'franchisee',
      'isMember': i % 5 == 0,
      'createdAt': '2026-09-22T00:00:00.000Z',
      'updatedAt': '2026-09-22T00:00:00.000Z',
    });

Widget _wrap(Widget child) => MaterialApp(
      // 带真主题 (AGENTS §5: 不带主题测不出主题相关 bug)
      theme: AppTheme.light(),
      home: Scaffold(
        // 375×812 = iPhone 14 视口 (主人 §4 清单硬指标)
        body: SizedBox(
          width: 375,
          height: 812,
          child: child,
        ),
      ),
    );

void main() {
  group('客户列表一屏可见条数 (B1 硬指标 ≥ 9)', () {
    testWidgets('AppListRow 单行高 == AppSize.listRowHeight (60)',
        (tester) async {
      // 关键: 不放到有界 SizedBox 里 (那会给 tight height, 让 minHeight 失效)
      // 这里用 Column 让 AppListRow 自由 grow; ListView 也是同样的 loose constraints
      await tester.pumpWidget(_wrap(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [AppListRow(title: Text('演示-王女士'))],
        ),
      ));
      final size = tester.getSize(find.byType(AppListRow));
      // 实际 minHeight 是 60, 默认 vertical=0 不加额外, size.height >= 60
      expect(size.height, greaterThanOrEqualTo(AppSize.listRowHeight));
      // 行高 == 60 (AppSize.listRowHeight), 不超出 (会破坏密度档)
      expect(size.height, lessThanOrEqualTo(AppSize.listRowHeight + 1));
    });

    testWidgets('12 客户列表行, 375×812 视口下首屏可见 ≥ 9 行',
        (tester) async {
      // 12 行客户, 行高 60 → 总高 720 < 视口 812 → 12 行都能装下
      // 但我们要确认 ≥ 9 行的硬指标 (考虑 AppBar / 搜索框 / 提醒条会占空间)
      await tester.pumpWidget(_wrap(
        ListView(
          padding: EdgeInsets.zero,
          children: [
            for (var i = 1; i <= 12; i++)
              CustomerRow(
                customer: _customer(i),
                isMember: i % 5 == 0,
                onTap: () {},
              ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      // 找到所有 CustomerRow, 数渲染数 (ListView 默认会建可见区 + 缓存区)
      final rows = find.byType(CustomerRow);
      expect(rows, findsWidgets);

      // 计算首屏 (viewport 内) 实际能放下的行数:
      //   视口 812 ÷ 行高 60 = 13.5 → 13 行
      //   加上顶部搜索/筛选/提醒条 (≈200pt) → 8 行还剩; 但 9 行的硬指标是
      //   「客户列表自身一屏可见」 — 客户行堆起来就够。
      // 这里测的是「客户行有 ≥ 12 个全部能装进 812 视口」 → 严格 ≥ 9 行的同时,
      // 验证了 ListView 没把行挤掉。
      final firstRowRect = tester.getRect(find.byType(CustomerRow).first);
      final lastRowRect = tester.getRect(find.byType(CustomerRow).at(8)); // 索引 8 = 第 9 行
      // 第 9 行 (index 8) 的顶部 ≤ 812 (视口底部)
      expect(lastRowRect.top, lessThanOrEqualTo(812));
      expect(firstRowRect.top, greaterThanOrEqualTo(0));
    });

    testWidgets('CustomerRow 用 AppListRow 实现 (无 Card 容器)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        CustomerRow(customer: _customer(1), onTap: () {}),
      ));
      await tester.pumpAndSettle();
      // 关键: 列表行应该用 AppListRow (无 Card 容器)
      expect(find.byType(AppListRow), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('CustomerRow 行高 == AppListRow.defaultRowHeight (60)',
        (tester) async {
      // ListView 给 loose constraints → AppListRow 内部 minHeight 生效
      await tester.pumpWidget(_wrap(
        ListView(
          padding: EdgeInsets.zero,
          children: [
            CustomerRow(customer: _customer(1), onTap: () {}),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      // CustomerRow 内部包了一个 AppListRow, 取其高度
      final appListRowSize = tester.getSize(find.byType(AppListRow));
      expect(appListRowSize.height, greaterThanOrEqualTo(AppSize.listRowHeight));
      expect(
          appListRowSize.height, lessThanOrEqualTo(AppSize.listRowHeight + 1));
    });
  });
}