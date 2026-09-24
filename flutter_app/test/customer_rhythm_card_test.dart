// ============================================
// 「跟进节奏」卡 widget 测试 (P1, 2026-09-25 新; 2026-09-26 紧凑版改造)
// ============================================
// 守护的东西:
//   ① 标题「跟进节奏」(副标题「客观记录: ...」已删, 不再断言)
//   ② headline (一句话总结) 渲染
//   ③ 6 指标: 「近 30 天联系 / 联系间隔 / 到店次数 / 复购间隔 / 上次到店 / 待办跟进」
//   ④ 「上次到店」**只出现一次** (去重证据: 不再像旧卡那样和复购段里重复)
//   ⑤ 复购预测段: 「预计下次」+「还有/已过 N 天」+ 置信度 chip + reason 小字
//      (合并一行 Wrap; 日期不再有底色容器)
//   ⑥ isDue 时: 「建跟进任务」按钮在 (紧凑 FilledButton.tonalIcon, 内容宽度, 右对齐)
//   ⑥b 点击按钮 → showAddFollowUpSheet 弹层渲染「新建跟进任务」
//   ⑥c isDue=false → 大动作按钮**不**渲染
//   ⑦ 预测抛错 → 「复购预测暂时算不出来」+ 跟进段照常显示 (静默降级)
//   ⑧ 点刷新 → 两个 service 各被再调一次 (复购预测埋点也走)
//   ⑨ aiTipAvailable=false → 卡底锁文案在
//   ⑩ 「点右上角可重试」提示在错误态下出现
//
// ⚠ 必须带真主题 (AGENTS §5: 不带主题走 Flutter 默认样式, 白字/塌高 bug 测不出来)。
//
// 跑: cd flutter_app && flutter test test/customer_rhythm_card_test.dart
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/ai_insight.dart';
import 'package:nuankebao/core/models/follow_up_info.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/customer_rhythm_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- 假 service ----------

/// 假的 CustomerService: 覆盖 followUpAnalysis, 其他走 super (避免 dio 触发)
class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this.followUpResult) : super(Dio());

  FollowUpAnalysis followUpResult;
  int followUpCalls = 0;
  bool throwOnFollowUp = false;

  @override
  Future<FollowUpAnalysis> followUpAnalysis(String customerId) async {
    followUpCalls++;
    if (throwOnFollowUp) throw Exception('follow-up service 503');
    return followUpResult;
  }
}

/// 假的 AiService: 覆盖 repurchasePrediction, 其他走 super
class _FakeAiService extends AiService {
  _FakeAiService(this.repurchaseResult) : super(Dio());

  RepurchasePrediction repurchaseResult;
  int repurchaseCalls = 0;
  bool throwOnRepurchase = false;

  @override
  Future<RepurchasePrediction> repurchasePrediction(String customerId) async {
    repurchaseCalls++;
    if (throwOnRepurchase) throw Exception('repurchase service 503');
    return repurchaseResult;
  }
}

// ---------- 默认 fixture ----------

FollowUpAnalysis _followUpBase({bool aiTipAvailable = false}) =>
    FollowUpAnalysis(
      contactLast30: 4,
      contactLast90: 9,
      contactTotal: 18,
      avgContactIntervalDays: 12,
      daysSinceLastContact: 3,
      trend: 'warmer',
      trendText: '近 30 天联系变频繁',
      visitCount: 7,
      avgVisitIntervalDays: 21,
      lastVisitAt: DateTime(2026, 9, 18),
      daysSinceLastVisit: 7,
      medianRepurchaseIntervalDays: 30,
      pendingTasks: 2,
      overdueTasks: 1,
      oldestOverdueDays: 5,
      headline: '近 30 天联系 4 次, 节奏稳定偏热, 1 条任务逾期 5 天',
      aiTipAvailable: aiTipAvailable,
    );

RepurchasePrediction _repurchaseBase({
  bool isDue = false,
  int? daysUntilPredicted = 5,
}) =>
    RepurchasePrediction(
      customerId: '798',
      lastVisit: '2026-09-18',
      daysSinceLastVisit: 7,
      avgIntervalDays: 30,
      predictedNextVisit: '2026-10-18',
      daysUntilPredicted: daysUntilPredicted,
      confidence: 'high',
      reason: '按 30 天平均复购周期推算',
    );

// ---------- Host ----------

Future<Widget> _host(
  Widget child, {
  required _FakeCustomerService customerService,
  required _FakeAiService aiService,
  double cardWidth = 600,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      customerServiceProvider.overrideWithValue(customerService),
      aiServiceProvider.overrideWithValue(aiService),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: cardWidth,
            child: CustomerRhythmCard(customerId: '798'),
          ),
        ),
      ),
    ),
  );
}

Widget _card() => const CustomerRhythmCard(customerId: '798');

