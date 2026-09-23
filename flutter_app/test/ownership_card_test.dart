// ============================================
// 「归属」卡 单测 (管理维度 P7, 主人 2026-09-23)
// ============================================
// 守护的东西:
//   ① **按钮可用性 = 后端 canClaim** —— 不允许 UI 自己重算规则
//      (否则就是"按钮能点但一点就 409", 最气的交互)
//   ② 四种归属状态各自的文案与按钮形态
//   ③ 归属别人时**明确不给按钮** + 说清原因 (而不是给个点了报错的)
//   ④ 点认领会真调 API, 并 invalidate 三处 (归属自己 / 详情 / 客户列表)
//   ⑤ 高度 > 0 (P4 踩过: widget test 全绿但真机零高)
//
// ⚠ 必须带真主题 AppTheme.light(tokens) —— 不带主题走 Flutter 默认样式,
//   白字/零高这类真机 bug 测不出来 (AGENTS §5)。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/models/customer_ownership.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/ownership_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假的 CustomerService: 不发网络, 只记调用 + 可指定抛错
class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this._ownership) : super(Dio());

  final CustomerOwnership _ownership;
  int claimCalls = 0;
  Object? claimError;

  @override
  Future<CustomerOwnership> ownership(String customerId) async => _ownership;

  @override
  Future<Customer> claim(String customerId) async {
    claimCalls++;
    if (claimError != null) throw claimError!;
    return Customer(
      id: customerId,
      name: '演示-蒋金娣',
      phone: '13800000000',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
  }
}

CustomerOwnership _own({
  String? ownerId,
  String? ownerName,
  bool isMine = false,
  bool canClaim = false,
  String? blockedReason,
  String statusLabel = '',
}) =>
    CustomerOwnership(
      customerId: '798',
      ownerId: ownerId,
      ownerName: ownerName,
      isMine: isMine,
      canClaim: canClaim,
      blockedReason: blockedReason,
      statusLabel: statusLabel,
    );

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
      home: const Scaffold(
        body: SingleChildScrollView(
          child: CustomerOwnershipCard(customerId: '798'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① 无归属: 显示状态 + 后果说明 + 认领按钮', (tester) async {
    final svc = _FakeCustomerService(
      _own(canClaim: true, statusLabel: '还没有归属人'),
    );
    await _pump(tester, svc);

    expect(find.text('还没有归属人'), findsOneWidget);
    expect(find.text('认领为我的客户'), findsOneWidget);
    // 说清"为什么该管" —— 不讲清用户不会点
    expect(find.textContaining('不在任何人的「我的客户」列表里'), findsOneWidget);
  });

  testWidgets('② 已经是我的: 状态显示"我的客户"', (tester) async {
    final svc = _FakeCustomerService(
      _own(ownerId: '540', ownerName: '演示-王秀兰', isMine: true,
          canClaim: true, statusLabel: '我的客户'),
    );
    await _pump(tester, svc);

    expect(find.text('我的客户'), findsOneWidget);
    expect(find.text('已经是我的客户'), findsOneWidget);
  });

  testWidgets('③ 归属别人: **不给认领按钮** + 说清原因', (tester) async {
    final svc = _FakeCustomerService(
      _own(
        ownerId: '999',
        ownerName: '演示-李桂芳',
        canClaim: false,
        statusLabel: '已是 演示-李桂芳 的客户',
        blockedReason: '已被别人先认领 (先到先得); 要转移需与对方协商',
      ),
    );
    await _pump(tester, svc);

    expect(find.text('已是 演示-李桂芳 的客户'), findsOneWidget);
    // 关键: 不能给一个"点了会 409"的按钮
    expect(find.text('认领为我的客户'), findsNothing);
    expect(find.textContaining('已被别人先认领'), findsOneWidget);
    expect(find.textContaining('想转移归属请联系对方协商'), findsOneWidget);
  });

  testWidgets('④ 自己的档案: 不给按钮 + 说明', (tester) async {
    final svc = _FakeCustomerService(
      _own(canClaim: false, statusLabel: '这是你自己的档案',
          blockedReason: '不能把自己加为客户'),
    );
    await _pump(tester, svc);

    expect(find.text('这是你自己的档案'), findsOneWidget);
    expect(find.text('认领为我的客户'), findsNothing);
  });

  testWidgets('⑤ 点认领 → 真调 API', (tester) async {
    final svc = _FakeCustomerService(
      _own(canClaim: true, statusLabel: '还没有归属人'),
    );
    await _pump(tester, svc);

    await tester.tap(find.text('认领为我的客户'));
    await tester.pumpAndSettle();

    expect(svc.claimCalls, 1);
    expect(find.text('已加为我的客户'), findsOneWidget); // snackbar
  });

  testWidgets('⑥ 认领撞 409 → 提示人话而不是 DioException', (tester) async {
    final svc = _FakeCustomerService(
      _own(canClaim: true, statusLabel: '还没有归属人'),
    );
    svc.claimError = Exception('DioException [bad response]: status code 409');
    await _pump(tester, svc);

    await tester.tap(find.text('认领为我的客户'));
    await tester.pumpAndSettle();

    expect(find.text('已被别人先认领 (先到先得)'), findsOneWidget);
  });

  testWidgets('⚠ 高度不是 0 (P4 踩过: 单测绿但真机零高)', (tester) async {
    final svc = _FakeCustomerService(
      _own(canClaim: true, statusLabel: '还没有归属人'),
    );
    await _pump(tester, svc);

    final size = tester.getSize(find.byType(CustomerOwnershipCard));
    expect(size.height, greaterThan(100), reason: '整块塌成 0 高的话真机看不见');
    expect(size.width, greaterThan(0));
  });
}
