// ============================================
// 客户详情页 —— 评分卡 vs 行动卡 的 Tab 归属测试 (2026-09-24 新)
//
// 主人 2026-09-24 拍板诉求:
//   「评分卡」只允许出现在「分析」Tab, 三个 Tab 都有 = 反 vibe;
//   「现在该做」行动卡**只在记录 Tab** (2026-09-24 主人拍板, 覆盖早先的
//   "切 Tab 也可见" 口径) —— 分析 / 管理 Tab 必须看不到它。
//
// 本文件 (页面级) 守结构归属:
//   · CustomerInsightActions (行动卡) 在记录 Tab 顶部; 分析/管理 Tab **不渲染**
//   · CustomerScoreCard (评分卡) 在 TabBarView **里面**, 而且只在「分析」Tab
//     (不是「记录」, 也不是「管理」)
//   · 评分卡不会出现在另外两个 Tab (回归保护)
//
// 单元级测试 (评分卡 widget / 行动卡 widget 各自渲染) 见:
//   flutter_app/test/customer_score_card_test.dart
//   flutter_app/test/customer_insight_actions_test.dart
//
// 测试策略 (2026-09-24, 收尾日):
//   · 整页 pump CustomerDetailPage (真主题)
//   · override customerDetailProvider + customerInsightProvider (本测试要断言的两个核心)
//   · 其他 provider 用**假 Dio** (返回 503) 让 service 安静报错 ——
//     各 section 已做错误降级 (`when` 三态 / `valueOrNull`), 一处挂掉不该拖垮整页
//   · **不**用 pumpAndSettle: 详情页若干 section 在加载中会渲染 indeterminate
//     CircularProgressIndicator → 它会不停动画, pumpAndSettle 永不返回。
//     改用 pump + pump(Duration) + runAsync: 我们只验证 widget tree 形状, 不等动画。
//   · runAsync 里推真实时间, 让 dio 内部 0-duration Timer 走完, 避免
//     "A Timer is still pending" (踩过: wellness_form_dict_error_test 同样的处理)。
//
// ⚠ 必须带真主题 (AGENTS §5: 不带主题走 Flutter 默认样式, 测不出主题顶掉默认样式类 bug)。
//
// 跑: cd flutter_app && flutter test test/customer_detail_tabs_test.dart
// ============================================

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/models/customer_insight.dart';
import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/models/wellness_record.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/screens/customer_detail_page.dart';
import 'package:nuankebao/modules/customer/widgets/customer_activity_cards.dart';
import 'package:nuankebao/modules/customer/widgets/customer_insight_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- 假数据 ----------

