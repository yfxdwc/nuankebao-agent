// ============================================
// P5 守护: 三张 AI 卡共用**一次**调用
// ============================================
// 主人 2026-09-23 拍「AI 4 卡合并成 1 次调用」。
// 这个测试守的就是这句话 —— 后端已有 `aiCallCount === 1` 断言, 这里守客户端:
//
//   ① 初始**不发请求** (进页就烧 AI 是绝对不行的)
//   ② 点任意一张卡的「生成」→ 只打 **1 次** /ai/insight
//   ③ 同一次结果驱动**三张卡** (画像 / 话术 / 效果) 同时出内容
//   ④ 重新生成仍只打 1 次
//   ⑤ 跟进理由存在共享状态里 (跨卡不丢)
//
// ⚠ 必须带真主题 (AppTheme.light(tokens)) —— 不带主题走 Flutter 默认样式,
//   白字/零高这类真机 bug 永远测不出来 (AGENTS §5 已沉过坑)。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/ai_insight.dart';
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
      ),
    );
  }
}

/// ⚠ 必须提供 prefs: `usageServiceProvider` (埋点) 依赖 sharedPreferencesProvider,
///   不 override 会在 `_trackAiClick` 抛 UnimplementedProviderError, 把 generate 打断
///   —— 表现为「点了按钮但一次调用都没发」(踩过)。
Future<Widget> _host(Widget child, _FakeAiService fake) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

Widget _threeCards() => const Column(
      children: [
        AiProfileCard(customerId: '798'),
        AiFollowUpCard(customerId: '798'),
        EffectAnalysisCard(customerId: '798'),
      ],
    );

void main() {
  testWidgets('① 初始不发请求 —— 进页不烧 AI', (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(await _host(_threeCards(), fake));
    await tester.pumpAndSettle();

    expect(fake.insightCalls, 0);
    // 三张卡都停在「生成」按钮
    expect(find.text('生成客户画像'), findsOneWidget);
    expect(find.text('生成跟进话术'), findsOneWidget);
    expect(find.text('生成效果分析'), findsOneWidget);
  });

  testWidgets('②③ 点一次生成 → 只打 1 次调用 + 三张卡同时出内容', (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(await _host(_threeCards(), fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成客户画像'));
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

    await tester.tap(find.text('生成效果分析'));
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

  testWidgets('事实底稿能渲染 (累计/距上次/平均/趋势)', (tester) async {
    final fake = _FakeAiService();
    await tester.pumpWidget(await _host(_threeCards(), fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成客户画像'));
    await tester.pumpAndSettle();

    expect(find.text('累计 5 次'), findsWidgets);
    expect(find.text('距上次 28 天'), findsWidgets);
    expect(find.text('平均 35 天一次'), findsWidgets);
    expect(find.text('趋势 改善中'), findsWidgets);
  });
}
