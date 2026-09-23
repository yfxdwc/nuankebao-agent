// ============================================
// 养生记录卡片 单测 (记录页完善, 主人 2026-09-23)
// ============================================
// 守护的东西:
//   ① 字典翻译: serviceItemId/bodyPartIds → 名字; 查不到**不显示 #id** (宁可回落笼统文案)
//   ② 改善判定: 疼痛"降"是好事、睡眠"升"是好事 —— 方向相反最容易写反
//   ③ 只显示**前后都填了**的指标 (只填一半算改善 = 编数据)
//   ④ 卡片真渲染出项目名/部位/改善/反馈, 且**不是零高**
//      (P4 踩过: widget test 全绿但真机零高 —— 所以必须断言 getSize)
//
// ⚠ 必须带真主题 AppTheme.light(tokens) —— 不带主题走 Flutter 默认样式,
//   白字/零高这类真机 bug 永远测不出来 (AGENTS §5 已沉过坑)。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/dictionaries.dart';
import 'package:nuankebao/core/models/wellness_record.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/customer/widgets/record_tile.dart';

// ── fixtures ──

const _dict = Dictionaries(
  bodyParts: [
    BodyPart(id: '1', name: '肩颈'),
    BodyPart(id: '4', name: '头部'),
    BodyPart(id: '9', name: '腰部'),
  ],
  serviceItems: [
    ServiceItem(id: '2', name: '肩颈经络理疗'),
    ServiceItem(id: '7', name: '艾灸调理'),
  ],
);

