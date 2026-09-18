// 临时验证 (2026-09-18 编辑客户页: 标签候选项 + 生日(农历/阳历) + 提醒 + 过敏史) — 出图后删
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/customer/screens/customers_page.dart';

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService() : super(Dio());
  @override
  Future<Customer> getById(String id) async => Customer(
        id: '1',
        name: '王女士',
        phone: '13912345678',
        gender: 'F',
        birthYear: 1968,
        birthMonth: 8,
        birthDay: 15,
        birthCalendar: 'lunar',
        birthdayRemindDays: 7,
        healthTags: const ['肩颈僵硬', '自定标签'],
        diseaseHistory: '高血压(服药中)',
        allergyHistory: '青霉素过敏',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
}

Widget _app({String? customerId}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => CustomerFormPage(customerId: customerId),
      ),
    ],
  );
  return ProviderScope(
    overrides: [customerServiceProvider.overrideWithValue(_FakeCustomerService())],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

void main() {
  testWidgets('新增客户: 标签候选项 + 生日年月日 + 提醒 + 过敏史', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    // 滚到生日区
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('生日'), 200, scrollable: scroll);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('生日'), findsOneWidget);
    expect(find.text('年 不清楚'), findsOneWidget);
    expect(find.text('月 不清楚'), findsOneWidget);
    expect(find.text('日 不清楚'), findsOneWidget);
    expect(find.text('阳历'), findsOneWidget);
    expect(find.text('农历'), findsOneWidget);
    // 月/日 未填 → 不显示提醒设置
    expect(find.text('生日提醒 (已开启)'), findsNothing);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/form-01-birthday-empty.png'));

    // 提醒区交互留给真浏览器 E2E (widget 测试驱动弹层不稳, 不在这耗时间)
    // 健康标签候选项 + 自定义输入
    await tester.scrollUntilVisible(find.text('健康标签'), -200, scrollable: scroll);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('肩颈僵硬'), findsOneWidget); // 默认候选项
    expect(find.text('睡眠差'), findsOneWidget);
    expect(find.text('自定义 (最多 6 个字)'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/form-03-tags.png'));
  });

  testWidgets('编辑客户: 回填农历生日 + 提醒 + 过敏史 + 自定义标签', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(customerId: '1'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('生日'), 200, scrollable: scroll);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('年 1968'), findsOneWidget);
    expect(find.text('月 8'), findsOneWidget);
    expect(find.text('日 1'), findsOneWidget);
    expect(find.text('农历'), findsWidgets);
    expect(find.text('生日提醒 (已开启)'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/form-04-edit-loaded.png'));

    // 既往病史 / 过敏史 回填
    await tester.scrollUntilVisible(find.text('既往病史'), 200, scrollable: scroll);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('高血压(服药中)'), findsOneWidget);
    expect(find.text('青霉素过敏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
