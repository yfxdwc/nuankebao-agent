// ============================================
// 客户分析图谱 (P4) widget 测试
// ============================================
// 守护的东西:
//   ① 雷达: 三维度**都有分**才画 (fl_chart 的 RadarDataSet assert ≥3 entry;
//      不足 3 个硬画 = 空维度落 0, 看着像"极差" → 误导)
//   ② 趋势: <2 个带疼痛评分的点不画线, 明确说"还差几次"
//   ③ 部位热力: 排列 + 止痛方向的显示 (↓改善 / 持平 / ↑变差 / — 无数据)
//   ④ 只显示**描述性统计** —— 界面文案里不出现"该用什么方案"这类医疗结论 (§1.3)
//   ⑤ 真主题下不出现"设了字号没 color"的文本 (AGENTS §5 白线 bug 防线)
//   ⑥ charts 拿不到时静默降级, 不拖垮分析 Tab
//
// 跑: cd flutter_app && flutter test test/customer_analysis_charts_test.dart
// ============================================

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer_charts.dart';
import 'package:nuankebao/core/models/customer_insight.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/customer_analysis_charts.dart';

// ---------- 夹具 ----------

ScoreDimension dim(String key, String label, double? score) => ScoreDimension(
      key: key,
      label: label,
      score: score,
      bandLabel: score == null ? "待评估" : "良好",
    );

CustomerScore score({double? effect = 70, double? engagement = 55, double? value = 80}) =>
    CustomerScore(
      overall: 66,
      overallBandLabel: "良好",
      effect: dim("effect", "健康改善", effect),
      engagement: dim("engagement", "关系温度", engagement),
      value: dim("value", "价值潜力", value),
    );

TrendPoint tp(int day, double? prePain, double? postPain) => TrendPoint(
      date: "2026-09-${day.toString().padLeft(2, '0')}",
      prePain: prePain,
      postPain: postPain,
      preSleep: 3,
      postSleep: 4,
    );

