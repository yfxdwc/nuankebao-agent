// ============================================
// 客户洞察 L0 (「现在该做」行动卡) —— widget 测试
// ============================================
// 2026-09-24: 文件从 customer_insight_header_test.dart 改名,
//   因为 L0 widget 从 CustomerInsightHeader 改成 CustomerInsightActions
//   (评分环已搬到分析 Tab = customer_score_card.dart 的范围)。
//   本文件**只守行动卡**, 评分相关的 ①②③ + 白字检查搬到 customer_score_card_test.dart。
//
// 守护的东西:
//   ④ 待办区: 有行动显示 / 无行动显示"节奏正常"
//   ⑤ 建任务回调能触发 (闭环)
//   ⑤b 认领归属闭环 (修 profile_incomplete 死路)
//   ⑥ 拿不到数据时静默降级, 不炸 (详情页其他部分不能跟着挂)
//
// ⚠ 必须带真主题 (AGENTS §5: 不带主题走 Flutter 默认样式, 测不出"主题顶掉默认样式"类 bug)
//
// 跑: cd flutter_app && flutter test test/customer_insight_actions_test.dart
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer_insight.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/customer_insight_actions.dart';

// ---------- 夹具 ----------

ScoreFactor f(String label, double score, double max, String detail) =>
    ScoreFactor(key: label, label: label, score: score, max: max, detail: detail);

ScoreDimension dim(String key, String label, double? score, String band,
        {List<ScoreFactor> factors = const [], String? missing}) =>
    ScoreDimension(
      key: key,
      label: label,
      score: score,
      bandLabel: band,
      factors: factors,
      missingReason: missing,
    );

ActionItem action({
  String id = "repurchase_window",
  String priority = "high",
  String title = "约下次到店",
  String why = "她的复购间隔通常 28 天, 已经 32 天没到店",
  String when = "今天",
  String channel = "phone",
  String cta = "create_task",
}) =>
    ActionItem(
      id: id,
      priority: priority,
      title: title,
      why: why,
      when: when,
      channel: channel,
      expected: "约到具体日期",
      taskTitle: title,
      taskDueAt: "2026-09-23T09:00:00.000Z",
      cta: cta,
    );

CustomerInsight insight({
  double? overall = 72,
  String band = "良好",
  List<ActionItem>? actions,
  ScoreDimension? effect,
  ScoreDimension? engagement,
  ScoreDimension? value,
  List<String> weak = const [],
}) =>
    CustomerInsight(
      score: CustomerScore(
        overall: overall,
        overallBandLabel: band,
        effect: effect ??
            dim("effect", "健康改善", 68, "良好", factors: [
              f("最近一次改善", 29, 40, "上次做完有改善 (+45%)"),
              f("近 3 次平均", 30, 40, "平均改善 +40%"),
            ]),
        engagement: engagement ?? dim("engagement", "关系温度", 72, "良好"),
        value: value ?? dim("value", "价值潜力", 76, "良好"),
        weakDimensions: weak,
      ),
      actions: actions ?? const [],
      topActions: actions ?? const [],
    );

/// ⚠ 关键: 带真主题 + 真实字体缩放, 跟生产一致
Widget host(
  CustomerInsight data, {
  Future<void> Function(ActionItem)? onBuild,
  Future<void> Function(ActionItem)? onClaim,
}) {
  final tokens = AppThemes.resolve(null);
  return ProviderScope(
    overrides: [
      customerInsightProvider("1").overrideWith((ref) async => data),
    ],
    child: MaterialApp(
      theme: AppTheme.light(tokens),
      home: Scaffold(
        body: CustomerInsightActions(
          customerId: "1",
          onBuildTask: onBuild ?? (_) async {},
          onClaim: onClaim ?? (_) async {},
        ),
      ),
    ),
  );
}

Future<void> pump(
  WidgetTester tester,
  CustomerInsight data, {
  Future<void> Function(ActionItem)? onBuild,
  Future<void> Function(ActionItem)? onClaim,
}) async {
  await tester.pumpWidget(host(data, onBuild: onBuild, onClaim: onClaim));
  await tester.pumpAndSettle();
}

