// 「我的」页 widget 测试
//
// 关注点 (跟目标用户强相关):
//   1. 资料/加盟/数据/设置四块都渲染出来 (文字对不对)
//   2. 未加盟 / 统计缺失 / 账号资料不全 这三种空态**不崩、不空白**
//   3. 窄屏 (320) + 特大字号 (1.3) 下滚完整页**不溢出** (中老年用户就是这样用的)
//
// 不测: 网络请求 (provider 直接 override 成假数据), 弹层里的平台能力 (package_info 等)
//
// 注意: 页面是 ListView (按需构建), 内容测试用一个「高屏」viewport 让整页一次渲染完;
//       溢出测试用真实手机尺寸 + 手动滚到底 —— 两条路径都要覆盖

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/me.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/services/api.dart'
    show ManualPayInfo, ManualPayProduct, MyReferral;
import 'package:nuankebao/core/widgets/user_avatar.dart';
import 'package:nuankebao/screens/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

MeProfile _fullProfile() => MeProfile.fromJson({
      'user': {
        'id': '1',
        'name': 'SeedTest-dev用户',
        'role': 'sales',
        'roleLabel': '销售员',
        'isActive': true,
        'createdAt': '2026-09-16T11:37:31.156Z',
        'hasUserRecord': true,
      },
      'phone': {'full': '13800138000', 'masked': '138****8000'},
      'store': {'id': '3', 'name': '城南店'},
      'franchisee': {
        'id': '75',
        'name': '宋一鸣',
        'phone': {'full': '13900000175', 'masked': '139****0175'},
        'isActive': true,
        'notes': 'A 线负责人',
        'joinedAt': '2026-09-16T11:37:26.315Z',
        'placement': {
          'side': 'left',
          'sideLabel': 'A 线 (左)',
          'depth': 1,
          'depthLabel': '第 1 层',
          'path': 'L.',
        },
        'referrer': {
          'id': '70',
          'name': '王总',
          'phone': {'full': '13700000070', 'masked': '137****0070'},
        },
        'downline': {'total': 2, 'left': 1, 'right': 1, 'unknown': 0},
      },
      'stats': {
        'customerCount': 47,
        'thisMonthVisits': 13,
        'pendingFollowUps': 6,
        'totalInteractions': 2,
        'newCustomersThisMonth': 47,
      },
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
    // 默认空列表: 「我的」页现在会读"我推荐的人", 不 override 会去打网络
    myReferralsProvider.overrideWith((ref) async => const <MyReferral>[]),
    // 「邀请被推荐人」区块读 appReleaseProvider. 不 override = 真去打网络 →
    //   测试里永远停在 AsyncLoading → 那块是 CircularProgressIndicator (无限动画)
    //   → pumpAndSettle 永不收敛 = 整份文件全挂 (2026-09-22 修).
    //   给空 release (apk=null) → 渲染"服务器上还没发布 APK"那行短文案, 不引入二维码图片
    appReleaseProvider.overrideWith((ref) async => const AppRelease()),
    ...extraOverrides,
  ]);
  addTearDown(container.dispose);
  return container;
}

/// 假的收款信息 (真接口在 curl 冒烟里验过, 这里只测 UI)
const _fakePayInfo = ManualPayInfo(
  enabled: true,
  qrUrl: '/payment/wechat-qr.png',
  isFallbackQr: false,
  qrAvailable: true, // 收款码已就位 (真接口在 curl 冒烟里验过)
  payeeName: '管理员小张',
  noteHint: '写手机号后 4 位',
  products: [
    ManualPayProduct(planCode: 'monthly', label: '1 个月', amountCents: 6900, days: 30),
    ManualPayProduct(planCode: 'quarterly', label: '3 个月', amountCents: 18900, days: 90),
  ],
);

Future<void> _pumpProfile(
  WidgetTester tester,
  ProviderContainer container, {
  double width = 393,
  double height = 3400, // 高屏: 整页一次渲染 (内容测试用; 页面加区块要同步调大)
  double fontScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // 必须带真主题: 不带 = Flutter 默认样式, 测不出"主题把组件默认样式顶掉了"这类 bug
        //   (2026-09-22 真机 chip 白字 bug 就是这么漏过去的 —— 见 chip_label_color_test.dart)
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(fontScale)),
          child: child!,
        ),
        home: const ProfilePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 从顶滚到底 (溢出只会在构建到那一段时暴露)
