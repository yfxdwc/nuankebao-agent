// 临时验证 (2026-09-18 客户详情页丰富: 养生记录 + AI 4 卡 + 跟进 + 互动) — 出图后删
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuankebao/core/models/ai_insight.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/models/wellness_record.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/customer/screens/customers_page.dart';

class _FakeAi extends AiService {
  _FakeAi() : super(Dio());

  @override
  Future<RepurchasePrediction> repurchasePrediction(String customerId) async =>
      const RepurchasePrediction(
        customerId: '1',
        lastVisit: '2026-09-16',
        daysSinceLastVisit: 2,
        avgIntervalDays: 4,
        predictedNextVisit: '2026-09-20',
        daysUntilPredicted: 1,
        confidence: 'high',
        reason: '预计 1 天内会复购, 可主动联系',
      );

  @override
  Future<CustomerProfileInsight> profileInsight(String customerId) async =>
      const CustomerProfileInsight(
        aiSummary: '45-55 岁女性, 主要问题是肩颈劳损 + 睡眠差; 到店 4 次, 对热敷理疗反应好; 建议主推肩颈疗程。',
        recentSummaries: ['2026-09-16 · 肩颈经络理疗 · 肩颈'],
      );

  @override
  Future<FollowUpSuggestion> followUpInsight(String customerId,
          {String? reason}) async =>
      const FollowUpSuggestion(
        suggestion: '王姐您好, 上次做完肩颈说轻松多了, 这两天睡得怎么样? 我这边周四下午还有空档, 给您留一个?',
        reason: '好久没来了',
        daysSinceLastVisit: 2,
        avgInterval: 4,
      );

  @override
  Future<EffectAnalysis> effectAnalysis(String customerId) async =>
      const EffectAnalysis(
        totalVisits: 4,
        trend: 'improving',
        aiSummary: '4 次记录里 3 次反馈"明显好转", 趋势向上; 建议继续当前疗程 2 次巩固。',
        from: '2026-09-01',
        to: '2026-09-16',
      );
}

void main() {
  testWidgets('客户详情页: 丰富内容渲染', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final customer = Customer(
      id: '1',
      name: '王女士',
      phone: '13912345678',
      gender: 'F',
      birthYear: 1968,
      healthTags: ['肩颈劳损', '睡眠差'],
      diseaseHistory: '高血压(服药中)',
      customerType: 'seed',
      isSeed: true,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 9, 16),
    );

    WellnessRecord rec(int i) => WellnessRecord(
          id: '$i',
          customerId: '1',
          serviceDate: '2026-09-${(16 - i).toString().padLeft(2, '0')}',
          serviceItemId: '1',
          bodyPartIds: const ['1'],
          customerFeedback: i == 0 ? '轻松多了' : null,
          createdAt: DateTime(2026, 9, 16),
        );

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const CustomerDetailPage(customerId: '1')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerDetailProvider.overrideWith((ref, id) async => customer),
          customerWellnessRecordsProvider
              .overrideWith((ref, id) async => List.generate(6, rec)),
          aiServiceProvider.overrideWithValue(_FakeAi()),
          customerFollowUpTasksProvider.overrideWith((ref, id) async => [
                FollowUpTask(
                  id: '21',
                  customerId: '1',
                  dueAt: DateTime.now().add(const Duration(days: 1)),
                  reason: '打电话问腰疼好点没',
                  status: 'pending',
                  createdAt: DateTime.now(),
                ),
              ]),
          interactionsForCustomerProvider.overrideWith((ref, id) async => [
                Interaction(
                  id: '2',
                  customerId: '1',
                  type: 'phone',
                  summary: '聊了腰疼好多了, 约下周三到店',
                  createdBy: '1',
                  createdAt: DateTime(2026, 9, 18),
                ),
              ]),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    // 头部 + 养生记录 + AI 区标题
    expect(find.text('王女士'), findsOneWidget);
    expect(find.text('养生记录'), findsWidgets); // 区块标题 + 每条记录 tile 标题
    expect(find.text('共 6 次 · 最近 2026-09-16'), findsOneWidget);
    expect(find.text('查看全部 6 条'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/detail-01-top.png'));

    // 滚到 AI 区 (复购预测自动加载 + 其余点按钮生成)
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.text('复购预测'), findsOneWidget);
    expect(find.text('4 天'), findsOneWidget);      // 平均复购周期 (自动算出来)
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/detail-02-ai.png'));

    // 生成话术 (点一下) → 出结果 + 复制/建跟进按钮
    await tester.scrollUntilVisible(find.text('生成跟进话术'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('生成跟进话术'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('王姐您好'), findsOneWidget);
    expect(find.text('复制话术'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/detail-03-ai-result.png'));

    // 滚到底: 跟进任务 + 互动记录
    await tester.scrollUntilVisible(find.text('互动记录'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('跟进任务'), findsWidgets);
    expect(find.text('打电话问腰疼好点没'), findsOneWidget);
    expect(find.text('互动记录'), findsOneWidget);
    expect(find.textContaining('聊了腰疼好多了'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/detail-04-bottom.png'));

    expect(tester.takeException(), isNull);
  });
}
