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
class _FakeBillingService extends BillingService {
  _FakeBillingService({this.lookup}) : super(Dio());
  final ReferralLookup? lookup;
  @override
  Future<ReferralLookup> lookupReferralCode(String code) async =>
      lookup ?? ReferralLookup(found: false, code: code);
}

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this._ownership) : super(Dio());

  final CustomerOwnership _ownership;
  int claimCalls = 0;
  int transferCalls = 0;
  String? lastTransferCode;
  Object? claimError;
  Object? transferError;

  @override
  Future<CustomerOwnership> ownership(String customerId) async => _ownership;

  @override
  Future<CustomerOwnership> transfer(String customerId,
      {required String toReferralCode}) async {
    transferCalls++;
    lastTransferCode = toReferralCode;
    if (transferError != null) throw transferError!;
    return _ownership;
  }

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

Future<void> _pump(
  WidgetTester tester,
  _FakeCustomerService svc, {
  _FakeBillingService? billing,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      customerServiceProvider.overrideWithValue(svc),
      billingServiceProvider.overrideWithValue(billing ?? _FakeBillingService()),
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

  testWidgets('② 已经是我的: 状态"我的客户" + 按钮是「转给我的同事」', (tester) async {
    final svc = _FakeCustomerService(
      _own(ownerId: '540', ownerName: '演示-王秀兰', isMine: true,
          canClaim: true, statusLabel: '我的客户'),
    );
    await _pump(tester, svc);

    expect(find.text('我的客户'), findsOneWidget);
    // 归属我的时候, 唯一有意义的动作是**转出去** (原来给的"已经是我的客户"按钮没意义)
    expect(find.text('转给我的同事'), findsOneWidget);
    // 无归属才给认领按钮
    expect(find.text('认领为我的客户'), findsNothing);
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

  group("转移归属 (P8)", () {
    testWidgets("点「转给我的同事」→ 弹层要求输邀请码, 未识别时确认按钮禁用", (tester) async {
      final svc = _FakeCustomerService(
        _own(ownerId: '540', isMine: true, canClaim: true, statusLabel: '我的客户'),
      );
      await _pump(tester, svc);
      await tester.tap(find.text('转给我的同事'));
      await tester.pumpAndSettle();

      expect(find.text('转给同事'), findsOneWidget);
      expect(find.textContaining('你这边就不再有这位客户'), findsOneWidget);
      // 没识别出人之前不能确认 (防盲转)
      final confirm = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '确认转移'));
      expect(confirm.onPressed, isNull);
    });

    testWidgets("识别出人 → 显示姓名 + 打码手机号 → 确认后真调 transfer", (tester) async {
      final svc = _FakeCustomerService(
        _own(ownerId: '540', isMine: true, canClaim: true, statusLabel: '我的客户'),
      );
      final billing = _FakeBillingService(
        lookup: const ReferralLookup(
            found: true, code: 'SRFTF7', name: '张三',
            phoneMasked: '138****8000', claimState: 'others'),
      );
      await _pump(tester, svc, billing: billing);
      await tester.tap(find.text('转给我的同事'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'SRFTF7');
      await tester.tap(find.text('识别'));
      await tester.pumpAndSettle();

      expect(find.text('张三'), findsOneWidget);
      expect(find.textContaining('138****8000'), findsOneWidget);

      await tester.tap(find.text('确认转移'));
      await tester.pumpAndSettle();

      expect(svc.transferCalls, 1);
      expect(svc.lastTransferCode, 'SRFTF7');
      expect(find.textContaining('已转出'), findsOneWidget);
    });

    testWidgets("码是自己 → 明确说清, 不给确认", (tester) async {
      final svc = _FakeCustomerService(
        _own(ownerId: '540', isMine: true, canClaim: true, statusLabel: '我的客户'),
      );
      final billing = _FakeBillingService(
        lookup: const ReferralLookup(
            found: true, code: 'MINE01', name: '我自己', claimState: 'self'),
      );
      await _pump(tester, svc, billing: billing);
      await tester.tap(find.text('转给我的同事'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'MINE01');
      await tester.tap(find.text('识别'));
      await tester.pumpAndSettle();

      expect(find.text('这是你自己的邀请码'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '确认转移'));
      expect(confirm.onPressed, isNull);
      expect(svc.transferCalls, 0);
    });

    testWidgets("码不存在 → 提示核对", (tester) async {
      final svc = _FakeCustomerService(
        _own(ownerId: '540', isMine: true, canClaim: true, statusLabel: '我的客户'),
      );
      await _pump(tester, svc); // 默认 lookup 返回 found:false
      await tester.tap(find.text('转给我的同事'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'WRONG1');
      await tester.tap(find.text('识别'));
      await tester.pumpAndSettle();

      expect(find.textContaining('邀请码不存在'), findsOneWidget);
      expect(svc.transferCalls, 0);
    });

    testWidgets("转移失败 → 把后端人话显示出来, 不崩", (tester) async {
      final svc = _FakeCustomerService(
        _own(ownerId: '540', isMine: true, canClaim: true, statusLabel: '我的客户'),
      );
      svc.transferError = Exception('only 当前归属人 (或系统管理员) 能转出客户');
      final billing = _FakeBillingService(
        lookup: const ReferralLookup(
            found: true, code: 'SRFTF7', name: '张三', claimState: 'others'),
      );
      await _pump(tester, svc, billing: billing);
      await tester.tap(find.text('转给我的同事'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'SRFTF7');
      await tester.tap(find.text('识别'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认转移'));
      await tester.pumpAndSettle();

      expect(find.textContaining('转移失败'), findsOneWidget);
    });
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
