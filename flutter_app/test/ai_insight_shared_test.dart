// ============================================
// P5 守护: 三张 AI 卡共用**一次**调用
// ============================================
// 主人 2026-09-23 拍「AI 4 卡合并成 1 次调用」。
// 这个测试守的就是这句话 —— 后端已有 `aiCallCount === 1` 断言, 这里守客户端:
//
//   ① 初始**不发请求** (进页就烧 AI 是绝对不行的)
//   ② 点话术卡 (唯一入口) 的「生成 AI 解读」→ 只打 **1 次** /ai/insight
//   ③ 同一次结果驱动**三张卡** (画像 / 话术 / 效果) 同时出内容
//   ④ 重新生成仍只打 1 次
//   ⑤ 跟进理由存在共享状态里 (跨卡不丢)
//   ⑥ 事实底稿能渲染 + 样本来源范围 (P0)
//   ⑦ P0 会员锁态: scriptAvailable=false → 话术卡出「升级会员」按钮 + 锁块;
//                  其他两张卡出同款锁块, 不出按钮, 提示「点上方...」
//
// ⚠ 必须带真主题 (AppTheme.light(tokens)) —— 不带主题走 Flutter 默认样式,
//   白字/零高这类真机 bug 永远测不出来 (AGENTS §5 已沉过坑)。
//
// ⚠ 必须 override `customerInsightProvider('798')` 返回带 scriptAvailable 的
//   CustomerInsight —— 否则 host 里 ai_insight_cards 会**真的**去打网络接口
//   (本次 P0 锁态改造后这点尤其明显, 没 override = real network = 挂)。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/ai_insight.dart';
import 'package:nuankebao/core/models/customer_insight.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/ai_insight_cards.dart';

/// 假的 AiService: 只数调用次数, 不发网络
class _FakeAiService extends AiService {
  _FakeAiService() : super(Dio());

  int insightCalls = 0;
  String? lastReason;

  @override
  Future<AiInsightResult> insight(String customerId, {String? reason}) async {
    insightCalls++;
    lastReason = reason;
    return AiInsightResult(
      customerId: customerId,
      customerName: '测试客户',
      sections: const AiInsightSections(
        profile: '画像段内容',
        followUp: '话术段内容',
        effect: '效果段内容',
      ),
      facts: const AiInsightFacts(
        totalVisits: 5,
        daysSinceLastVisit: 28,
        avgIntervalDays: 35,
        trend: 'improving',
        reason: '复购周期提醒',
        dateFrom: '2026-06-25',
        dateTo: '2026-09-25',
      ),
    );
  }
}

/// 给 host 提供一个带 scriptAvailable=true 的 CustomerInsight,
/// 不打真网络 (P0 锁态改造后, AiFollowUpCard 会 watch customerInsightProvider)。
CustomerInsight _insightAvailable({bool scriptAvailable = true}) {
  // 用 fromJson 简单构造, scriptAvailable 是顶层字段
  return CustomerInsight.fromJson({'scriptAvailable': scriptAvailable});
}