Widget host({
  required CustomerScore? s,
  CustomerCharts? charts,
  bool chartsError = false,
}) {
  final tokens = AppThemes.resolve(null);
  return ProviderScope(
    overrides: [
      customerChartsProvider("c1").overrideWith((ref) async {
        if (chartsError) throw Exception("boom");
        return charts ?? const CustomerCharts();
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light(tokens),
      home: Scaffold(
        body: SingleChildScrollView(
          child: CustomerAnalysisCharts(customerId: "c1", score: s),
        ),
      ),
    ),
  );
}

Future<void> pump(WidgetTester tester,
    {required CustomerScore? s, CustomerCharts? charts, bool chartsError = false}) async {
  await tester.binding.setSurfaceSize(const Size(500, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host(s: s, charts: charts, chartsError: chartsError));
  await tester.pumpAndSettle();
}

void main() {
  group("① 雷达图的门槛 (三维都有分才画)", () {
    testWidgets("三个维度都有分 → 真的画出 RadarChart", (tester) async {
      await pump(tester, s: score());
      expect(find.byType(RadarChart), findsOneWidget);
      expect(find.text("能力雷达"), findsOneWidget);
    });

    testWidgets("只有两个维度有分 → 不画雷达, 提示还差几个", (tester) async {
      await pump(tester, s: score(effect: null));
      expect(find.byType(RadarChart), findsNothing);
      expect(find.textContaining("还差 1 个维度"), findsOneWidget);
    });

    testWidgets("score 为 null (洞察未就绪) → 雷达显示空态, 整块不消失", (tester) async {
      await pump(tester, s: null);
      expect(find.byType(RadarChart), findsNothing);
      expect(find.text("能力雷达"), findsOneWidget); // 卡片标题仍在
      expect(find.textContaining("正在加载"), findsOneWidget);
    });

    testWidgets("一个维度都没分 → 还差 3 个 (不给空图)", (tester) async {
      await pump(tester, s: score(effect: null, engagement: null, value: null));
      expect(find.byType(RadarChart), findsNothing);
      expect(find.textContaining("还差 3 个维度"), findsOneWidget);
    });
  });

  group("①b 布局真的占位 (find.text 不查布局!)", () {
    // ⚠ 这条是**踩过坑才加的**: 组件根是 Column, 若它用了 CrossAxisAlignment.stretch
    //   而父级是垂直 ListView (无界高度) → 布局塌成 **0 高**。
    //   此时 find.text 仍然找得到 widget (完全不报错), 只有 getSize 才看得出来。
    //   真机上表现 = 整块图不可见, 排查了很久。
    testWidgets("根组件高度 > 0 (塌成 0 高时这条会挂)", (tester) async {
      await pump(
        tester,
        s: score(),
        charts: CustomerCharts(
          trend: [tp(2, 8, 4), tp(9, 7, 3)],
          bodyParts: [const BodyPartStat(id: "1", name: "肩颈", count: 3, medianPainDrop: 4)],
          recordCount: 3,
          scoredRecordCount: 2,
        ),
      );
      // 雷达(约 300) + 趋势(约 280) + 部位(约 200) → 总量应远超 600
      final h = tester.getSize(find.byType(CustomerAnalysisCharts)).height;
      expect(h, greaterThan(600),
          reason: "图表区塌成 ${h}px —— 多半是父级约束/交叉轴设置把高度吃掉了");
      // 每张卡的标题也要真的占位
      for (final title in ["能力雷达", "效果趋势", "部位分布"]) {
        expect(tester.getSize(find.text(title)).height, greaterThan(0),
            reason: "「$title」标题高度为 0");
      }
    });
  });

  group("② 趋势线的门槛", () {
    testWidgets("≥2 个带疼痛的点 → 画出 LineChart", (tester) async {
      await pump(
        tester,
        s: score(),
        charts: CustomerCharts(
          trend: [tp(2, 8, 4), tp(9, 7, 3), tp(16, 6, 3)],
          recordCount: 3,
          scoredRecordCount: 3,
        ),
      );
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text("效果趋势"), findsOneWidget);
    });

    testWidgets("只有 1 个点 → 不画线, 明确说还差几次", (tester) async {
      await pump(
        tester,
        s: score(),
        charts: CustomerCharts(trend: [tp(2, 8, 4)], recordCount: 1, scoredRecordCount: 1),
      );
      expect(find.byType(LineChart), findsNothing);
      expect(find.textContaining("至少 2 次"), findsOneWidget);
      expect(find.textContaining("当前 1 次"), findsOneWidget);
    });

    testWidgets("有记录但都没疼痛评分 → 也不画 (不拿 0 当数据)", (tester) async {
      await pump(
        tester,
        s: score(),
        charts: CustomerCharts(
          trend: [tp(2, null, null), tp(9, null, null)],
          recordCount: 2,
        ),
      );
      expect(find.byType(LineChart), findsNothing);
    });
  });

  group("③ 部位热力", () {
    CustomerCharts parts(List<BodyPartStat> ps) =>
        CustomerCharts(bodyParts: ps, recordCount: 3);

    testWidgets("列出部位 + 次数 + 止痛方向", (tester) async {
      await pump(
        tester,
        s: score(),
        charts: parts([
          const BodyPartStat(id: "1", name: "肩颈", count: 8, medianPainDrop: 4),
          const BodyPartStat(id: "2", name: "腰部", count: 5, medianPainDrop: 0),
          const BodyPartStat(id: "3", name: "膝盖", count: 2, medianPainDrop: -1.5),
          const BodyPartStat(id: "4", name: "头部", count: 2, medianPainDrop: null),
        ]),
      );
      expect(find.text("部位分布"), findsOneWidget);
      expect(find.text("肩颈"), findsOneWidget);
      expect(find.text("8 次"), findsOneWidget);
      expect(find.text("↓4.0"), findsOneWidget); // 改善
      expect(find.text("持平"), findsOneWidget); // 0
      expect(find.text("↑1.5"), findsOneWidget); // 变差
      expect(find.text("—"), findsOneWidget); // 无数据
    });

    testWidgets("没选过部位 → 提示怎么产生数据 (不留空白)", (tester) async {
      await pump(tester, s: score(), charts: const CustomerCharts());
      expect(find.textContaining("还没选过身体部位"), findsOneWidget);
      expect(find.textContaining("勾一下部位"), findsOneWidget);
    });

    testWidgets("超过 6 个部位只显示 6 个 + 提示还剩几个", (tester) async {
      await pump(
        tester,
        s: score(),
        charts: parts([
          for (var i = 0; i < 9; i++)
            BodyPartStat(id: "$i", name: "部位$i", count: 9 - i),
        ]),
      );
      expect(find.text("部位0"), findsOneWidget);
      expect(find.text("部位5"), findsOneWidget);
      expect(find.text("部位6"), findsNothing);
      expect(find.textContaining("还有 3 个部位"), findsOneWidget);
    });
  });

  group("④ CHARTER §1.3 边界 (不做医疗诊断)", () {
    testWidgets("界面文案里没有『建议/诊断/治疗/该怎么』这类结论", (tester) async {
      await pump(
        tester,
        s: score(),
        charts: CustomerCharts(
          trend: [tp(2, 8, 4), tp(9, 7, 3)],
          bodyParts: [const BodyPartStat(id: "1", name: "肩颈", count: 3, medianPainDrop: 4)],
          recordCount: 3,
          scoredRecordCount: 2,
        ),
      );
      final all = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .map((rp) => rp.text.toPlainText())
          .join(" ");
      for (final forbidden in ["建议", "诊断", "治疗", "应当", "该怎么"]) {
        expect(all, isNot(contains(forbidden)),
            reason: "界面里出现了医疗结论式文案「$forbidden」");
      }
    });
  });

  group("⑤ 健壮性", () {
    testWidgets("charts 请求失败 → 静默降级 (雷达仍在, 分析 Tab 不挂)", (tester) async {
      await pump(tester, s: score(), chartsError: true);
      expect(tester.takeException(), isNull);
      expect(find.byType(RadarChart), findsOneWidget); // 雷达不依赖 charts
      expect(find.text("效果趋势"), findsNothing); // 降级的只影响趋势/部位
    });

    testWidgets("真主题下 0 个『设了字号没 color』的文本", (tester) async {
      await pump(
        tester,
        s: score(),
        charts: CustomerCharts(
          trend: [tp(2, 8, 4), tp(9, 7, 3)],
          bodyParts: [const BodyPartStat(id: "1", name: "肩颈", count: 3, medianPainDrop: 4)],
          recordCount: 3,
          scoredRecordCount: 2,
        ),
      );
      var checked = 0;
      for (final rp in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
        final st = rp.text.style;
        if (st?.fontSize == null) continue;
        checked++;
        expect(st?.color, isNotNull, reason: '「${rp.text.toPlainText()}」有字号没 color');
      }
      expect(checked, greaterThan(3));
    });
  });
}
