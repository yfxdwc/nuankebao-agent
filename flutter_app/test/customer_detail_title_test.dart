// ============================================
// 客户详情页 —— 顶栏标题 (主人 2026-09-24 拍)
// ============================================
// 诉求原话: 「顶行的『客户详情』改成变量，显示当前客户的姓名」
//
// 守什么:
//   ① 数据就绪 → 顶栏是**客户姓名**, 不再是写死的「客户详情」
//   ② 还没拿到数据 → 回落「客户详情」(顶栏不能空一块)
//   ③ 超长姓名 → 单行省略, 不溢出 (中文姓名+门店前缀很容易超)
//
// 为什么只 override 一个 provider 就能测:
//   标题只依赖 `customerDetailProvider`; 其余 provider (养生记录/洞察/归属/AI…)
//   各自失败只影响自己那块 section (页面都做了错误/空态降级), **AppBar 一定会渲染**。
//   这样不必 mock 十几个 provider 就守住标题逻辑。
//
// ⚠ 必须带真主题 (AGENTS §5: 不带主题走 Flutter 默认样式, 测不出"主题顶掉默认样式"类 bug)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/screens/customer_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Customer _customer(String name) => Customer(
      id: '798',
      name: name,
      phone: '13800001111',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

/// @param name null = 数据一直不返回 (模拟加载中)
Future<void> _pump(WidgetTester tester, String? name) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      customerDetailProvider('798').overrideWith((ref) async {
        if (name == null) return Completer<Customer>().future; // 永不完成
        return _customer(name);
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: const CustomerDetailPage(customerId: '798'),
    ),
  ));
}

void main() {
  testWidgets('① 数据就绪 → 顶栏显示客户姓名, 不再写死「客户详情」', (tester) async {
    await _pump(tester, '演示-蒋金娣');
    // ⚠ 不用 pumpAndSettle: 页面上没 mock 的 provider (养生记录/洞察/AI…) 在测试里
    //   拿不到网络 → 一直转圈 → 无限动画 → pumpAndSettle 永不返回。
    //   标题只依赖 customerDetailProvider, 有界 pump 足够。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // AppBar 里应该有这个名字
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('演示-蒋金娣'),
      ),
      findsOneWidget,
    );
    // 且不能再有写死的「客户详情」
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('客户详情'),
      ),
      findsNothing,
    );
  });

  testWidgets('② 加载中 → 回落「客户详情」(顶栏不空一块)', (tester) async {
    await _pump(tester, null);
    await tester.pump(); // 不用 pumpAndSettle: future 永不完成
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('客户详情'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('③ 超长姓名 → 单行 + 省略号, 不溢出', (tester) async {
    const longName = '演示-某某某大健康养生会所旗舰店VIP客户蒋金娣女士';
    await _pump(tester, longName);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final title = tester.widget<Text>(
      find.descendant(of: find.byType(AppBar), matching: find.text(longName)),
    );
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    // 有 overflow 的话 flutter_test 会直接抛异常 —— 跑到这里没抛就是没溢出
    expect(tester.takeException(), isNull);
  });
}
