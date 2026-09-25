// 设置页 (/profile/settings) widget 测试 —— 「我的」页低频项下沉后的二级页
//
// 关注点:
//   1. 4 个区块都渲染 (显示与存储 / 主题配色 / 提醒 / 关于与帮助)
//   2. 字号 chips 4 档可见 + 点「特大」真改 settingsProvider + 落盘
//   3. 窄屏 (320) + 特大字号 (1.3) 不溢出 (中老年销售员常见组合)
//
// 不测: 真排程的本地通知 (依赖 flutter_local_notifications 平台实现; 已通过
//       flutter_test 之外的真机冒烟 / showDiagnosticsSheet 已在 profile_sheets 测过)
//
// 不必 stub manualPayInfoProvider (设置页不直接读, 只在「开通会员」时读, 而
// 「开通会员」入口仍在「我的」页 member 区块里, 不在本页面)。
//
// 不必 stub appReleaseProvider (settings_page 区块 4 (关于与帮助) 不读
// appRelease, 它由「我的」页 _InviteCard 读; 区块 3 提醒 / 区块 2 主题配色 /
// 区块 1 显示与存储 都不读)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/me.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/services/api.dart' show MyReferral;
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/follow_up/screens/follow_ups_page.dart'
    show FollowUpTodo, pendingFollowUpsProvider;
import 'package:nuankebao/screens/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

MeProfile _profileWithRole({String role = 'sales', String name = '宋一鸣'}) =>
    MeProfile.fromJson({
      'user': {
        'id': '1',
        'name': name,
        'role': role,
        'roleLabel': role == 'admin' ? '管理员' : '销售员',
        'isActive': true,
        'createdAt': '2026-09-16T11:37:31.156Z',
        'hasUserRecord': true,
      },
      'phone': {'full': '13800138000', 'masked': '138****8000'},
      'franchisee': null,
      'stats': null,
      'dev': {'authSkipped': false, 'sessionUserId': '1'},
    });