Customer _customer() => Customer(
      id: '798',
      name: '演示-蒋金娣',
      phone: '13800001111',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

const _action = ActionItem(
  id: 'repurchase_window',
  priority: 'high',
  title: '约下次到店',
  why: '她的复购间隔通常 28 天, 已经 32 天没到店',
  when: '今天',
  channel: 'phone',
  expected: '约到具体日期',
  taskTitle: '约下次到店',
  taskDueAt: '2026-09-23T09:00:00.000Z',
  cta: 'create_task',
);

CustomerInsight _insightWithActions() => CustomerInsight(
      score: CustomerScore(
        overall: 78,
        overallBandLabel: '良好',
        effect: ScoreDimension.fromJson(const {
          'key': 'effect',
          'label': '健康改善',
          'score': 68,
          'bandLabel': '良好',
          'factors': [],
        }),
        engagement: ScoreDimension.fromJson(const {
          'key': 'engagement',
          'label': '关系温度',
          'score': 72,
          'bandLabel': '良好',
          'factors': [],
        }),
        value: ScoreDimension.fromJson(const {
          'key': 'value',
          'label': '价值潜力',
          'score': 76,
          'bandLabel': '良好',
          'factors': [],
        }),
        weakDimensions: const [],
      ),
      actions: const [_action],
      topActions: const [_action],
    );

// ---------- 假养生/互动 service: 让记录卡内部列表**可滚** ----------
//
// 2026-09-24 记录卡改成「固定表头 + 卡内可滚列表」后, 页面级折叠测试 (⑧⑨)
//   必须让**卡内那个**列表真的能滚 —— 否则 fling 不产生 ScrollNotification,
//   折叠状态机永远不触发 (之前记录 Tab 有外层 SingleChildScrollView, 空数据
//   也能靠"卡片 + 空列表"撑出可滚高度; 现在不行了)。
//   ⇒ 给 12 条养生记录 (dense 行 52px → 超出卡片可视区), 保证可滚。
class _FakeWellnessService extends WellnessRecordService {
  _FakeWellnessService(this.rows) : super(Dio());
  final List<WellnessRecord> rows;
  @override
  Future<List<WellnessRecord>> list({String? customerId, int limit = 50}) async =>
      rows;
}

class _FakeInteractionService extends InteractionService {
  _FakeInteractionService(this.rows) : super(Dio());
  final List<Interaction> rows;
  @override
  Future<List<Interaction>> list({String? customerId}) async => rows;
}

List<WellnessRecord> _timelineWellnessRows() => [
      for (var i = 0; i < 12; i++)
        WellnessRecord(
          id: 'w$i',
          customerId: '798',
          serviceDate:
              '2026-09-${(24 - i).clamp(1, 24).toString().padLeft(2, '0')}',
          serviceItemId: 'svc-1',
          createdAt: DateTime(2026, 9, 24).subtract(Duration(days: i)),
        ),
    ];

// ---------- 假 Dio: 所有请求立刻 503 ----------

class _AlwaysFailAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'error': 'mock-fail'}),
      503,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ---------- 假 FollowUpService: 记 create 调用 + list 返回空 ----------
//
// 为什么 override `followUpServiceProvider` 而不是只 inject Dio:
//   要验证「建任务」调用了 `followUpServiceProvider.create()`, 需要让 fake 服务
//   **记录** 调用参数。其他方法 (list/complete/cancel) 走假实现返回空 list
//   或仅继原型, 都是为了不让 dio 503 拖崩 CustomerFollowUpSection
//   (section 在加载中/error 都会渲染占位, key 仍在树上, 不影响 ensureVisible 验证)。
class _FakeFollowUpService extends FollowUpService {
  _FakeFollowUpService() : super(Dio()); // never used, 所有请求都在下面 override

  final List<Map<String, dynamic>> createCalls = [];
  int listCalls = 0;

  /// ⑨ 测试用: list() 返回这个列表 (默认空)。让 _FakeFollowUpService 复用
  /// 在「跟进卡固定 + 上滑折叠」测试里, 提供 1-2 条假任务模拟真实列表。
  List<FollowUpTask> listResult = const [];

  @override
  Future<FollowUpTask> create(Map<String, dynamic> data) async {
    createCalls.add(Map<String, dynamic>.from(data));
    return FollowUpTask(
      id: 'fake-task-${createCalls.length}',
      customerId: data['customerId'] as String,
      dueAt: DateTime.tryParse(data['dueAt'] as String? ?? '') ?? DateTime(2026, 9, 23),
      reason: data['reason'] as String? ?? '',
      status: 'pending',
      createdAt: DateTime(2026, 9, 22),
    );
  }

  @override
  Future<List<FollowUpTask>> list({String? customerId, String status = 'pending'}) async {
    listCalls++;
    return listResult;
  }
}

// ---------- pump helper ----------

Future<void> _pumpPage(WidgetTester tester, {Customer? customer}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _AlwaysFailAdapter();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(dio),
      wellnessRecordServiceProvider
          .overrideWithValue(_FakeWellnessService(_timelineWellnessRows())),
      interactionServiceProvider
          .overrideWithValue(_FakeInteractionService(const [])),
      customerDetailProvider('798')
          .overrideWith((ref) async => customer ?? _customer()),
      customerInsightProvider('798')
          .overrideWith((ref) async => _insightWithActions()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: const CustomerDetailPage(customerId: '798'),
    ),
  ));
  // ⚠ runAsync: dio 内部 Timer 在 fake_async 下不自动 fire → 收尾
  //   "A Timer is still pending" 拖崩测试 (踩过: wellness_form_dict_error_test 同样的处理)。
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  });
}