/// ⚠ 必须提供 prefs: `usageServiceProvider` (埋点) 依赖 sharedPreferencesProvider,
///   不 override 会在 `_trackAiClick` 抛 UnimplementedProviderError, 把 generate 打断
///   —— 表现为「点了按钮但一次调用都没发」(踩过)。
Future<Widget> _host(
  Widget child,
  _FakeAiService fake, {
  bool scriptAvailable = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiServiceProvider.overrideWithValue(fake),
      customerInsightProvider('798')
          .overrideWith((ref) async => _insightAvailable(scriptAvailable: scriptAvailable)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

/// 三张卡按分析 Tab 的顺序排: 话术 (主入口) → 画像 → 效果
Widget _threeCards() => const Column(
      children: [
        AiFollowUpCard(customerId: '798'),
        AiProfileCard(customerId: '798'),
        EffectAnalysisCard(customerId: '798'),
      ],
    );

void main() {
  testWidgets('① 初始不发请求 —— 进页不烧 AI', (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(await _host(_threeCards(), fake));
    await tester.pumpAndSettle();

    expect(fake.insightCalls, 0);
    // P2: 只有话术卡出「生成 AI 解读」按钮 (单入口); 画像/效果卡改为
    // 「点上方「生成 AI 解读」」提示
    expect(find.text('生成 AI 解读'), findsOneWidget);
    expect(find.text('生成客户画像'), findsNothing);
    expect(find.text('生成效果分析'), findsNothing);
    // 「点上方…」提示应有 2 处 (画像卡 + 效果卡)
    expect(find.textContaining('点上方'), findsNWidgets(2));
  });

  testWidgets('②③ 点一次生成 → 只打 1 次调用 + 三张卡同时出内容', (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(await _host(_threeCards(), fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成 AI 解读'));
    await tester.pumpAndSettle();

    // ② 只一次 (P5 的核心)
    expect(fake.insightCalls, 1);

    // ③ 三张卡都吃到了同一次的结果
    expect(find.textContaining('画像段内容'), findsOneWidget);
    expect(find.textContaining('话术段内容'), findsOneWidget);
    expect(find.textContaining('效果段内容'), findsOneWidget);
  });

  testWidgets('④ 从别的卡重新生成, 仍只打 1 次', (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(await _host(_threeCards(), fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成 AI 解读'));
    await tester.pumpAndSettle();
    expect(fake.insightCalls, 1);

    // 已有结果 → 三张卡都出现「重新生成」按钮
    expect(find.byTooltip('重新生成'), findsNWidgets(3));

    await tester.tap(find.byTooltip('重新生成').first);
    await tester.pumpAndSettle();

    expect(fake.insightCalls, 2); // 只多一次, 不是三次
  });

  testWidgets('⑤ 跟进理由走共享状态 (跨卡不丢)', (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(await _host(_threeCards(), fake));
    await tester.pumpAndSettle();

    // 在跟进卡选一个理由 → 立刻触发一次生成, 理由带过去
    await tester.tap(find.text('好久没来了'));
    await tester.pumpAndSettle();

    expect(fake.insightCalls, 1);
    expect(fake.lastReason, '好久没来了');
  });

  testWidgets('事实底稿能渲染 (累计/距上次/平均/趋势) + 数据范围 (P0)', (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(await _host(_threeCards(), fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成 AI 解读'));
    await tester.pumpAndSettle();

    expect(find.text('累计 5 次'), findsWidgets);
    expect(find.text('距上次 28 天'), findsWidgets);
    expect(find.text('平均 35 天一次'), findsWidgets);
    expect(find.text('趋势 改善中'), findsWidgets);
    // P0: facts.dateFrom/dateTo 都非空 → footer 出「数据范围:」
    expect(find.textContaining('数据范围:'), findsOneWidget);
    expect(find.textContaining('2026-06-25'), findsOneWidget);
    expect(find.textContaining('2026-09-25'), findsOneWidget);
  });

  testWidgets('P0 锁态: scriptAvailable=false → 无「生成 AI 解读」, 出「升级会员」',
      (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(
      await _host(_threeCards(), fake, scriptAvailable: false),
    );
    await tester.pumpAndSettle();

    // 「生成 AI 解读」按钮不出
    expect(find.text('生成 AI 解读'), findsNothing);
    // 锁文案应出现 (3 处: 话术卡 + 画像卡 + 效果卡)
    expect(find.textContaining('升级会员可看 AI 解读'), findsNWidgets(3));
    // 只有话术卡 (primaryEntry) 出「升级会员」按钮
    expect(find.text('升级会员'), findsOneWidget);
    // 跟进理由 ChoiceChip 在锁态下隐藏 (选了就要触发, 锁态下点了会白出锁块)
    expect(find.text('好久没来了'), findsNothing);
    expect(find.text('想约她到店'), findsNothing);
    expect(find.text('生日/节日问候'), findsNothing);
    expect(find.text('该复购了'), findsNothing);

    // 锁态下点「升级会员」不会真打 insight 调用 (埋点/调用计数都不变)
    await tester.tap(find.text('升级会员'));
    await tester.pumpAndSettle();
    expect(fake.insightCalls, 0);
  });
}