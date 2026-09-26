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

Customer _customer({
  required bool hasAccount,
  String affiliation = 'none',
  String ownership = 'none',
}) =>
    Customer.fromJson({
      'id': '1',
      'name': '演示-李桂芳',
      'phone': '13800001111',
      'customerType': 'normal',
      'hasAccount': hasAccount,
      'affiliation': affiliation,
      'ownership': ownership,
      'createdAt': '2026-09-22T00:00:00.000Z',
      'updatedAt': '2026-09-22T00:00:00.000Z',
    });

Future<void> _pumpRow(WidgetTester tester, Customer c,
    {bool isMember = false}) async {
  tester.view.physicalSize = const Size(393 * 3, 400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // 带真主题 (AGENTS §5: 不带主题测不出"主题把默认样式顶掉"这类 bug)
      theme: AppTheme.light(),
      home: Scaffold(
        body: CustomerRow(customer: c, isMember: isMember, onTap: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('客户列表行 — 身份图标条 (v2: 名字**下面** + 彩色 Material 图标, 只显示真状态)', () {
    testWidgets('已注册 → Icons.verified; 未注册 → 没有', (tester) async {
      await _pumpRow(tester, _customer(hasAccount: true));
      expect(find.byIcon(Icons.verified), findsOneWidget);

      await _pumpRow(tester, _customer(hasAccount: false));
      expect(find.byIcon(Icons.verified), findsNothing);
    });

    testWidgets('加盟 → Icons.handshake_outlined; 未加盟 → 不显示', (tester) async {
      await _pumpRow(tester, _customer(hasAccount: false, affiliation: 'direct'));
      expect(find.byIcon(Icons.handshake_outlined), findsOneWidget);

      await _pumpRow(tester, _customer(hasAccount: false, affiliation: 'none'));
      expect(find.byIcon(Icons.handshake_outlined), findsNothing);
    });

    testWidgets('★ 账号维度递进: 会员标**替换**注册标 (不是并列两个)', (tester) async {
      // 已注册 + 非会员 → 注册标
      await _pumpRow(tester,
          _customer(hasAccount: true), isMember: false);
      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(find.byIcon(Icons.workspace_premium), findsNothing);

      // 已注册 + 充值会员 → 只剩会员标 (替换掉注册标)
      await _pumpRow(tester,
          _customer(hasAccount: true), isMember: true);
      expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsNothing,
          reason: '会员是顶格状态 → 注册标要被替换, 不能并列');

      // 未注册 → 两个都不显示
      await _pumpRow(tester,
          _customer(hasAccount: false), isMember: false);
      expect(find.byIcon(Icons.workspace_premium), findsNothing);
      expect(find.byIcon(Icons.verified), findsNothing);
    });

    testWidgets('归属类: 上级推送 → Icons.move_to_inbox; 下级的客户 → Icons.groups_outlined',
        (tester) async {
      await _pumpRow(tester, _customer(hasAccount: false, ownership: 'upline'));
      expect(find.byIcon(Icons.move_to_inbox), findsOneWidget);
      expect(find.byTooltip('上级推送'), findsOneWidget, reason: '「是谁」在长按 tooltip');
      expect(find.byIcon(Icons.groups_outlined), findsNothing);

      await _pumpRow(tester, _customer(hasAccount: false, ownership: 'subordinate'));
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
      expect(find.byIcon(Icons.move_to_inbox), findsNothing);
    });

    testWidgets('★ 位置: 图标在**客户名下面** (不在名字前面)', (tester) async {
      await _pumpRow(
        tester,
        _customer(hasAccount: true, affiliation: 'direct'),
        isMember: true,
      );
      final nameRect = tester.getRect(find.text('演示-李桂芳'));
      // 用**第一个**图标断言左对齐 (第 3 个图标本来就该往右偏两个图标宽度)
      final firstIcon = tester.getRect(find.byIcon(Icons.handshake_outlined));
      expect(firstIcon.top, greaterThanOrEqualTo(nameRect.bottom - 1),
          reason: '图标要在名字下方那一行');
      expect(firstIcon.left, lessThan(nameRect.left + 1),
          reason: '图标条与名字左对齐 (不是名字右侧)');
    });

    testWidgets('真状态全为真 → 5 个图标都在; 全为假 → 一个都没有', (tester) async {
      await _pumpRow(
        tester,
        _customer(hasAccount: true, affiliation: 'direct', ownership: 'upline'),
        isMember: true,
      );
      for (final ic in [
        Icons.handshake_outlined,
        Icons.workspace_premium, // 会员 (替换注册标)
        Icons.move_to_inbox,
      ]) {
        expect(find.byIcon(ic), findsOneWidget, reason: '缺少图标 $ic');
      }
      expect(find.byIcon(Icons.verified), findsNothing,
          reason: '会员时不该同时出现注册标');

      await _pumpRow(tester, _customer(hasAccount: false, affiliation: 'none'));
      for (final ic in [
        Icons.handshake_outlined,
        Icons.workspace_premium,
        Icons.verified,
        Icons.move_to_inbox,
        Icons.groups_outlined,
      ]) {
        expect(find.byIcon(ic), findsNothing, reason: '$ic 不该出现 (真状态全为假)');
      }
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