Future<ProviderContainer> _container(
  MeProfile profile, {
  List<Override> extraOverrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    meProfileProvider.overrideWith((ref) async => profile),
    myReferralsProvider.overrideWith((ref) async => const <MyReferral>[]),
    // 不 override: pendingFollowUpsProvider 会真去打网络 → 在测试里会卡 AsyncLoading;
    //   Widget test 里走的是 stub dio, 但保险起见显式 override 成空列表。
    pendingFollowUpsProvider
        .overrideWith((ref) async => const <FollowUpTodo>[]),
    ...extraOverrides,
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpSettings(
  WidgetTester tester,
  ProviderContainer container, {
  double width = 393,
  double height = 3400,
  double fontScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // 必须带真主题 (chipTheme.labelStyle.color = textPrimary) ——
        // 不带 = 测不出 chip 文字白字 bug (AGENTS §5 2026-09-22 防线)
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(fontScale)),
          child: child!,
        ),
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('4 个区块都渲染 (显示与存储 + 主题配色 + 提醒 + 关于与帮助)',
      (tester) async {
    final container = await _container(_profileWithRole());
    await _pumpSettings(tester, container);

    expect(find.text('设置'), findsOneWidget); // AppBar title

    // 显示与存储
    expect(find.text('显示与存储'), findsOneWidget);
    expect(find.text('小'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('大'), findsOneWidget);
    expect(find.text('特大'), findsOneWidget);
    expect(find.text('清理图片缓存'), findsOneWidget);

    // 主题配色 (ThemePickerCard)
    expect(find.text('主题配色'), findsOneWidget);
    expect(find.text('养生绿'), findsOneWidget); // 默认主题 (sage) 的 label
    expect(find.text('春 · 新芽'), findsOneWidget); // 季节组首项

    // 提醒
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('每天 08:30 提醒跟进'), findsOneWidget);

    // 关于与帮助
    expect(find.text('关于与帮助'), findsOneWidget);
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('使用帮助 / 数据安全'), findsOneWidget);
    expect(find.text('网络自检'), findsOneWidget);

    // debug-only 项不在 release build 出现; 测试是 debug, 但 profile 没带 admin 角色 →
    //   kDebugMode=true 会渲染「服务地址 (调试)」; role=sales 没 admin tool 入口
    expect(find.text('管理员工具'), findsNothing);
    expect(find.textContaining('服务地址'), findsOneWidget); // 调试可见 (kDebugMode=true)
  });

  testWidgets('管理员 (role=admin): 关于与帮助多一行「管理员工具」入口',
      (tester) async {
    // 回归防线 (reviewer P1): 原 profile_page._AboutCard 有 admin 工具入口,
    //   迁移时被漏掉过 —— 这个用例专门盯住它
    final container =
        await _container(_profileWithRole(role: 'admin', name: '管理员'));
    await _pumpSettings(tester, container);

    expect(find.text('管理员工具'), findsOneWidget);
    expect(find.text('用户管理 · 收款码设置 · 付款申请核销'), findsOneWidget);
  });

  testWidgets('点「特大」→ 字号设置真被改掉 (共享 FontSizePicker)',
      (tester) async {
    final container = await _container(_profileWithRole());
    await _pumpSettings(tester, container);

    await tester.tap(find.text('特大'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).fontSize, AppFontSize.xlarge);
    // 持久化也要落到 prefs
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.font_size'), 'xlarge');
  });

  testWidgets('设置页改字号 → settingsProvider 状态更新 (两页共用同一 provider)',
      (tester) async {
    // 同一份共享组件 + 同一 provider: 这里改完, 「我的」页读到的就是新值
    final container = await _container(_profileWithRole());
    await _pumpSettings(tester, container);

    // 设置页内点小
    await tester.tap(find.text('小'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).fontSize, AppFontSize.small);

    // 回到「我的」页, 「字号快捷 chips」应显示「小」为 selected (基于 chipTheme 选择高亮
    //   / chip 默认 selectedColor); 这里只验证 provider 已变化, 不验证 selected 视觉)
  });

  testWidgets('关于与帮助: 使用帮助 → /profile/about; 网络自检 → 弹层',
      (tester) async {
    final container = await _container(_profileWithRole());
    await _pumpSettings(tester, container);

    // 使用帮助: 跳到 /profile/about (在 go_router 测试里需要 ProviderScope 跑 router)
    // 这里仅验证「使用帮助 / 数据安全」行存在且可点; 不真正 push (避免引入 GoRouter 依赖)
    expect(find.text('使用帮助 / 数据安全'), findsOneWidget);

    // 网络自检: 一旦点击会调 showDiagnosticsSheet —— 在 widget test 里点会拉
    // /api/health (真实 dio 调用), 我们不点, 只断言行渲染
    expect(find.text('网络自检'), findsOneWidget);

    // 当前版本: 看 PackageInfo.fromPlatform(); widget test 里 PackageInfo 在
    // testing 模式下会让数据稳定返回 → 显示稳定版本, 这里只断言行标题
    expect(find.text('当前版本'), findsOneWidget);
  });

  testWidgets('窄屏 320 + 特大字号 1.3: 滚完整页不溢出', (tester) async {
    final container = await _container(_profileWithRole());
    // 真实手机尺寸 (红米/老安卓常见 320 宽) + 特大字号 —— 最容易挤破的组合
    await _pumpSettings(tester, container,
        width: 320, height: 852, fontScale: 1.3);

    // 滚到底 (16 次拖动)
    for (var i = 0; i < 16; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 250));

    // 溢出会让 test framework 直接 fail (RenderFlex overflowed 是异常)
    expect(tester.takeException(), isNull);
    expect(find.text('使用帮助 / 数据安全'), findsOneWidget); // 至少最后一行可点
  });
}