/// 泵 详情页 + 注入假 FollowUpService (用于 ⑦ 验证建任务路径)
Future<void> _pumpPageWithFakeFollowUp(
  WidgetTester tester, {
  required _FakeFollowUpService fake,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _AlwaysFailAdapter();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(dio),
      followUpServiceProvider.overrideWithValue(fake),
      wellnessRecordServiceProvider
          .overrideWithValue(_FakeWellnessService(_timelineWellnessRows())),
      interactionServiceProvider
          .overrideWithValue(_FakeInteractionService(const [])),
      customerDetailProvider('798')
          .overrideWith((ref) async => _customer()),
      customerInsightProvider('798')
          .overrideWith((ref) async => _insightWithActions()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: const CustomerDetailPage(customerId: '798'),
    ),
  ));
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  });
}

// ---------- 切 Tab helper ----------

/// 切 Tab (0=记录 / 1=分析 / 2=管理) 通过 controller 直接调 index。
///
/// ⚠ TabBar 内部手势检测在 fake_async + runAsync 组合下不容易触发;
///   animateTo 也靠帧推进, 在 widget test 中经常无法完成动画。
///   直接 .index = N + pump 是最可靠的跳页方式。
///
/// 2026-09-24: 详情页改为 ConsumerStatefulWidget + 自管 TabController,
///   `DefaultTabController.of(ctx)` 不可用 —— 改为拿 State 句柄
///   (`tester.state<CustomerDetailPageState>(find.byType(CustomerDetailPage))`)
///   调 `tabController.index`。
Future<void> _tapTab(WidgetTester tester, int index) async {
  final state =
      tester.state<CustomerDetailPageState>(find.byType(CustomerDetailPage));
  state.tabController.index = index;
  // ⚠ 切页动画 ~300ms (kTabScrollDuration): 动画没走完时 **前一个 Tab 仍在树上**
  //   (PageView 过渡期同时挂两页) —— 2026-09-24 行动卡搬进记录 Tab 后,
  //   「分析/管理 Tab 不该出现行动卡」的 findsNothing 断言会被这半挂的旧页假失败。
  //   有界推进直到 indexIsChanging == false, 再多推几帧让旧页卸载。
  for (var i = 0; i < 20; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    if (!state.tabController.indexIsChanging) break;
  }
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ---------- 评分环定位: 评分卡的环是**determinate** (value != null) ----------
//
// 详情页其他 section 的加载转圈 (记录/互动/任务的 LoadingState) 都是
// indeterminate (value=null)。用 widget predicate 精准锁定评分环。
Finder _scoreRing() => find.byWidgetPredicate(
      (w) => w is CircularProgressIndicator && w.value != null,
      description: '评分环 (determinate CPI, value != null)',
    );

void main() {
  testWidgets(
    'a) 默认「记录」Tab → 行动卡可见 (只在这个 Tab), 评分卡不可见',
    (tester) async {
      await _pumpPage(tester);

      // 行动卡**可见** —— 2026-09-24 主人拍板: 只在记录 Tab 显示
      expect(find.byType(CustomerInsightActions), findsOneWidget,
          reason: '「现在该做」在记录 Tab 必须可见 (主人 2026-09-24 拍)');

      // 评分卡**不可见** —— 默认 Tab 是「记录」, CustomerScoreCard 在「分析」Tab,
      //   TabBarView 懒加载: 没切到的 Tab 不渲染。验证分数 78 也不在树里。
      expect(find.text('78'), findsNothing,
          reason: '记录 Tab 不该出现评分卡的数字');
      expect(_scoreRing(), findsNothing,
          reason: '记录 Tab 不该出现评分环');

      // 行动卡内容: 标题 + 行动内容
      expect(find.textContaining('现在该做'), findsOneWidget);
      expect(find.text('约下次到店'), findsWidgets);
      expect(find.text('建任务'), findsOneWidget);
    },
  );

  testWidgets(
    'b) 切到「分析」Tab → 评分卡出现 (评分环 + 分数 78)',
    (tester) async {
      await _pumpPage(tester);
      await _tapTab(tester, 1); // 分析

      // 评分环可见 (determinate CPI, value != null)
      expect(_scoreRing(), findsOneWidget,
          reason: '分析 Tab 应有评分环');
      // 分数 78 在评分环里 (只渲染在 overall != null 时, 与评分环同生命周期)
      expect(find.text('78'), findsOneWidget,
          reason: '分析 Tab 评分环上应有综合分 78');

      // 三个维度小条 (收起态) — 评分卡渲染
      expect(find.text('健康改善'), findsWidgets);
      expect(find.text('关系温度'), findsWidgets);
      expect(find.text('价值潜力'), findsWidgets);

      // 行动卡**不可见** —— 2026-09-24 主人拍板: 「现在该做」只在记录 Tab。
      // ⚠ 用 `.hitTestable()` 而不是裸 findsNothing: TabBarView 底层 PageView 会把
      //   相邻页**留在树上** (离屏但不卸载), 裸 findsNothing 会假失败;
      //   hitTestable = "在视口里、能点到" = 用户口径的"显示"。
      expect(find.byType(CustomerInsightActions).hitTestable(), findsNothing,
          reason: '分析 Tab 不该显示「现在该做」(主人 2026-09-24 拍)');
      expect(find.textContaining('现在该做').hitTestable(), findsNothing);
    },
  );

  testWidgets(
    'c) 切到「管理」Tab → 评分卡不可见, 行动卡也不可见',
    (tester) async {
      await _pumpPage(tester);
      await _tapTab(tester, 2); // 管理

      // 评分卡**不可见**
      expect(find.text('78'), findsNothing,
          reason: '管理 Tab 不该出现评分卡的数字');
      expect(_scoreRing(), findsNothing,
          reason: '管理 Tab 不该出现评分环');

      // 行动卡**不可见** —— 2026-09-24 主人拍板: 只在记录 Tab 显示
      //   (同分析 Tab: 用 hitTestable 判"显示", 见上方注释)
      expect(find.byType(CustomerInsightActions).hitTestable(), findsNothing,
          reason: '管理 Tab 不该显示「现在该做」(主人 2026-09-24 拍)');
      expect(find.textContaining('现在该做').hitTestable(), findsNothing);
      // 管理 Tab 该有的内容还在 (证明不是整页空了)
      expect(find.textContaining('客户类型'), findsWidgets);
    },
  );

  // ============================================
  // ⑦ 建任务后的确认与引导 (2026-09-24 P1 闭环反馈)
  //
  // 主人原话: 「建任务后除了卡片消失, 没有其他任务引导或提示。
  //   用户不知道任务建到哪了、何时到期、去哪看。」
  //
  // 守什么:
  //   ⑦a 建任务成功后 SnackBar 出现, 文案含「已建任务」+「到期」+「查看任务」action
  //       (同根: 「该做的事」没明示下一步 = 用户发呆重复点「建任务」)
  //   ⑦b 点「查看任务」 → 切回记录 Tab (tabController.index == 0)
  //       (验证 _revealFollowUpSection 路径 + GlobalKey + Scrollable.ensureVisible 不拋)
  //   ⑦c followUpServiceProvider.create 被调用 (路径不止走到 UI, 真到了 service 层)
  //
  // 仍遵守本文件约定: 不用 pumpAndSettle (indeterminate 动画会永不返回),
  //   改用 pump + pump(Duration) 推进; SnackBar/动画/scroll 用有界重试。
  // ============================================
  group('⑦ 建任务后的确认与引导 (P1 闭环反馈)', () {
    testWidgets(
      '⑦a 建任务成功 → SnackBar 文案含「已建任务」+「到期」+「查看任务」action',
      (tester) async {
        final fake = _FakeFollowUpService();
        await _pumpPageWithFakeFollowUp(tester, fake: fake);

        // 点 L0 「建任务」 (行动卡一直可见, CHARTER §1.4 拍板)
        await tester.tap(find.text('建任务'));
        // 给 SnackBar / Future 几个帧推进 (建任务本身走 dio, SnackBar 需要动画到位)
        for (var i = 0; i < 8; i++) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }

        // ⚠ 锁 SnackBar 内的文本 (不动行动卡里那个「已建任务」状态小字):
        //   行动卡建成功后也会出「已建任务」三字, 与 SnackBar 文案同名,
        //   不用 descendant 锁会被凑成 2 个 text 报 too many。
        final snackBarText = find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Text),
        );
        expect(snackBarText, findsWidgets,
            reason: 'SnackBar 至少一个 Text');
        final allSnackTexts = snackBarText
            .evaluate()
            .map((e) => (e.widget as Text).data ?? '')
            .join(' | ');
        expect(allSnackTexts, contains('已建任务'),
            reason: 'SnackBar 应明确告知已建任务');
        expect(allSnackTexts, contains('到期'),
            reason: 'SnackBar 应告知到期日 (修复诉求: 用户不知「何时到期」)');
        expect(allSnackTexts, contains('约下次到店'),
            reason: 'SnackBar 应显示任务标题');
        expect(allSnackTexts, contains('09-23'),
            reason: 'SnackBar 应显示到期日 (本任务 taskDueAt=2026-09-23)');
        // action: SnackBarAction 渲染为 TextButton, label 为「查看任务」
        expect(find.widgetWithText(TextButton, '查看任务'), findsOneWidget,
            reason: '修复诉求: 提供「去哪看」入口');
      },
    );

    testWidgets(
      '⑦b 点「查看任务」 → 停在记录 Tab + 跟进卡仍可见 (行动卡只在记录 Tab)',
      (tester) async {
        final fake = _FakeFollowUpService();
        await _pumpPageWithFakeFollowUp(tester, fake: fake);

        // 2026-09-24 行动卡只在记录 Tab → 「在别的 Tab 点建任务再切回来」这个
        //   老场景不再存在; 现在验证: 点「查看任务」后**留在**记录 Tab、
        //   跟进卡(固定卡)仍在, 且不崩 (_revealFollowUpSection 的收折叠分支)。
        await tester.tap(find.text('建任务'));
        for (var i = 0; i < 8; i++) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }

        await tester.tap(find.widgetWithText(TextButton, '查看任务'));
        // 让 Future.delayed / setState 走完 (有界推进)
        for (var i = 0; i < 10; i++) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }

        final after = tester
            .state<CustomerDetailPageState>(find.byType(CustomerDetailPage));
        expect(after.tabController.index, 0,
            reason: '点「查看任务」后应停在记录 Tab (行动卡 / 跟进卡都在这里)');
        expect(find.byKey(CustomerFollowUpSection.cardKey), findsOneWidget,
            reason: '跟进卡是固定卡, 点 action 后仍可见');
      },
    );

    testWidgets(
      '⑦c followUpServiceProvider.create 被调用 + customerId/reason/dueAt 都对',
      (tester) async {
        final fake = _FakeFollowUpService();
        await _pumpPageWithFakeFollowUp(tester, fake: fake);

        await tester.tap(find.text('建任务'));
        for (var i = 0; i < 8; i++) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(fake.createCalls, hasLength(1),
            reason: '「建任务」应走 followUpServiceProvider.create (闭环要点)');
        final call = fake.createCalls.single;
        expect(call['customerId'], '798');
        expect(call['reason'], '约下次到店',
            reason: '传 action.taskTitle 作为任务原因');
        expect(call['dueAt'], isNotNull,
            reason: '传 action.taskDueAt 转 UTC ISO 字符串');
      },
    );
  });

  // ============================================
  // ⑧ 上滑折叠行动卡 (2026-09-24 主人诉求)
  //
  // 主人原话: 「随页面上滑折叠到最少一行, 补折叠状态时卡片右上角出现图标
  //   (向下展开)」。
  //
  // 守什么 (页面级):
  //   · 默认状态 = 展开 → 不出 expand_more
  //   · 记录 Tab 纵向滚动越过阈值 24 → 出现 expand_more (action 区折叠)
  //   · 滚回顶部 → expand_more 消失 (恢复展开)
  //
  // 测试机制: 默认 Tab 是「记录」, 它的滚动容器是 SingleChildScrollView;
  //   NotificationListener 在 body 外层, 收子树冒泡上来的 ScrollNotification,
  //   过滤 axis != vertical (TabBarView 横向 PageView 不会误触发)。
  //   用 tester.fling 在 SingleChildScrollView 上 fling 100pt 即可越过 24pt 阈值。
  //
  // ⚠ 抩展点: 页面 pump 后默认在记录 Tab (index 0), TabBarView 当前子页就是
  //   _buildRecordTab → _tabScroll → SingleChildScrollView, 可直接定位。
  // ============================================
  group('⑧ 上滑折叠行动卡 (滚动驱动, 2026-09-24)', () {
    testWidgets(
      '上滑越过阈值 → 行动卡折叠 (expand_more 出现); 滚回顶部 → 恢复展开',
      (tester) async {
        await _pumpPage(tester);

        // 预条件: 默认展开态, 折叠图标**不**可见
        expect(find.byIcon(Icons.expand_more), findsNothing,
            reason: '默认 (顶在顶部) 应该是展开态, 不出折叠图标');

        // 定位记录 Tab 的滚动容器 (是 SingleChildScrollView;
        // TabBarView 本身也是 Scrollable 但轴向 horizontal, fling 纵向偏移它不会动)
        final recordScrollable = find.descendant(
          of: find.byType(CustomerDetailPage),
          matching: find.byType(SingleChildScrollView),
        );
        expect(recordScrollable, findsWidgets,
            reason: '记录 Tab 应至少有 1 个 SingleChildScrollView (TAB 懒加载, 可能在当前页看到几个)');

        // fling 200pt 向上 → 越过 24pt 阈值 → 触发折叠
        await tester.fling(recordScrollable.first, const Offset(0, -200), 800);
        await tester.pumpAndSettle();

        // 折叠图标应出现 (L0 行动卡已折叠到一行 + 右上角 expand_more)
        expect(find.byIcon(Icons.expand_more), findsOneWidget,
            reason: '上滑越过 24pt 阈值 → 行动卡折叠 → 右下角出现 expand_more');
        // 同时行动行**不可见**
        expect(find.text('约下次到店'), findsNothing,
            reason: '折叠态不该渲染行动行');

        // 反向: fling 向下足够多 → 滚回顶部 → 恢复展开
        await tester.fling(recordScrollable.first, const Offset(0, 1000), 800);
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.expand_more), findsNothing,
            reason: '滚回顶部 (pixels <= 0) → 行动卡恢复展开 → 图标消失');
        expect(find.text('约下次到店'), findsWidgets,
            reason: '展开态应渲染行动行');
      },
    );

    testWidgets(
      '点 expand_more → 强制回到展开态 (不管当前滚动位置)',
      (tester) async {
        await _pumpPage(tester);

        // 先上滑触发折叠
        final recordScrollable = find.descendant(
          of: find.byType(CustomerDetailPage),
          matching: find.byType(SingleChildScrollView),
        );
        await tester.fling(recordScrollable.first, const Offset(0, -200), 800);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.expand_more), findsOneWidget,
            reason: '预条件: 已上滑, 折叠图标在');

        // 点折叠图标 → 手动切回展开 (详情页不要求滚动位置归零)
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.expand_more), findsNothing,
            reason: '点折叠图标 → onToggleCollapsed 被调 → 详情页强制回展开');
      },
    );
  });
  // ============================================
  // ⑨ 跟进任务卡固定 + 上滑折叠 (2026-09-24 主人诉求)
  //
  // 主人原话: 「『跟进任务』卡片也像『现在该做』卡片一样随上滑收起,
  //   但不能随上滑全部不见了。」
  //
  // 验证什么 (页面级):
  //   ① 给假 service 1-2 条任务 → 详情页渲染
  //   ② 上滑 (fling) → 折叠状态推进:
  //     - 跟进卡**仍然**在树上 (`find.byKey(CustomerFollowUpSection.cardKey)` findsOneWidget)
  //     - 任务 tile 收起 (具体 reason 不可见)
  //     - **关键**: 这条断言守「不能随上滑全部不见了」—— 卡片整体不消失,
  //       折叠后只剩 header 一行, 但卡片实体还在视口里
  //   ③ 滚回顶部 → 恢复展开 (reason 重新可见)
  //
  // 测试机制: 详情页 body 外包 NotificationListener<ScrollNotification>, 收子树
  //   冒泡的纵向滚动; pixels > 24 → setState(_actionsCollapsed = true);
  //   pixels <= 0 → setState(_actionsCollapsed = false)。本测试借 fling
  //   让 SingleChildScrollView (时间线) 滚, 触发 NotificationListener 折叠。
  //
  // 上一版 (改动前): 跟进任务卡在 _tabScroll 里, 上滑整张卡滚出视口 → 违反
  //   主人诉求。本测试**就是这条诉求的回归断言**, 改回旧布局会失败。
  // ============================================
  group('⑨ 跟进任务卡固定 + 上滑折叠 (2026-09-24 主人诉求)', () {
    testWidgets(
      '跟进卡不能随上滑全部不见了 + 任务行收起 + 滚回顶部恢复',
      (tester) async {
        // 1-2 条假任务: 装到 _FakeFollowUpService 注入详情页
        final fake = _FakeFollowUpService();
        // 复用 fake.listResult (现有 _FakeFollowUpService 自带字段),
        // 让 list() 返回 2 条假任务 —— 模拟有真实任务的客户,
        // 验证「上滑折叠 + 卡片固定可见」+ 「滚回顶部恢复」整条路径。
        fake.listResult = [
          FollowUpTask(
            id: 'pinned-1',
            customerId: '798',
            dueAt: DateTime(2026, 9, 25, 9, 0),
            reason: '问腰疼好点没',
            status: 'pending',
            createdAt: DateTime(2026, 9, 24),
          ),
          FollowUpTask(
            id: 'pinned-2',
            customerId: '798',
            dueAt: DateTime(2026, 9, 23, 9, 0),
            reason: '回访上次理疗效果',
            status: 'pending',
            createdAt: DateTime(2026, 9, 22),
          ),
        ];

        await _pumpPageWithFakeFollowUp(tester, fake: fake);

        // 预条件: 展开态, 卡片在树上 + 任务 tile 可见
        final cardFinder = find.byKey(CustomerFollowUpSection.cardKey);
        expect(cardFinder, findsOneWidget,
            reason: '预条件: 跟进卡挂 CustomerFollowUpSection.cardKey, '
                '详情页初次渲染就应可见');
        expect(find.textContaining('问腰疼好点没'), findsOneWidget,
            reason: '预条件: 任务 tile (展开态) 可见');
        // 展开态**不**该出现 expand_more 图标
        expect(find.descendant(of: cardFinder, matching: find.byIcon(Icons.expand_more)), findsNothing,
            reason: '展开态不渲染折叠图标');

        // fling 记录 Tab 的滚动容器 → 越过 24pt 阈值 → 触发折叠
        final recordScrollable = find.descendant(
          of: find.byType(CustomerDetailPage),
          matching: find.byType(SingleChildScrollView),
        );
        expect(recordScrollable, findsWidgets,
            reason: '记录 Tab 至少有 1 个 SingleChildScrollView (时间线那个)');
        await tester.fling(recordScrollable.first, const Offset(0, -300), 800);
        await tester.pumpAndSettle();

        // ⭐ 关键断言: 跟进卡**仍然**在 widget tree 上, 视觉上不被滚走
        //    (旧的滚动布局会让整张卡滚出视口, find 找不到 → 这条会失败)
        expect(cardFinder, findsOneWidget,
            reason: '★ 主人诉求「不能随上滑全部不见了」: 跟进卡必须仍挂载, '
                'fixed 卡的实现承诺');
        // 任务 tile 收起: reason / 完成按钮 不可见 (折叠态只渲染一行 header)
        expect(find.textContaining('问腰疼好点没'), findsNothing,
            reason: '折叠态收起任务 tile → reason 不可见');
        expect(find.textContaining('回访上次理疗效果'), findsNothing);
        expect(find.byIcon(Icons.check_circle_outline), findsNothing,
            reason: '折叠态收起任务 tile → 完成按钮不可见');
        // 折叠态 header 上应该有 expand_more 图标
        expect(find.descendant(of: cardFinder, matching: find.byIcon(Icons.expand_more)), findsOneWidget,
            reason: '折叠态出 expand_more (有任务可展开)');

        // 反向: 滚回顶部 → 恢复展开
        await tester.fling(recordScrollable.first, const Offset(0, 1500), 800);
        await tester.pumpAndSettle();

        expect(find.textContaining('问腰疼好点没'), findsOneWidget,
            reason: '滚回顶部 → 恢复展开 → 任务 tile 重新可见');
        expect(find.descendant(of: cardFinder, matching: find.byIcon(Icons.expand_more)), findsNothing,
            reason: '恢复展开 → 折叠图标消失');
        expect(cardFinder, findsOneWidget,
            reason: '展开态跟进卡仍在树上 (本来就是固定的)');
      },
    );
  });

  // ============================================
  // ⑩ 管理 Tab 改进 (2026-09-24 建议 #2/#6/#7/#9)
  //
  // 守什么:
  //   · 三节分组标题在 (档案 / 关系与身份 / 最近改动)
  //   · 健康提示卡在档案组顶部 (有过敏史 → 显示"过敏史"; 无 → 轻提示)
  //   · app 身份卡: 已注册客户显示**她的邀请码** (#6)
  // ============================================
  group('⑩ 管理 Tab 分组 + 邀请码 (2026-09-24)', () {
    testWidgets('三节分组标题 + 健康提示空态提示', (tester) async {
      await _pumpPage(tester);
      await _tapTab(tester, 2); // 管理

      // #7 分节
      expect(find.text('档案'), findsWidgets);
      expect(find.text('关系与身份'), findsOneWidget);
      expect(find.text('最近改动'), findsOneWidget);

      // #9 健康卡空态 (测试客户没填过敏/病史)
      expect(find.textContaining('还没填健康信息'), findsOneWidget);
    });

    testWidgets('有过敏史 → 健康卡显示过敏史; 已注册 → 显示她的邀请码 (#6)',
        (tester) async {
      await _pumpPage(
        tester,
        customer: Customer.fromJson({
          'id': '798',
          'name': '演示-蒋金娣',
          'phone': '13800001111',
          'allergyHistory': '花粉、海鲜',
          'hasAccount': true,
          'accountReferralCode': 'AB12CD',
          'createdAt': '2026-09-01T00:00:00.000Z',
          'updatedAt': '2026-09-01T00:00:00.000Z',
        }),
      );
      await _tapTab(tester, 2); // 管理

      // #9 健康提示
      expect(find.text('过敏史'), findsOneWidget);
      expect(find.text('花粉、海鲜'), findsOneWidget);
      expect(find.textContaining('还没填健康信息'), findsNothing);

      // #6 她的邀请码 + 复制
      expect(find.text('她的邀请码'), findsOneWidget);
      expect(find.text('AB12CD'), findsOneWidget);
      expect(find.byTooltip('复制邀请码'), findsOneWidget);
    });
  });
}