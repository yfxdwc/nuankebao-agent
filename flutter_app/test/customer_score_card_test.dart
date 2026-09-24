// ============================================
// 客户评分卡 (分析 Tab) —— widget 测试
// ============================================
// 2026-09-24 新建 (从 customer_insight_header_test.dart 的 ①②③ 拆出来)。
//
// 背景: 主人 2026-09-24 拍板把评分卡从 L0 搬到分析 Tab。本文件只守评分卡 widget。
//
// 守护的东西:
//   ① 真主题下能渲染 (⚠ 必须带 AppTheme.light(tokens) —— 见 AGENTS §5:
//      "测 UI 的 widget test 必须带到真主题, 不带主题 = 走 Flutter 默认样式,
//       这类 bug 永远测不出来")
//   ①b 评分环显示正确数字 + 分档
//   ①c 数据不足的维度不假装 0 分, 而是显示 missingReason
//   ①d 全部文字对卡片底可读 (不出现白字白底, AGENTS §5 真机白字教训)
//   ② 总体无分时环显示 — 而不是 0
//   ③ 展开: 可解释性 —— 销售要能核对"为什么这个分"
//
// 跑: cd flutter_app && flutter test test/customer_score_card_test.dart
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer_insight.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/customer_score_card.dart';

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

CustomerInsight insight({
  double? overall = 72,
  String band = "良好",
  ScoreDimension? effect,
  ScoreDimension? engagement,
  ScoreDimension? value,
  List<String> weak = const [],
  List<ActionItem> actions = const [],
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
      actions: actions,
      topActions: actions,
    );

/// ⚠ 关键: 带真主题 + 真实字体缩放, 跟生产一致
Widget host(CustomerInsight data) {
  final tokens = AppThemes.resolve(null);
  return ProviderScope(
    overrides: [
      customerInsightProvider("1").overrideWith((ref) async => data),
    ],
    child: MaterialApp(
      theme: AppTheme.light(tokens),
      home: Scaffold(
        body: CustomerScoreCard(customerId: "1"),
      ),
    ),
  );
}

Future<void> pump(WidgetTester tester, CustomerInsight data) async {
  await tester.pumpWidget(host(data));
  await tester.pumpAndSettle();
}

void main() {
  group("① 渲染 (真主题下)", () {
    testWidgets("综合分 + 分档显示正确", (tester) async {
      // 用跟维度分不同的数字, 避免 "72" 同时命中评分环和维度条 (那是测试不够精确)
      await pump(tester, insight(overall: 83, band: "优秀"));
      expect(find.text("83"), findsOneWidget);
      expect(find.text("优秀"), findsOneWidget);
    });

    testWidgets("三个维度小条都渲染", (tester) async {
      await pump(tester, insight());
      expect(find.text("健康改善"), findsWidgets);
      expect(find.text("关系温度"), findsWidgets);
      expect(find.text("价值潜力"), findsWidgets);
    });

    testWidgets("评分环是真 CircularProgressIndicator 且 value 与分数一致", (tester) async {
      await pump(tester, insight(overall: 72));
      final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator).first,
      );
      expect(ring.value, closeTo(0.72, 0.001));
    });

    testWidgets("全部文字对卡片底可读 (不出现白字白底)", (tester) async {
      await pump(tester, insight());
      final rps = tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      );
      for (final rp in rps) {
        final color = rp.text.style?.color;
        expect(color, isNotNull, reason: '「${rp.text.toPlainText()}」没写 color');
        // 纯白 = 白卡片上不可见 (历史真 bug)
        expect(color, isNot(const Color(0xFFFFFFFF)),
            reason: '「${rp.text.toPlainText()}」是纯白, 看不见');
      }
    });
  });

  group("② 数据不足的维度", () {
    testWidgets("不假装 0 分, 显示 — 而不是 0", (tester) async {
      await pump(
        tester,
        insight(
          effect: dim("effect", "健康改善", null, "待评估",
              missing: "还没有带评分 (疼痛/睡眠/情绪) 的养生记录"),
        ),
      );
      // 收起态: 该维度条显示「—」(不是 0)
      expect(find.text("—"), findsOneWidget);

      // 展开后: 看到"待评估" + 缺什么
      await tester.tap(find.text("健康改善").first);
      await tester.pumpAndSettle();
      expect(find.text("待评估"), findsOneWidget);
      expect(find.textContaining("还没有带评分"), findsOneWidget);
    });

    testWidgets("总体无分时环显示 — 而不是 0", (tester) async {
      await pump(tester, insight(overall: null, band: "待评估"));
      expect(find.text("—"), findsWidgets);
      final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator).first,
      );
      expect(ring.value, 0); // 环不画进度, 但**不显示数字 0**
    });
  });

  group("③ 展开: 可解释性", () {
    testWidgets("默认收起 (分析 Tab 要克制), 点一下展开", (tester) async {
      await pump(tester, insight());
      expect(find.text("最近一次改善"), findsNothing);

      await tester.tap(find.text("健康改善").first);
      await tester.pumpAndSettle();

      // 因子明细出来: 标签 + 分值 + 人话
      expect(find.text("最近一次改善"), findsOneWidget);
      expect(find.text("29/40"), findsOneWidget);
      expect(find.text("上次做完有改善 (+45%)"), findsOneWidget);
    });
  });
}