// ============================================
// 「危险操作」卡 单测 (P8 归档删除入口, 主人 2026-09-23)
// ============================================
// 守护的东西:
//   ① 危险操作要在视觉上被标出来 (标题「危险操作」+ 红系配色)
//   ② 点归档**先弹确认框**, 取消 → 一个 API 都不发 (误点保护)
//   ③ 确认 → 真调 DELETE, 并退回上一页 (客户已不在列表, 停在详情页没意义)
//   ④ ⭐ **诚实性护栏**: 确认框文案必须说清「App 内无恢复入口」——
//      绝不能写"可恢复"骗人 (后端只有软删, 全仓无 undelete 路径)
//   ⑤ 失败不崩 + 把错误说出来
//
// ⚠ 必须带真主题 (AGENTS §5: 不带主题走默认样式, 白字/零高测不出来)

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/models/follow_up_info.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/danger_zone_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService() : super(Dio());

  int deleteCalls = 0;
  int mergeCalls = 0;
  String? mergedInto;
  Object? deleteError;
  Object? mergeError;
  List<CustomerWithFollowUp> searchResults = const [];

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<Map<String, dynamic>> merge(String customerId,
      {required String intoCustomerId}) async {
    mergeCalls++;
    mergedInto = intoCustomerId;
    if (mergeError != null) throw mergeError!;
    return {'movedRecords': 3};
  }

  @override
  Future<CustomerListResult> list({
    String? search,
    String? type,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async =>
      CustomerListResult(
        items: searchResults,
        total: searchResults.length,
        sort: 'new',
        urgencyLocked: false,
      );
}

Future<void> _pump(WidgetTester tester, _FakeCustomerService svc) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      customerServiceProvider.overrideWithValue(svc),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('上一页'),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: SingleChildScrollView(
                          child: CustomerDangerZoneCard(
                            customerId: '798',
                            customerName: '演示-蒋金娣',
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('进详情页'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 进到详情页 (危险操作卡可见)
Future<void> _enter(WidgetTester tester) async {
  await tester.tap(find.text('进详情页'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① 渲染: 标出「危险操作」+ 归档按钮 + 后果提示', (tester) async {
    await _pump(tester, _FakeCustomerService());
    await _enter(tester);

    expect(find.text('危险操作'), findsOneWidget);
    expect(find.text('归档这位客户'), findsOneWidget);
    expect(find.textContaining('无法撤销'), findsOneWidget);
  });

  group("合并重复客户 (P8)", () {
    Customer other(String id, String name, {bool hasAccount = false}) => Customer(
          id: id,
          name: name,
          phone: '13900000000',
          hasAccount: hasAccount,
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        );

    CustomerWithFollowUp wrap(Customer c) =>
        CustomerWithFollowUp(customer: c, isMember: false);

    testWidgets("有「合并重复客户」按钮 + 说清用途", (tester) async {
      await _pump(tester, _FakeCustomerService());
      await _enter(tester);
      expect(find.text('合并重复客户'), findsOneWidget);
      expect(find.textContaining('并成一条'), findsOneWidget);
    });

    testWidgets("点它 → 弹「保留哪条客户」搜索框", (tester) async {
      await _pump(tester, _FakeCustomerService());
      await _enter(tester);
      await tester.tap(find.text('合并重复客户'));
      await tester.pumpAndSettle();

      expect(find.text('保留哪条客户？'), findsOneWidget);
      expect(find.text('搜索'), findsOneWidget);
    });

    testWidgets("搜到 → 点选 → 确认框说清「搬什么 / 不搬什么 / 不可逆」", (tester) async {
      final svc = _FakeCustomerService();
      svc.searchResults = [wrap(other('801', '演示-蒋金娣'))];
      await _pump(tester, svc);
      await _enter(tester);

      await tester.tap(find.text('合并重复客户'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '蒋');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('演示-蒋金娣'), findsWidgets);
      await tester.tap(find.text('演示-蒋金娣').last);
      await tester.pumpAndSettle();

      expect(find.text('合并客户？'), findsOneWidget);
      // 搬家清单必须写清 (养生记录/联系记录/跟进任务)
      expect(find.textContaining('养生记录、联系记录、跟进任务'), findsOneWidget);
      // 不能让人以为档案字段也会搬
      expect(find.textContaining('不会搬'), findsOneWidget);
      expect(find.textContaining('App 里无法撤销'), findsOneWidget);
    });

    testWidgets("确认 → 真调 merge(目标 id) + 退回列表", (tester) async {
      final svc = _FakeCustomerService();
      svc.searchResults = [wrap(other('801', '演示-蒋金娣'))];
      await _pump(tester, svc);
      await _enter(tester);

      await tester.tap(find.text('合并重复客户'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '蒋');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('演示-蒋金娣').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定合并'));
      await tester.pumpAndSettle();

      expect(svc.mergeCalls, 1);
      expect(svc.mergedInto, '801');
      expect(find.textContaining('已合并进'), findsOneWidget);
      expect(find.text('上一页'), findsOneWidget); // 已归档 → 退回
    });

    testWidgets("双绑定被拒 → 显示后端人话, 不崩", (tester) async {
      final svc = _FakeCustomerService();
      svc.searchResults = [wrap(other('801', '演示-蒋金娣', hasAccount: true))];
      svc.mergeError = Exception('两条档案都绑了 app 账号 —— 无法判断谁是谁');
      await _pump(tester, svc);
      await _enter(tester);

      await tester.tap(find.text('合并重复客户'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '蒋');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('演示-蒋金娣').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定合并'));
      await tester.pumpAndSettle();

      expect(find.textContaining('都绑了 app 账号'), findsOneWidget);
      expect(find.text('危险操作'), findsOneWidget); // 没被踢出页面
    });

    testWidgets("搜不到 → 明确说「没找到」", (tester) async {
      await _pump(tester, _FakeCustomerService());
      await _enter(tester);
      await tester.tap(find.text('合并重复客户'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '不存在');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('没找到匹配的客户'), findsOneWidget);
    });
  });

  testWidgets('⚠ 高度不是 0 (P4 踩过: 单测绿但真机零高)', (tester) async {
    await _pump(tester, _FakeCustomerService());
    await _enter(tester);
    final size = tester.getSize(find.byType(CustomerDangerZoneCard));
    expect(size.height, greaterThan(100), reason: '塌成 0 高的话真机看不见');
  });

  testWidgets('② 点归档 → 弹确认框; 取消 → 一个 API 都不发', (tester) async {
    final svc = _FakeCustomerService();
    await _pump(tester, svc);
    await _enter(tester);

    await tester.tap(find.text('归档这位客户'));
    await tester.pumpAndSettle();
    expect(find.textContaining('归档「演示-蒋金娣」'), findsOneWidget);

    await tester.tap(find.text('再想想'));
    await tester.pumpAndSettle();

    expect(svc.deleteCalls, 0, reason: '取消不能发请求 (误点保护)');
    expect(find.text('归档这位客户'), findsOneWidget); // 还在原页
  });

  testWidgets('④ ⭐诚实性: 确认框必须说清「App 内无恢复入口」, 不能写可恢复', (tester) async {
    await _pump(tester, _FakeCustomerService());
    await _enter(tester);
    await tester.tap(find.text('归档这位客户'));
    await tester.pumpAndSettle();

    // 后端只有软删 + 全仓无 undelete 路径 → 文案必须诚实
    expect(find.textContaining('没有恢复入口'), findsOneWidget);
    expect(find.textContaining('联系系统管理员'), findsOneWidget);
    // 反向断言: 不能给用户"随时能恢复"的错觉
    expect(find.textContaining('可以恢复'), findsNothing);
    expect(find.textContaining('可恢复'), findsNothing);
  });

  testWidgets('③ 确认 → 真调 DELETE + 退回上一页', (tester) async {
    final svc = _FakeCustomerService();
    await _pump(tester, svc);
    await _enter(tester);

    await tester.tap(find.text('归档这位客户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定归档'));
    await tester.pumpAndSettle();

    expect(svc.deleteCalls, 1);
    // 退回上一页 (客户已不在列表, 停详情页没意义)
    expect(find.text('上一页'), findsOneWidget);
    expect(find.text('危险操作'), findsNothing);
  });

  testWidgets('⑤ 失败: 不崩 + 不退出页面 + 把错误说出来', (tester) async {
    final svc = _FakeCustomerService();
    svc.deleteError = Exception('DioException 404');
    await _pump(tester, svc);
    await _enter(tester);

    await tester.tap(find.text('归档这位客户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定归档'));
    await tester.pumpAndSettle();

    expect(svc.deleteCalls, 1);
    expect(find.textContaining('归档失败'), findsOneWidget);
    // 失败不能把人踢出页面
    expect(find.text('危险操作'), findsOneWidget);
  });
}