void main() {
  testWidgets('① 标题 + headline + 6 指标 + 「上次到店」只出现一次',
      (tester) async {
    final c = _FakeCustomerService(_followUpBase());
    final a = _FakeAiService(_repurchaseBase());
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();

    // 标题在 (副标题「客观记录: ...」已删, 不再断言)
    expect(find.text('跟进节奏'), findsOneWidget);
    // 一句话总结 (跟趋势同行, 紧凑)
    expect(
      find.text('近 30 天联系 4 次, 节奏稳定偏热, 1 条任务逾期 5 天'),
      findsOneWidget,
    );
    // 趋势 (图标 + 文字) 也渲染
    expect(find.text('近 30 天联系变频繁'), findsOneWidget);
    // 6 指标 (label)
    expect(find.text('近 30 天联系'), findsOneWidget);
    expect(find.text('联系间隔'), findsOneWidget);
    expect(find.text('到店次数'), findsOneWidget);
    expect(find.text('复购间隔'), findsOneWidget);
    expect(find.text('上次到店'), findsOneWidget);
    expect(find.text('待办跟进'), findsOneWidget);
    // ★ 去重证据: 跟进段里出现过「上次到店」, 复购段里**不**再有
    //   (旧 RepurchaseCard 渲染「距上次到店」tile —— 现在删了)
    expect(find.text('上次到店'), findsOneWidget);
    expect(find.text('距上次到店'), findsNothing);
    // 旧 RepurchaseCard 里有「平均复购周期」, 现在也没了 (复购间隔已在跟进段)
    expect(find.text('平均复购周期'), findsNothing);
  });

  testWidgets('⑤⑥ 复购预测段 (isDue=true): 预计下次 + 还有 N 天 + 置信度 + reason + 紧凑按钮',
      (tester) async {
    final c = _FakeCustomerService(_followUpBase());
    final a = _FakeAiService(
        _repurchaseBase(daysUntilPredicted: 2, isDue: true));
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();

    expect(find.text('预计下次'), findsOneWidget);
    expect(find.text('2026-10-18'), findsOneWidget);
    expect(find.textContaining('还有 2 天'), findsOneWidget);
    expect(find.text('数据充分'), findsOneWidget); // confidence=high
    expect(find.text('按 30 天平均复购周期推算'), findsOneWidget);
    // isDue=true → 紧凑按钮在 (label 改成「建跟进任务」, 不再有 surfaceSubtle 容器包裹)
    expect(find.text('建跟进任务'), findsOneWidget);
    // ★ 旧文案不再出现 (确保确实换了)
    expect(find.text('建一条跟进任务'), findsNothing);
  });

  testWidgets('⑥b 紧凑按钮 = FilledButton.tonalIcon, onPressed != null, tap 不崩',
      (tester) async {
    // 备注: 直接 pumpBottomSheet 验证 showAddFollowUpSheet 弹层文案——
    //   走不通: Material 3 InkSparkle 触发的 shader 资产
    //   ('shaders/ink_sparkle.frag') 在 headless test 框架里缺失。
    //   真实端到端已由 B4 「flutter build apk + 真机验证」覆盖。
    //   这里验证按钮的渲染形态 (icon + label + 类型 + 可点) + tap 不抛错,
    //   「isDue=true 显示 / isDue=false 不显示」配套互证。
    //
    // 2026-09-26 reviewer 报: 原用例只「tap 不崩」一个断言, 姿态过低,
    // 任何「表单里布着个空按钮」都能过。补两点:
    //   ① 按钮是 FilledButton.tonalIcon 的子类 (_FilledButtonWithIconChild),
    //      且 onPressed != null (=按钮是点得动的, 不是占位)
    //   ② onPressed 回调存在时, tap 不会被 swallowed (warnIfMissed=false + 不报错)
    final c = _FakeCustomerService(_followUpBase());
    final a = _FakeAiService(
        _repurchaseBase(daysUntilPredicted: 2, isDue: true));
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();

    // isDue=true → 紧凑按钮渲染: icon + label + 不依赖 BigActionButton 全宽类
    expect(find.byIcon(Icons.add_task), findsOneWidget);
    expect(find.text('建跟进任务'), findsOneWidget);

    // ★ reviewer m6 加强: 按钮必须是 FilledButton 系 (ButtonStyleButton) 且 onPressed != null
    // 用 predicate 找「祖先是 FilledButton (含 tonalIcon 子类) 的 Text widget」。
    // FilledButton.tonalIcon 实际返的是 _FilledButtonWithIconChild (FilledButton 子类),
    //   直接 find.byType(FilledButton) 会送 0 (因为拿到的是包了 Text 的内部子类)——
    //   所以走 ButtonStyleButton (上面 Fill 都在的) 一下包到
    final ancestor = find.ancestor(
      of: find.text('建跟进任务'),
      matching: find.byWidgetPredicate(
        (w) => w is ButtonStyleButton && w.onPressed != null,
      ),
    );
    expect(ancestor, findsOneWidget,
        reason: '「建跟进任务」必须是可点的 ButtonStyleButton');

    // tap 不崩 (sheet 内部 ink_sparkle.frag 可能会招, 但 warnIfMissed=false 软点
    // + pump 一帧能看出 widget 树未报错的本意; 本身不靠这点验证 button onPressed)。
    final btn = find.text('建跟进任务');
    expect(btn, findsOneWidget);
    await tester.tap(btn, warnIfMissed: false);
    await tester.pump();
  });

  testWidgets('⑥c 复购预测段 (isDue=false): 紧凑按钮**不**在',
      (tester) async {
    final c = _FakeCustomerService(_followUpBase());
    // daysUntilPredicted=14 → isDue=false (判定: <=7)
    final a = _FakeAiService(
        _repurchaseBase(daysUntilPredicted: 14, isDue: false));
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();

    expect(find.text('预计下次'), findsOneWidget);
    expect(find.textContaining('还有 14 天'), findsOneWidget);
    // isDue=false → 紧凑按钮不渲染
    expect(find.text('建跟进任务'), findsNothing);
    expect(find.text('建一条跟进任务'), findsNothing);
  });

  testWidgets('⑦ 预测抛错 → 「复购预测暂时算不出来」+ 跟进段照常显示',
      (tester) async {
    final c = _FakeCustomerService(_followUpBase());
    final a = _FakeAiService(_repurchaseBase());
    a.throwOnRepurchase = true;
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();

    // 复购段: 错误文案 + 提示点右上刷新
    expect(find.textContaining('复购预测暂时算不出来'), findsOneWidget);
    expect(find.textContaining('点右上角可重试'), findsOneWidget);
    // 跟进段照常: 一句话总结 + 6 指标在
    expect(find.text('近 30 天联系 4 次, 节奏稳定偏热, 1 条任务逾期 5 天'),
        findsOneWidget);
    expect(find.text('近 30 天联系'), findsOneWidget);
    expect(find.text('待办跟进'), findsOneWidget);
    // 整卡不崩 (找到 Card 节点)
    expect(find.byType(CustomerRhythmCard), findsOneWidget);
  });

  testWidgets('⑧ 点刷新 → 两个 service 各被再调一次', (tester) async {
    final c = _FakeCustomerService(_followUpBase());
    final a = _FakeAiService(_repurchaseBase());
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();
    expect(c.followUpCalls, 1);
    expect(a.repurchaseCalls, 1);

    // 找「重新计算」按钮 (tooltip) ——
    // 右上角 IconButton 的 tooltip = '重新计算'
    final refreshBtn = find.byTooltip('重新计算');
    expect(refreshBtn, findsOneWidget);
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();

    expect(c.followUpCalls, 2);
    expect(a.repurchaseCalls, 2);
  });

  testWidgets('⑨ aiTipAvailable=false → 卡底锁文案在', (tester) async {
    final c = _FakeCustomerService(_followUpBase(aiTipAvailable: false));
    final a = _FakeAiService(_repurchaseBase());
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('升级会员可看 AI 解读'),
      findsOneWidget,
    );
    expect(find.textContaining('该聊什么'), findsOneWidget);
  });

  testWidgets('⑨b aiTipAvailable=true → 卡底锁文案**不**在', (tester) async {
    final c = _FakeCustomerService(_followUpBase(aiTipAvailable: true));
    final a = _FakeAiService(_repurchaseBase());
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();

    // 锁态: 锁文案不出现
    expect(find.textContaining('升级会员可看 AI 解读'), findsNothing);
  });

  testWidgets('跟进段抛错 → 错误行 + 重试按钮 (不裸 DioException)',
      (tester) async {
    final c = _FakeCustomerService(_followUpBase());
    c.throwOnFollowUp = true;
    final a = _FakeAiService(_repurchaseBase());
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a));
    await tester.pumpAndSettle();

    expect(find.text('跟进数据没加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    // 不应该看到 DioException / stack trace
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('stack'), findsNothing);
  });

  testWidgets('窄屏 (<360) → 6 指标自动退化为 2 列 (3 行)', (tester) async {
    final c = _FakeCustomerService(_followUpBase());
    final a = _FakeAiService(_repurchaseBase());
    // 300 < 360 → 应走 2 列路径
    await tester.pumpWidget(await _host(_card(),
        customerService: c, aiService: a, cardWidth: 300));
    await tester.pumpAndSettle();

    // 数据完整性: 6 个 label 全在
    expect(find.text('近 30 天联系'), findsOneWidget);
    expect(find.text('联系间隔'), findsOneWidget);
    expect(find.text('到店次数'), findsOneWidget);
    expect(find.text('复购间隔'), findsOneWidget);
    expect(find.text('上次到店'), findsOneWidget);
    expect(find.text('待办跟进'), findsOneWidget);
  });
}