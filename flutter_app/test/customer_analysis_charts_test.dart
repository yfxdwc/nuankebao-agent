// ============================================
// 客户分析图谱 widget 测试 (2026-09-24 砍雷达后)
// ============================================
// 守护的东西:
//   ② 趋势图: <2 个带疼痛评分的点不画线, 明确说"还差几次" (P0 进度化空态)
//   ②b 进度化空态: pts==1 / pts==0 + 有记录 / pts==0 + 没记录, 三档区分
//   ③ 部位热力: 排列 + 止痛方向的显示 (↓改善 / 持平 / ↑变差 / — 无数据)
//   ③b 部位空态: recordCount>0 + 没勾部位 vs 没记录
//   ④ CHARTER §1.3 边界: 界面文案里不出现"该用什么方案"这类医疗结论
//   ⑤ 真主题下不出现"设了字号没 color"的文本 (AGENTS §5 白线 bug 防线)
//   ⑥ charts 拿不到时显示「图表没加载出来」+「重新加载」 (不再静默降级)
//
// 2026-09-24 主人拍板砍掉「能力雷达图」: 同源重复 + 3 维可读性差 + 分析 Tab 太长。
//   雷达相关 group/断言整段移除; 趋势图 + 部位图保留。
//
// 跑: cd flutter_app && flutter test test/customer_analysis_charts_test.dart
// ============================================

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer_charts.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/customer_analysis_charts.dart';

// ---------- 夹具 ----------

TrendPoint tp(int day, double? prePain, double? postPain) => TrendPoint(
      date: "2026-09-${day.toString().padLeft(2, '0')}",
      prePain: prePain,
      postPain: postPain,
      preSleep: 3,
      postSleep: 4,
    );

/// ⚠ 不再收 score 参数 (雷达已删, 2026-09-24)
Widget host({
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
          child: CustomerAnalysisCharts(customerId: "c1"),
        ),
      ),
    ),
  );
}

