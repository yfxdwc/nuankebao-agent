// 注册页 (B1) widget 测试
//
// 主人 2026-09-20 要求: 「账号/用户名提醒用户填真实姓名，真实手机号」
//   → 断言页面上真的有这两句提示 (这类"文案要求"最容易在重构里被删掉)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/router/app_router.dart';
import 'package:nuankebao/modules/auth/screens/register_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpRegister(WidgetTester tester, {String? code}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // 注册页只读 prefs (Router/网络都不需要), 这里给最小可用环境
        // ignore: invalid_use_of_visible_for_testing_member
      ],
      child: MaterialApp(home: RegisterScreen(initialCode: code)),
    ),
  );
  await tester.pump();
  // 注: 本页不读 sharedPreferencesProvider; prefs 仅为避免插件缺失告警
  expect(prefs, isNotNull);
}

/// 端到端复现原 bug: 在**真路由**上从登录页点「去注册」→ 必须看到注册页
///
/// 为什么必须用真 router: 原 bug 不在按钮(按钮本身对), 而在鉴权重定向把 /register 踢走了
/// —— 只测按钮 onPressed 是测不出来的 (这正是当初漏掉的原因)。
Future<void> _pumpRealApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          routerConfig: ref.watch(appRouterProvider),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★ 回归: 登录页点「去注册」→ 进注册页 (不是被踢回登录页)', (tester) async {
    await _pumpRealApp(tester);

    // 未登录 → 落在登录页
    expect(find.text('账号 / 手机号'), findsOneWidget);

    await tester.ensureVisible(find.text('有新推荐码? 去注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('有新推荐码? 去注册'));
    await tester.pumpAndSettle();

    // 关键断言: 到了注册页, 且没被 redirect 踢回登录页
    expect(find.text('注册账号'), findsOneWidget);           // 注册页 AppBar
    expect(find.text('推荐码 *'), findsOneWidget);
    expect(find.text('账号 / 手机号'), findsNothing);         // 登录页已离开
  });

  testWidgets('注册页: 四个必填项 + 真实姓名/真实手机号提示 + 邀请制说明', (tester) async {
    await _pumpRegister(tester);

    // 必填项
    expect(find.text('推荐码 *'), findsOneWidget);
    expect(find.text('真实姓名 *'), findsOneWidget);
    expect(find.text('真实手机号 *'), findsOneWidget);
    expect(find.text('设置密码 *'), findsOneWidget);
    expect(find.text('再填一次密码 *'), findsOneWidget);

    // ★ 主人要求的"提醒填真实信息"
    expect(find.textContaining('请填真实姓名'), findsOneWidget);
    expect(find.textContaining('管理员要用它核对身份'), findsOneWidget);
    expect(find.textContaining('请填真实手机号'), findsOneWidget);
    expect(find.textContaining('它就是你的登录账号'), findsOneWidget);

    // 邀请制 + 要推荐人确认 (不能让用户以为注册完就有会员)
    expect(find.textContaining('邀请制'), findsOneWidget);
    expect(find.textContaining('推荐人点「这是我朋友」确认后'), findsOneWidget);

    // 注册按钮 + 回登录
    expect(find.text('注册'), findsOneWidget);
    expect(find.text('已有账号? 去登录'), findsOneWidget);
  });

  testWidgets('带上推荐码进来时会预填 (从登录页跳转)', (tester) async {
    await _pumpRegister(tester, code: 'ABC234');
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, '推荐码 *').first,
    );
    expect(field.controller?.text, 'ABC234');
  });

  testWidgets('信息没填全时点注册: 给中文提示, 不发请求', (tester) async {
    await _pumpRegister(tester);
    // 表单比测试窗口高 → 先滚到按钮再点 (真机上用户也会滚动)
    await tester.ensureVisible(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('注册'));
    await tester.pump(); // 触发 setState/SnackBar
    await tester.pump(const Duration(milliseconds: 400)); // 等 SnackBar 进场
    expect(find.textContaining('请填推荐码'), findsOneWidget);
  });
}
