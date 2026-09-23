// 「已注册」标 + 绑定 app 身份解析 (ADR-0016 D8 + 绑定场景, 主人 2026-09-22)
//
// 关注点:
//   1. 列表行能区分「app 用户」与「凭空建档的客户」(hasAccount → 「已注册」标)
//   2. BindAccountResult 解析 (接管空档案/手机号同步/幂等) + 老后端缺字段不崩
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/services/api.dart' show BindAccountResult;
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/customer/widgets/customer_row.dart';

Customer _customer({required bool hasAccount}) => Customer.fromJson({
      'id': '1',
      'name': '演示-李桂芳',
      'phone': '13800001111',
      'customerType': 'normal',
      'hasAccount': hasAccount,
      'createdAt': '2026-09-22T00:00:00.000Z',
      'updatedAt': '2026-09-22T00:00:00.000Z',
    });

Future<void> _pumpRow(WidgetTester tester, Customer c) async {
  tester.view.physicalSize = const Size(393 * 3, 400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // 带真主题 (AGENTS §5: 不带主题测不出"主题把默认样式顶掉"这类 bug)
      theme: AppTheme.light(),
      home: Scaffold(
        body: CustomerRow(customer: c, onTap: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('客户列表行 — 「已注册」标 (ADR-0016 D8)', () {
    testWidgets('已绑定账号的客户 → 显示「已注册」', (tester) async {
      await _pumpRow(tester, _customer(hasAccount: true));
      expect(find.text('已注册'), findsOneWidget);
      expect(find.text('演示-李桂芳'), findsOneWidget);
    });

    testWidgets('凭空建档的客户 → 不显示「已注册」', (tester) async {
      await _pumpRow(tester, _customer(hasAccount: false));
      expect(find.text('已注册'), findsNothing);
      expect(find.text('演示-李桂芳'), findsOneWidget);
    });
  });

  group('BindAccountResult (绑定 app 身份响应)', () {
    test('接管空档案 + 手机号同步 → 各标志位正确', () {
      final r = BindAccountResult.fromJson({
        'ok': true,
        'alreadyBound': false,
        'phoneMismatch': true,
        'phoneSynced': true,
        'replacedEmptyProfile': true,
        'account': {'userId': '591', 'name': '演示-宋佳琪', 'phoneMasked': '138****3333'},
        'message': '已绑定 (演示-宋佳琪) —— 她注册时系统自动建的空档案已并入这条',
      });
      expect(r.replacedEmptyProfile, isTrue);
      expect(r.phoneSynced, isTrue);
      expect(r.accountName, '演示-宋佳琪');
      expect(r.accountPhoneMasked, '138****3333');
      expect(r.message, contains('已绑定'));
    });

    test('幂等 (alreadyBound) → 不重复处理', () {
      final r = BindAccountResult.fromJson({
        'alreadyBound': true,
        'account': {'name': '张三', 'phoneMasked': '139****0000'},
      });
      expect(r.alreadyBound, isTrue);
      expect(r.replacedEmptyProfile, isFalse);
      expect(r.phoneSynced, isFalse);
    });

    test('缺字段 (老后端) → 空壳不崩', () {
      final r = BindAccountResult.fromJson(const {});
      expect(r.alreadyBound, isFalse);
      expect(r.accountName, '');
      expect(r.message, '');
    });
  });
}