Future<void> _scrollToBottom(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
  }
  // 滚到底会把「账号与安全」也建出来, 它读 authProvider → 未登录时会
  // `Future.delayed(200ms)` 重试一次 cookie 同步 (R12 时序兜底). 测试结束时这个
  // Timer 还挂着 = "A Timer is still pending" 断言失败 → 这里把它跑完.
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('个人资料: 姓名/账号/角色/门店/手机号打码 都显示', (tester) async {
    final container = await _container(_fullProfile());
    await _pumpProfile(tester, container);

    expect(find.text('宋一鸣'), findsWidgets); // 加盟名 = 主标题
    expect(find.text('账号: SeedTest-dev用户'), findsOneWidget);
    expect(find.text('销售员'), findsOneWidget);
    expect(find.text('城南店'), findsOneWidget);
    expect(find.text('138****8000'), findsWidgets); // 头部 + 账号与安全 两处都打码
    expect(find.text('13800138000'), findsNothing); // 默认不露全号
    expect(find.text('编辑我的资料'), findsOneWidget);
  });

  testWidgets('加盟身份: 编号/位置/层级/上级/加入时间/下线数', (tester) async {
    final container = await _container(_fullProfile());
    await _pumpProfile(tester, container);

    expect(find.text('我的加盟身份'), findsOneWidget);
    expect(find.text('编号 #75'), findsOneWidget);
    expect(find.text('A 线 (左)'), findsOneWidget);
    expect(find.text('第 1 层'), findsOneWidget);
    expect(find.textContaining('王总'), findsOneWidget);
    expect(find.text('2026-09-16'), findsOneWidget);
    expect(find.text('2 人 (A线 1 · B线 1)'), findsOneWidget);
    expect(find.text('A 线负责人'), findsOneWidget);
  });

  testWidgets('数据概览: 5 个数字 + 加盟网络入口', (tester) async {
    final container = await _container(_fullProfile());
    await _pumpProfile(tester, container);

    expect(find.text('数据概览'), findsOneWidget);
    expect(find.text('47'), findsNWidgets(2)); // 客户 / 本月新增
    expect(find.text('6'), findsOneWidget); // 待办
    expect(find.text('13'), findsOneWidget); // 本月拜访
    expect(find.text('2 次'), findsOneWidget); // 累计互动
    expect(find.text('我的加盟网络'), findsOneWidget);
  });

  testWidgets('设置区: 字号快捷 chips (只显示) + 「更多设置」入口', (tester) async {
    final container = await _container(_fullProfile());
    await _pumpProfile(tester, container);

    // 设置区在「数据概览」之后 (按设计顺序; 中年用户刚需, 不下沉一层)
    Future<void> see(String text) async {
      await tester.scrollUntilVisible(
        find.text(text),
        120,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      expect(find.text(text), findsOneWidget, reason: '滚到「$text」后应可见');
    }

    // 设置区自身
    await see('设置');
    expect(find.text('更多设置'), findsOneWidget);
    expect(find.text('主题配色 / 跟进提醒 / 关于与帮助'), findsOneWidget);

    // 字号快捷 chips —— 4 档全部可见 (中年用户刚需, 这页不出现就不合格)
    expect(find.text('小'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('大'), findsOneWidget);
    expect(find.text('特大'), findsOneWidget);
  });

  testWidgets('账安 + 退出: 账号与安全/30天/编号  +  退出登录', (tester) async {
    final container = await _container(_fullProfile());
    await _pumpProfile(tester, container);

    Future<void> see(String text) async {
      await tester.scrollUntilVisible(
        find.text(text),
        120,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      expect(find.text(text), findsOneWidget, reason: '滚到「$text」后应可见');
    }

    // 账号与安全 (低频但保留 — 手机号/修改密码/改手机号是身份相关, 不下沉)
    await see('账号与安全');
    await see('30 天 (期间不用重复登录)');
    await see('#1 · 销售员');

    // 退出登录
    await see('退出登录');

    // 低频项已迁出 (在 settings_page_test.dart 里覆盖, 不在本「我的」页出现)
    expect(find.text('主题配色'), findsNothing);
    expect(find.text('关于与帮助'), findsNothing);
    expect(find.text('清理图片缓存'), findsNothing);
  });

  testWidgets('点「特大」→ 字号设置真被改掉', (tester) async {
    final container = await _container(_fullProfile());
    await _pumpProfile(tester, container);

    await tester.tap(find.text('特大'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).fontSize, AppFontSize.xlarge);
    // 持久化也要落到 prefs
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.font_size'), 'xlarge');
  });

  testWidgets('未加盟: 给说明而不是空白/报错', (tester) async {
    final container = await _container(MeProfile.fromJson({
      'user': {'id': '9', 'name': '李四', 'roleLabel': '销售员'},
      'phone': {'full': '13700137000', 'masked': '137****7000'},
      'franchisee': null,
      'stats': {
        'customerCount': 3,
        'thisMonthVisits': 1,
        'pendingFollowUps': 0,
        'totalInteractions': 0,
        'newCustomersThisMonth': 1,
      },
    }));
    await _pumpProfile(tester, container);

    expect(find.text('还没绑定加盟关系'), findsOneWidget);
    expect(find.text('未加盟'), findsOneWidget);
    expect(find.text('编辑我的资料'), findsNothing); // 没加盟就没得改
    expect(find.text('李四'), findsWidgets);
  });

  testWidgets('统计缺失 (stats=null): 给提示不崩', (tester) async {
    final container = await _container(MeProfile.fromJson({
      'user': {'id': '1', 'name': '张三', 'roleLabel': '销售员'},
      'stats': null,
    }));
    await _pumpProfile(tester, container);

    expect(find.textContaining('没拿到统计数据'), findsOneWidget);
  });

  testWidgets('账号资料不全 (dev mock): 明确提示', (tester) async {
    final container = await _container(MeProfile.fromJson({
      'user': {
        'id': '1',
        'name': '开发测试',
        'roleLabel': '销售员',
        'hasUserRecord': false,
      },
    }));
    await _pumpProfile(tester, container);

    expect(find.textContaining('账号资料还没建全'), findsOneWidget);
  });

  testWidgets('换头像: 入口可见 + 候选头像弹层能出 8 个候选', (tester) async {
    // bySemanticsLabel 需要语义树 (widget 测试默认不开, 跟线上不同)。
    // ⚠ 必须在测试体内 dispose: addTearDown 跑在框架的"检查语义句柄是否释放"之后
    final semantics = tester.ensureSemantics();

    final container = await _container(_fullProfile());
    await _pumpProfile(tester, container);

    // 入口 (头像本身可点 + 一个显式按钮)
    expect(find.text('换头像'), findsOneWidget);
    // 用正则: InkWell/按钮的语义会跟父节点合并, 精确匹配容易假失败
    expect(find.bySemanticsLabel(RegExp('我的头像')), findsWidgets);

    await tester.tap(find.text('换头像'));
    await tester.pumpAndSettle();

    expect(find.text('换个头像'), findsOneWidget);
    expect(find.text('拍一张'), findsOneWidget);
    expect(find.text('从相册选'), findsOneWidget);
    expect(find.text('或者挑一个现成的'), findsOneWidget);
    for (final preset in kAvatarPresets) {
      expect(find.text(preset.label), findsOneWidget);
    }
    expect(find.text('恢复默认头像'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('候选头像已选中时: 当前头像会被画出来 (首字 → 图标)', (tester) async {
    final container = await _container(MeProfile.fromJson({
      'user': {
        'id': '1',
        'name': '张三',
        'roleLabel': '销售员',
        'avatarUrl': 'preset:tea',
      },
      'stats': null,
    }));
    await _pumpProfile(tester, container);

    // preset:tea → 用「喝茶」图标画, 不再画首字「张」
    expect(find.byIcon(Icons.emoji_food_beverage), findsWidgets);
  });

  testWidgets('推荐人: 有人用我的码注册 → 「好友待确认」入口带人数', (tester) async {
    final container = await _container(
      // ⚠ 必须带 membership.referralCode: 「好友待确认」入口只在"我有码"时渲染
      MeProfile.fromJson({
        'user': {'id': '1', 'name': '张三', 'roleLabel': '销售员'},
        'membership': {
          'isMember': false,
          'planCode': 'free',
          'features': [],
          'referralCode': 'ABC234',
        },
      }),
      extraOverrides: [
        myReferralsProvider.overrideWith((ref) async => const [
              // 自助注册 + 未处理 → 需要我确认
              MyReferral(
                  id: '1',
                  name: '李秀兰',
                  phoneMasked: '139****3013',
                  status: 'pending',
                  source: 'self_signup'),
              // 管理员代建 (已生效) → 不该算进"待确认"
              MyReferral(
                  id: '2', name: '孙代建', phoneMasked: '139****3015', status: 'pending'),
              MyReferral(id: '3', name: '赵小兰', phoneMasked: '139****3014', status: 'confirmed'),
            ]),
      ],
    );
    await _pumpProfile(tester, container);

    expect(find.text('好友待确认 (1 人)'), findsOneWidget);
    expect(find.textContaining('有人用你的推荐码注册了'), findsOneWidget);
  });

  testWidgets('会员卡 (免费档): 显示开通入口 + 9 项会员功能说明 + 填推荐码', (tester) async {
    final container = await _container(_fullProfile()); // 没给 membership → 当免费档
    await _pumpProfile(tester, container);

    expect(find.text('会员'), findsOneWidget);
    expect(find.text('免费版'), findsOneWidget);
    expect(find.text('开通会员'), findsOneWidget);
    expect(find.textContaining('AI 助手'), findsWidgets); // 9 项里点名了 AI 助手
    // 主人 2026-09-19: 推荐码只能在注册(建号)时填 —— 「我的」页不能再有填码入口
    expect(find.text('我有推荐码'), findsNothing);
    expect(find.textContaining('填朋友的码'), findsNothing);
  });

  testWidgets('会员卡 (会员中): 显示到期日 + 续费入口 + 我的推荐码', (tester) async {
    final until = DateTime.now().add(const Duration(days: 15));
    String two(int n) => n.toString().padLeft(2, '0');
    final container = await _container(MeProfile.fromJson({
      'user': {'id': '1', 'name': '张三', 'roleLabel': '销售员'},
      'membership': {
        'isMember': true,
        'memberUntil': until.toIso8601String(),
        'planCode': 'member',
        'features': ['ai.assistant', 'crm.interaction'],
        'referralCode': 'ABC234',
      },
    }));
    await _pumpProfile(tester, container);

    expect(find.text('会员中'), findsOneWidget);
    expect(find.text('续费会员'), findsOneWidget);
    expect(
      find.textContaining(
          '会员有效期至 ${until.year}-${two(until.month)}-${two(until.day)}'),
      findsOneWidget,
    );
    expect(find.text('ABC234'), findsOneWidget); // 我的推荐码
    expect(find.text('复制推荐码'), findsNothing); // tooltip 不渲染成文字
  });

  testWidgets('会员卡 (管理员): 显示永久会员, 不显示开通/续费入口', (tester) async {
    final container = await _container(MeProfile.fromJson({
      'user': {'id': '1', 'name': '管理员', 'role': 'admin', 'roleLabel': '管理员'},
      'membership': {
        'isMember': true,
        'memberUntil': null,
        'planCode': 'admin',
        'permanent': true,
        'membershipSource': 'admin',
        'features': ['ai.assistant'],
        'referralCode': 'ADMIN1',
      },
    }));
    await _pumpProfile(tester, container);

    expect(find.textContaining('永久会员'), findsWidgets);
    expect(find.textContaining('不参与计费'), findsOneWidget);
    expect(find.text('开通会员'), findsNothing);
    expect(find.text('续费会员'), findsNothing);
  });

  testWidgets('开通会员弹层 (内测人工通道): 金额 + 收款人 + 我已支付', (tester) async {
    final container = await _container(
      _fullProfile(),
      extraOverrides: [
        manualPayInfoProvider.overrideWith((ref) async => _fakePayInfo),
      ],
    );
    await _pumpProfile(tester, container);

    await tester.tap(find.text('开通会员'));
    await tester.pumpAndSettle();

    expect(find.textContaining('¥69'), findsWidgets); // 1 个月金额
    expect(find.textContaining('¥189'), findsWidgets); // 3 个月金额
    expect(find.textContaining('管理员小张'), findsOneWidget); // 收款人
    expect(find.text('我已支付'), findsOneWidget); // 提交按钮
    expect(find.textContaining('写手机号后 4 位'), findsWidgets); // 备注提示
    expect(find.textContaining('暂不支持自动续费'), findsOneWidget);
    // 收款码已就位 (qrAvailable=true) → 不能误报"没有收款码"那句引导文案
    // (widget 测试里拿不到真实图片, 会走 errorBuilder 的"加载不出来", 那是另一件事)
    expect(find.textContaining('还没设置收款码'), findsNothing);
    expect(find.textContaining('管理员工具'), findsNothing);
  });

  testWidgets('窄屏 320 + 特大字号 1.3: 滚完整页不溢出', (tester) async {
    final container = await _container(_fullProfile());
    // 真实手机尺寸 (红米/老安卓常见 320 宽) + 特大字号 —— 最容易挤破的组合
    await _pumpProfile(tester, container,
        width: 320, height: 852, fontScale: 1.3);

    await _scrollToBottom(tester);

    // 溢出会让 test framework 直接 fail (RenderFlex overflowed 是异常)
    expect(tester.takeException(), isNull);
    expect(find.text('退出登录'), findsOneWidget); // 滚到底了, 整页都构建过
  });
}