void main() {
  group("④ 待办区 (§1.4 行动输出)", () {
    testWidgets("有待办 → 显示标题 + why (可核对的数字)", (tester) async {
      await pump(tester, insight(actions: [action()]));
      expect(find.textContaining("现在该做"), findsOneWidget);
      expect(find.text("约下次到店"), findsWidgets);
      expect(find.textContaining("已经 32 天没到店"), findsOneWidget);
      expect(find.textContaining("今天"), findsWidgets);
      expect(find.text("建任务"), findsOneWidget);
    });

    testWidgets("无待办 → 明确说「节奏正常」(不留空白让销售困惑)", (tester) async {
      await pump(tester, insight(actions: []));
      expect(find.textContaining("节奏正常"), findsOneWidget);
      expect(find.text("建任务"), findsNothing);
    });

    testWidgets("多条待办都渲染", (tester) async {
      await pump(tester, insight(actions: [
        action(),
        action(id: "contact_gap", priority: "medium", title: "主动联系一下", when: "本周", channel: "wechat"),
      ]));
      expect(find.textContaining("现在该做 (2)"), findsOneWidget);
      expect(find.text("建任务"), findsNWidgets(2));
    });
  });

  group("⑤ 建任务闭环", () {
    testWidgets("点「建任务」→ 回调收到对应 action + 变成已建", (tester) async {
      ActionItem? received;
      await pump(
        tester,
        insight(actions: [action()]),
        onBuild: (a) async => received = a,
      );

      await tester.tap(find.text("建任务"));
      await tester.pumpAndSettle();

      expect(received, isNotNull);
      expect(received!.id, "repurchase_window");
      expect(received!.taskTitle, "约下次到店");
      // 按钮变成「已建任务」(防重复建)
      expect(find.text("已建任务"), findsOneWidget);
      expect(find.text("建任务"), findsNothing);
    });

    testWidgets("建任务失败不崩 (回调抛异常)", (tester) async {
      await pump(
        tester,
        insight(actions: [action()]),
        onBuild: (a) async => throw Exception("network"),
      );
      await tester.tap(find.text("建任务"));
      await tester.pumpAndSettle();
      // 不崩即通过 (详情页其他部分不能被拖垮)
      expect(find.text("约下次到店"), findsWidgets);
    });
  });

  group("⑤b 认领归属闭环 (修 profile_incomplete 死路)", () {
    ActionItem claimAction() => action(
          id: "profile_incomplete",
          priority: "low",
          title: "认领为我的客户",
          why: "这个客户还没有归属人, 不认领的话不在任何人的客户列表里",
          when: "本周",
          channel: "profile",
          cta: "claim_ownership",
        );

    testWidgets("cta=claim_ownership → 按钮是「认领」而不是「建任务」", (tester) async {
      // 修之前: 这条行动的按钮是「建任务」→ 建任务不碰 owner_id → 行动永远消不掉
      await pump(tester, insight(actions: [claimAction()]));
      expect(find.widgetWithText(TextButton, "认领"), findsOneWidget);
      expect(find.text("建任务"), findsNothing);
      // 标题仍是全称 (标题 + 按钮文案要不同, 否则同一行重复)
      expect(find.text("认领为我的客户"), findsWidgets);
    });

    testWidgets("点它 → 走 onClaim, **不**走 onBuildTask", (tester) async {
      ActionItem? viaClaim;
      ActionItem? viaBuild;
      await pump(
        tester,
        insight(actions: [claimAction()]),
        onClaim: (a) async => viaClaim = a,
        onBuild: (a) async => viaBuild = a,
      );

      await tester.tap(find.widgetWithText(TextButton, "认领"));
      await tester.pumpAndSettle();

      expect(viaClaim, isNotNull);
      expect(viaClaim!.id, "profile_incomplete");
      expect(viaBuild, isNull, reason: "认领类行动不该去建任务");
    });

    testWidgets("点后显示「已认领」(不是「已建任务」—— 它压根没建任务)", (tester) async {
      await pump(tester, insight(actions: [claimAction()]));
      await tester.tap(find.widgetWithText(TextButton, "认领"));
      await tester.pumpAndSettle();

      expect(find.text("已认领"), findsOneWidget);
      expect(find.text("已建任务"), findsNothing);
    });

    testWidgets("认领失败不崩 (回调抛异常)", (tester) async {
      await pump(
        tester,
        insight(actions: [claimAction()]),
        onClaim: (a) async => throw Exception("409"),
      );
      await tester.tap(find.widgetWithText(TextButton, "认领"));
      await tester.pumpAndSettle();
      expect(find.text("认领为我的客户"), findsWidgets);
    });

    testWidgets("回归: cta=create_task 的行动仍走「建任务」", (tester) async {
      await pump(tester, insight(actions: [action()]));
      expect(find.text("建任务"), findsOneWidget);
      expect(find.widgetWithText(TextButton, "认领"), findsNothing);
    });
  });

  group("⑥ 静默降级", () {
    testWidgets("provider 报错 → 整块消失, 不炸 (详情页其他 section 要活)", (tester) async {
      final tokens = AppThemes.resolve(null);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerInsightProvider("1")
                .overrideWith((ref) async => throw Exception("boom")),
          ],
          child: MaterialApp(
            theme: AppTheme.light(tokens),
            home: const Scaffold(
              body: CustomerInsightActions(
                  customerId: "1", onBuildTask: _noop, onClaim: _noop),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomerInsightActions), findsOneWidget);
    });
  });
}

Future<void> _noop(ActionItem a) async {}