Future<void> pump(WidgetTester tester,
    {CustomerCharts? charts, bool chartsError = false}) async {
  await tester.binding.setSurfaceSize(const Size(500, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host(charts: charts, chartsError: chartsError));
  await tester.pumpAndSettle();
}

void main() {
  group("①b 布局真的占位 (find.text 不查布局!)", () {
    // ⚠ 这条是**踩过坑才加的**: 组件根是 Column, 若它用了 CrossAxisAlignment.stretch
    //   而父级是垂直 ListView (无界高度) → 布局塌成 **0 高**。
    //   此时 find.text 仍然找得到 widget (完全不报错), 只有 getSize 才看得出来。
    //   真机上表现 = 整块图不可见, 排查了很久。
    //
    // 2026-09-24 砍雷达后: 趋势图 (~280) + 部位图 (~200) = ~480, 但每张卡
    //   还有标题 + 副标题 + 内边距 ~50px, 总量 ~580-600。阈值从 >600 降到 >400
    //   (因为雷达占位没了)。
    testWidgets("根组件高度 > 0 (塌成 0 高时这条会挂)", (tester) async {
      await pump(
        tester,
        charts: CustomerCharts(
          trend: [tp(2, 8, 4), tp(9, 7, 3)],
          bodyParts: [
            const BodyPartStat(id: "1", name: "肩颈", count: 3, medianPainDrop: 4),
          ],
          recordCount: 3,
          scoredRecordCount: 2,
        ),
      );
      final h = tester.getSize(find.byType(CustomerAnalysisCharts)).height;
      // 实测 ~395px (趋势图 210 + 部位图占位 ~150 + 标题/padding/gaps)。
      // 砍雷达前是 >600; 阈值放宽到 >300 仍能挡住"塌成 0 高"的 bug (那种情况 h≈0)。
      expect(h, greaterThan(300),
          reason: "图表区塌成 ${h}px —— 多半是父级约束/交叉轴设置把高度吃掉了");
      // 雷达已删, 只剩趋势图 + 部位图 标题
      for (final title in ["效果趋势", "部位分布"]) {
        expect(tester.getSize(find.text(title)).height, greaterThan(0),
            reason: "「$title」标题高度为 0");
      }
    });
  });

  group("② 趋势图的门槛", () {
    testWidgets("≥2 个带疼痛的点 → 画出 LineChart", (tester) async {
      await pump(
        tester,
        charts: CustomerCharts(
          trend: [tp(2, 8, 4), tp(9, 7, 3), tp(16, 6, 3)],
          recordCount: 3,
          scoredRecordCount: 3,
        ),
      );
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text("效果趋势"), findsOneWidget);
    });

    testWidgets("只有 1 个点 → 进度化空态:「再记 1 次就能画」", (tester) async {
      await pump(
        tester,
        charts: CustomerCharts(
          trend: [tp(2, 8, 4)],
          recordCount: 1,
          scoredRecordCount: 1,
        ),
      );
      expect(find.byType(LineChart), findsNothing);
      expect(find.textContaining("至少 2 次"), findsOneWidget);
      expect(find.textContaining("再记 1 次"), findsOneWidget);
    });

    testWidgets("pts=0 + 有记录但都没疼痛评分 → 提示「都还没填疼痛评分」", (tester) async {
      await pump(
        tester,
        charts: CustomerCharts(
          trend: [tp(2, null, null), tp(9, null, null)],
          recordCount: 5, // 有 5 条记录, 但都没填疼痛
        ),
      );
      expect(find.byType(LineChart), findsNothing);
      expect(find.textContaining("至少 2 次"), findsOneWidget);
      expect(find.textContaining("都还没填疼痛评分"), findsOneWidget);
      // 趋势 / 部位空态都引用了「已有 5 条记录」, 用 findsWidgets
      expect(find.textContaining("已有 5 条记录"), findsWidgets);
    });

    testWidgets("pts=0 + recordCount=0 → 提示「先记一次」", (tester) async {
      await pump(
        tester,
        charts: const CustomerCharts(),
      );
      expect(find.byType(LineChart), findsNothing);
      expect(find.textContaining("至少 2 次"), findsOneWidget);
      // 「还没有养生记录」同文同时被趋势 + 部位两张卡渲染, 用 findsWidgets
      expect(find.textContaining("还没有养生记录"), findsWidgets);
    });

    testWidgets("有记录但都没疼痛评分 → 也不画 (不拿 0 当数据)", (tester) async {
      await pump(
        tester,
        charts: CustomerCharts(
          trend: [tp(2, null, null), tp(9, null, null)],
          recordCount: 2,
        ),
      );
      expect(find.byType(LineChart), findsNothing);
    });
  });

  group("③ 部位热力", () {
    CustomerCharts parts(List<BodyPartStat> ps, {int recordCount = 3}) =>
        CustomerCharts(bodyParts: ps, recordCount: recordCount);

    testWidgets("列出部位 + 次数 + 止痛方向", (tester) async {
      await pump(
        tester,
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

    testWidgets("recordCount>0 但没选过部位 → 提示「都还没勾部位」", (tester) async {
      await pump(
        tester,
        charts: const CustomerCharts(recordCount: 4),
      );
      expect(find.textContaining("还没选过身体部位"), findsOneWidget);
      expect(find.textContaining("都还没勾部位"), findsOneWidget);
      // 「已有 4 条记录」同文同时被趋势 + 部位两张卡渲染
      expect(find.textContaining("已有 4 条记录"), findsWidgets);
    });

    testWidgets("没记录 → 提示「还没有养生记录, 先记一次」", (tester) async {
      await pump(tester, charts: const CustomerCharts());
      expect(find.textContaining("还没选过身体部位"), findsOneWidget);
      // 「还没有养生记录」同文同时被趋势 + 部位两张卡渲染
      expect(find.textContaining("还没有养生记录"), findsWidgets);
    });

    testWidgets("超过 6 个部位只显示 6 个 + 提示还剩几个", (tester) async {
      await pump(
        tester,
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
    testWidgets("charts 请求失败 → 「图表没加载出来」+「重新加载」按钮 (不崩)", (tester) async {
      await pump(tester, chartsError: true);
      expect(tester.takeException(), isNull);
      expect(find.text("图表没加载出来"), findsOneWidget);
      expect(find.text("重新加载"), findsOneWidget);
      // 趋势 / 部位都拿不到数据 → 不应该有 LineChart / 部位标题
      expect(find.byType(LineChart), findsNothing);
      expect(find.text("效果趋势"), findsNothing);
      expect(find.text("部位分布"), findsNothing);
    });

    testWidgets("真主题下 0 个『设了字号没 color』的文本", (tester) async {
      await pump(
        tester,
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