WellnessRecord _rec({
  String serviceItemId = '2',
  List<String> bodyPartIds = const ['1'],
  Map<String, dynamic> pre = const {'pain_level': 8},
  Map<String, dynamic> post = const {'pain_level': 4},
  String? feedback = '挺舒服的, 下次还来',
  String serviceDate = '2026-09-22',
}) =>
    WellnessRecord(
      id: '100',
      customerId: '798',
      serviceDate: serviceDate,
      serviceItemId: serviceItemId,
      bodyPartIds: bodyPartIds,
      preCondition: pre,
      postCondition: post,
      customerFeedback: feedback,
      createdAt: DateTime(2026, 9, 22),
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(AppThemes.sage),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // ── ① 字典翻译 ──
  group("serviceItemName", () {
    test("id 命中 → 返回项目名", () {
      expect(serviceItemName(_dict, '2'), '肩颈经络理疗');
    });

    test("字典还没加载 (null) → null (调用方回落笼统文案)", () {
      expect(serviceItemName(null, '2'), isNull);
    });

    test("id 查不到 → null, **不返回 #id 这种给用户看的垃圾**", () {
      expect(serviceItemName(_dict, '999'), isNull);
    });
  });

  group("bodyPartNames", () {
    test("按入参顺序返回名字", () {
      expect(bodyPartNames(_dict, ['9', '1']), ['腰部', '肩颈']);
    });

    test("查不到的 id 直接丢掉 (不留占位)", () {
      expect(bodyPartNames(_dict, ['1', '999', '4']), ['肩颈', '头部']);
    });

    test("字典为 null / 空 ids → 空列表", () {
      expect(bodyPartNames(null, ['1']), isEmpty);
      expect(bodyPartNames(_dict, []), isEmpty);
    });
  });

  // ── ② 改善判定 (方向相反, 最容易写反) ──
  group("MetricDelta 改善方向", () {
    MetricDelta mk(int pre, int post, {required bool lowerIsBetter}) =>
        MetricDelta(
            label: 'x', pre: pre, post: post, lowerIsBetter: lowerIsBetter);

    test("疼痛 (越小越好): 8→4 是改善, 4→8 是变差", () {
      expect(mk(8, 4, lowerIsBetter: true).isImprovement, isTrue);
      expect(mk(8, 4, lowerIsBetter: true).isWorsening, isFalse);
      expect(mk(4, 8, lowerIsBetter: true).isImprovement, isFalse);
      expect(mk(4, 8, lowerIsBetter: true).isWorsening, isTrue);
    });

    test("睡眠 (越大越好): 5→7 是改善, 7→5 是变差 —— 与疼痛相反", () {
      expect(mk(5, 7, lowerIsBetter: false).isImprovement, isTrue);
      expect(mk(5, 7, lowerIsBetter: false).isWorsening, isFalse);
      expect(mk(7, 5, lowerIsBetter: false).isImprovement, isFalse);
      expect(mk(7, 5, lowerIsBetter: false).isWorsening, isTrue);
    });

    test("持平 → 既不是改善也不是变差", () {
      final m = mk(5, 5, lowerIsBetter: true);
      expect(m.isImprovement, isFalse);
      expect(m.isWorsening, isFalse);
      expect(m.rawDelta, 0);
    });

    test("缺一半 → isComplete=false, rawDelta=null (不猜)", () {
      final m = MetricDelta(
          label: 'x', pre: null, post: 4, lowerIsBetter: true);
      expect(m.isComplete, isFalse);
      expect(m.rawDelta, isNull);
      expect(m.isImprovement, isFalse);
    });
  });

  // ── ③ metricDeltas 抽取 ──
  group("metricDeltas", () {
    test("顺序固定 疼痛 → 睡眠 → 情绪 (疼痛排第一)", () {
      final r = _rec(
        pre: {'pain_level': 8, 'sleep_quality': 4, 'mood': 5},
        post: {'pain_level': 4, 'sleep_quality': 7, 'mood': 6},
      );
      expect(metricDeltas(r).map((m) => m.label).toList(), ['疼痛', '睡眠']);
    });

    test("默认最多 2 项 (卡片要能扫读, 不是把明细页搬过来)", () {
      final r = _rec(
        pre: {'pain_level': 8, 'sleep_quality': 4, 'mood': 5},
        post: {'pain_level': 4, 'sleep_quality': 7, 'mood': 6},
      );
      expect(metricDeltas(r).length, 2);
      expect(metricDeltas(r, max: 3).length, 3);
    });

    test("只显示**前后都填了**的指标 (只填一半不算改善)", () {
      final r = _rec(
        pre: {'pain_level': 8, 'sleep_quality': 4},
        post: {'pain_level': 4}, // sleep 没填后值
      );
      final m = metricDeltas(r);
      expect(m.length, 1);
      expect(m.first.label, '疼痛');
    });

    test("一个指标都没填 → 空列表 (卡片不显示对比行)", () {
      expect(metricDeltas(_rec(pre: {}, post: {})), isEmpty);
    });

    test("字符串数字也能解析 (后端 JSON 可能给字符串)", () {
      final r = _rec(pre: {'pain_level': '8'}, post: {'pain_level': '4'});
      final m = metricDeltas(r);
      expect(m.length, 1);
      expect(m.first.pre, 8);
      expect(m.first.post, 4);
    });
  });

  // ── ④ 真渲染 (带真主题 + 断言高度) ──
  group("RecordTile 渲染", () {
    testWidgets("画出了项目名 / 部位 / 改善 / 反馈", (tester) async {
      await _pump(tester, RecordTile(record: _rec(), dict: _dict));

      expect(find.text('肩颈经络理疗'), findsOneWidget); // 项目名 (不再是"养生记录")
      expect(find.text('肩颈'), findsWidgets); // 部位
      expect(find.text('疼痛 8 → 4'), findsOneWidget); // 前 → 后
      expect(find.text('↓4'), findsOneWidget); // 改善量
      expect(find.textContaining('挺舒服的'), findsOneWidget); // 反馈
    });

    testWidgets("⚠ 高度不是 0 (P4 踩过: 单测绿但真机零高)", (tester) async {
      await _pump(tester, RecordTile(record: _rec(), dict: _dict));
      final size = tester.getSize(find.byType(RecordTile));
      expect(size.height, greaterThan(80),
          reason: '整块塌成 0 高的话 UI 在真机上完全看不见');
      expect(size.width, greaterThan(0));
    });

    testWidgets("字典缺失 → 回落「养生记录」, 不显示 #id", (tester) async {
      await _pump(tester, RecordTile(record: _rec(), dict: null));

      expect(find.text('养生记录'), findsOneWidget);
      expect(find.textContaining('#2'), findsNothing);
      // 指标对比不需要字典, 仍要正常显示
      expect(find.text('疼痛 8 → 4'), findsOneWidget);
    });

    testWidgets("没填反馈 → 不画反馈行 (不显示空白)", (tester) async {
      await _pump(tester,
          RecordTile(record: _rec(feedback: null), dict: _dict));
      expect(find.textContaining('反馈'), findsNothing);
    });

    testWidgets("疼痛变差时用警告色, 但数字照常显示", (tester) async {
      await _pump(
        tester,
        RecordTile(
          record: _rec(pre: {'pain_level': 4}, post: {'pain_level': 8}),
          dict: _dict,
        ),
      );
      expect(find.text('疼痛 4 → 8'), findsOneWidget);
      expect(find.text('↑4'), findsOneWidget);
    });
  });
}
