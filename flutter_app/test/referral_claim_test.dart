// 「我推荐的人」+ 推荐码查人 模型单测 (ADR-0015 步骤 3)
//
// 关注点:
//   1. claimState 决定按钮显不显示 (claimable 才显示) —— 判错了要么加不了, 要么误报
//   2. 老后端 / 缺字段 → no_profile, 不崩 (flutter-only-sync: 客户端要能吃老响应)
//   3. 后端 409 (先到先得) 时 canClaim 必须能反映"不能加"
//   4. 页面级: 「我推荐的人」页真的把按钮画出来 (不只是模型算对)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/screens/my_referrals_page.dart';

void main() {
  group('MyReferral (我推荐的人)', () {
    test('claimState=claimable + customerId → canClaim=true', () {
      final r = MyReferral.fromJson({
        'id': '370',
        'name': '小张',
        'phoneMasked': '139****6633',
        'status': 'pending',
        'source': 'self_signup',
        'createdAt': '2026-09-22T09:58:32.666Z',
        'customerId': '697',
        'claimState': 'claimable',
      });
      expect(r.canClaim, isTrue);
      expect(r.customerId, '697');
      expect(r.needsMyConfirmation, isTrue);
      expect(r.claimLabel, isNull); // 可加 → 不显示状态文案
    });

    test('已归属别人 → 不能加 + 有状态文案', () {
      final r = MyReferral.fromJson({
        'id': '1',
        'name': '小张',
        'customerId': '697',
        'claimState': 'others',
      });
      expect(r.canClaim, isFalse);
      expect(r.claimLabel, '已归属其他销售');
    });

    test('已是我的客户 → 不能加 + 状态文案', () {
      final r = MyReferral.fromJson(
          {'id': '1', 'name': '小张', 'customerId': '697', 'claimState': 'mine'});
      expect(r.canClaim, isFalse);
      expect(r.claimLabel, '✓ 已是我的客户');
    });

    test('老后端 (没有 customerId / claimState) → no_profile, 不崩', () {
      final r = MyReferral.fromJson({'id': '1', 'name': '小张'});
      expect(r.customerId, isNull);
      expect(r.claimState, 'no_profile');
      expect(r.canClaim, isFalse);
    });

    test('claimable 但没有 customerId (脏数据) → 不能加 (防崩)', () {
      final r = MyReferral.fromJson(
          {'id': '1', 'name': '小张', 'claimState': 'claimable'});
      expect(r.canClaim, isFalse);
    });
  });

  group('ReferralLookup (按码查人)', () {
    test('找到 + claimable → canClaim=true, 姓名/打码手机号可用', () {
      final r = ReferralLookup.fromJson({
        'found': true,
        'code': 'ABC123',
        'name': '小张',
        'phoneMasked': '139****6633',
        'isMember': true,
        'customerId': '697',
        'claimState': 'claimable',
      });
      expect(r.found, isTrue);
      expect(r.canClaim, isTrue);
      expect(r.name, '小张');
      expect(r.phoneMasked, '139****6633');
      expect(r.isMember, isTrue);
    });

    test('码不存在 → found=false, 不能加 (200 不是错误)', () {
      final r = ReferralLookup.fromJson({'found': false, 'code': 'QQQQQQ'});
      expect(r.found, isFalse);
      expect(r.canClaim, isFalse);
      expect(r.claimLabel, '该用户没有客户档案 (不参与客户维护)');
    });

    test('本人码 / 已归属别人 → 不能加 + 原因文案', () {
      expect(
        ReferralLookup.fromJson({'found': true, 'claimState': 'self'}).canClaim,
        isFalse,
      );
      expect(
        ReferralLookup.fromJson({'found': true, 'claimState': 'others'})
            .claimLabel,
        '已归属其他销售 (先到先得)',
      );
    });

    test('缺字段 (老后端) → 空壳不崩', () {
      final r = ReferralLookup.fromJson(const {});
      expect(r.found, isFalse);
      expect(r.customerId, isNull);
      expect(r.canClaim, isFalse);
    });
  });

  // ============================================
  // 页面级: 按钮真画出来了 (模型算对 ≠ UI 看得见)
  // ============================================
  // 不 override meProfileProvider / customerServiceProvider: 本组只渲染不点击,
  // 点击路径的真行为走后端 curl 冒烟 (409/400/200 已在 E2E 验过)。
  group('MyReferralsPage — 「加为我的客户」按钮', () {
    Future<void> pump(WidgetTester tester, List<MyReferral> rows) async {
      final container = ProviderContainer(overrides: [
        myReferralsProvider.overrideWith((ref) async => rows),
      ]);
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(393 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            // 带真主题 (AGENTS §5: 不带主题测不出"主题把默认样式顶掉"这类 bug)
            theme: AppTheme.light(),
            home: const MyReferralsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    MyReferral row({
      required String claimState,
      String? customerId = '697',
      String status = 'confirmed',
      String source = 'admin',
    }) =>
        MyReferral.fromJson({
          'id': '1',
          'name': '小张',
          'phoneMasked': '139****6633',
          'status': status,
          'source': source,
          'customerId': customerId,
          'claimState': claimState,
        });

    testWidgets('可加 → 显示「加为我的客户」按钮', (tester) async {
      await pump(tester, [row(claimState: 'claimable')]);
      expect(find.text('加为我的客户'), findsOneWidget);
    });

    testWidgets('已归属别人 → 不显示按钮, 显示状态文案', (tester) async {
      await pump(tester, [row(claimState: 'others')]);
      expect(find.text('加为我的客户'), findsNothing);
      expect(find.text('已归属其他销售'), findsOneWidget);
    });

    testWidgets('已是我的客户 → 不显示按钮, 显示勾选文案', (tester) async {
      await pump(tester, [row(claimState: 'mine')]);
      expect(find.text('加为我的客户'), findsNothing);
      expect(find.text('✓ 已是我的客户'), findsOneWidget);
    });

    testWidgets('老后端 (no_profile) → 既不显示按钮也不显示状态 (不干扰)', (tester) async {
      await pump(tester, [row(claimState: 'no_profile', customerId: null)]);
      expect(find.text('加为我的客户'), findsNothing);
      expect(find.text('✓ 已是我的客户'), findsNothing);
      expect(find.text('已归属其他销售'), findsNothing);
    });

    testWidgets('待确认的自助注册行: 确认按钮与加客户按钮共存', (tester) async {
      await pump(tester, [
        row(claimState: 'claimable', status: 'pending', source: 'self_signup'),
      ]);
      expect(find.text('这是我朋友'), findsOneWidget);
      expect(find.text('加为我的客户'), findsOneWidget);
    });
  });
}
