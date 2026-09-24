// ============================================
// 客户详情页 —— 评分卡 vs 行动卡 的 Tab 归属测试 (2026-09-24 新)
//
// 主人 2026-09-24 拍板诉求:
//   「评分卡」只允许出现在「分析」Tab, 三个 Tab 都有 = 反 vibe;
//   「现在该做」行动卡保留在 L0 (切 Tab 可见) —— CHARTER §1.4 既有拍板, 不要一起移走。
//
// 本文件 (页面级) 守结构归属:
//   · CustomerInsightActions (行动卡) 在 TabBarView **外面** = L0, 永远可见
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
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/screens/customer_detail_page.dart';
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

// ---------- pump helper ----------

Future<void> _pumpPage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _AlwaysFailAdapter();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(dio),
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
  // ⚠ runAsync: dio 内部 Timer 在 fake_async 下不自动 fire → 收尾
  //   "A Timer is still pending" 拖崩测试 (踩过: wellness_form_dict_error_test 同样的处理)。
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
Future<void> _tapTab(WidgetTester tester, int index) async {
  final BuildContext ctx = tester.element(find.byType(TabBar));
  final controller = DefaultTabController.of(ctx);
  controller.index = index;
  // PageView 需要一些帧重建子页 + 懒加载 build 新 Tab
  for (var i = 0; i < 5; i++) {
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
    'a) 默认「记录」Tab → 行动卡在 L0 (可见), 评分卡不可见',
    (tester) async {
      await _pumpPage(tester);

      // 行动卡**可见** —— 验证"切 Tab 也可见"的核心 (即便在默认「记录」Tab 也在)
      expect(find.byType(CustomerInsightActions), findsOneWidget,
          reason: 'L0 行动卡必须一直挂载 (CHARTER §1.4 拍板: 切 Tab 也可见)');

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

      // 行动卡**仍**可见 — L0 (TabBarView 外), 不该被切 Tab 藏掉
      expect(find.byType(CustomerInsightActions), findsOneWidget,
          reason: '行动卡在 L0, 切 Tab 不该藏掉 (CHARTER §1.4)');
      expect(find.textContaining('现在该做'), findsOneWidget);
    },
  );

  testWidgets(
    'c) 切到「管理」Tab → 评分卡不可见, 行动卡仍可见',
    (tester) async {
      await _pumpPage(tester);
      await _tapTab(tester, 2); // 管理

      // 评分卡**不可见**
      expect(find.text('78'), findsNothing,
          reason: '管理 Tab 不该出现评分卡的数字');
      expect(_scoreRing(), findsNothing,
          reason: '管理 Tab 不该出现评分环');

      // 行动卡**仍**可见 — L0 切 Tab 可见是 CHARTER §1.4 拍板,
      // 不能因为本次"评分卡只在分析 Tab"诉求撤掉
      expect(find.byType(CustomerInsightActions), findsOneWidget,
          reason: '行动卡在 L0, 切 Tab 不该藏掉 (CHARTER §1.4)');
      expect(find.textContaining('现在该做'), findsOneWidget);
      expect(find.text('约下次到店'), findsWidgets);
      expect(find.text('建任务'), findsOneWidget);
    },
  );
}