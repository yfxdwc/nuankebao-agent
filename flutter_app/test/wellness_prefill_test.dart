// ============================================
// 养生记录表单 —— 「沿用上次」预填 (P3 记录提速) widget 测试
// ============================================
// 守护的东西:
//   ① 新建时拿上次记录预填: **本次的「前」= 上次的「后」** (核心洞察)
//   ② 本次的「后」默认 = 「前」→ 改善量 0 (不虚报效果)
//   ③ 部位 / 服务沿用上次 (同一疗程大概率一样)
//   ④ 给「已按上次填好」提示 (不提示 = 销售会把每个字段重看一遍, 提速归零)
//   ⑤ 「清空重填」能回到出厂默认
//   ⑥ 拿不到上次记录 (首次到店) → 静默退化成默认值, 表单照样能开
//   ⑦ 首次到店不该出现提示条
//
// ⚠ 必须带真主题 AppTheme.light(tokens) —— AGENTS §5: 不带主题 = 走 Flutter 默认样式,
//   "写了字号漏 color" 这类 bug 永远测不出来。
//
// 跑: cd flutter_app && flutter test test/wellness_prefill_test.dart
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nuankebao/core/models/dictionaries.dart';
import 'package:nuankebao/core/models/wellness_record.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/wellness/screens/wellness_record_form_page.dart';

// ---------- 假 service (只覆写 list / all) ----------

class _FakeWellnessRecordService extends WellnessRecordService {
  _FakeWellnessRecordService(this.records) : super(Dio());
  final List<WellnessRecord> records;

  @override
  Future<List<WellnessRecord>> list({String? customerId, int limit = 50}) async {
    return records.take(limit).toList();
  }
}

class _FakeDictionaryService extends DictionaryService {
  _FakeDictionaryService(this.dict) : super(Dio());
  final Dictionaries dict;

  @override
  Future<Dictionaries> all() async => dict;
}

// ---------- 夹具 ----------

final _dict = Dictionaries(
  bodyParts: const [BodyPart(id: "1", name: "肩颈")],
  serviceItems: const [ServiceItem(id: "s1", name: "碧波庭-脉动负压提拉按摩")],
);

/// 上次记录: 前 pain 8→后 3, sleep 2→4, mood 3→5 (明显改善的一次)
WellnessRecord lastRecord({
  List<String> bodyPartIds = const ["1"],
  String serviceItemId = "s1",
  Map<String, dynamic> post = const {
    "pain_level": 3,
    "sleep_quality": 4,
    "mood": 5,
  },
  String serviceDate = "2026-09-12",
}) =>
    WellnessRecord(
      id: "r1",
      customerId: "c1",
      serviceDate: serviceDate,
      serviceItemId: serviceItemId,
      bodyPartIds: bodyPartIds,
      preCondition: const {"pain_level": 8, "sleep_quality": 2, "mood": 3},
      postCondition: post,
      createdAt: DateTime.utc(2026, 9, 12),
    );

Widget host({
  required List<WellnessRecord> records,
  Dictionaries? dict,
}) {
  final tokens = AppThemes.resolve(null);
  return ProviderScope(
    overrides: [
      dictionaryServiceProvider.overrideWithValue(
        _FakeDictionaryService(dict ?? _dict),
      ),
      wellnessRecordServiceProvider.overrideWithValue(
        _FakeWellnessRecordService(records),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(tokens),
      home: const WellnessRecordFormPage(customerId: "c1"),
    ),
  );
}

Future<void> pump(WidgetTester tester,
    {required List<WellnessRecord> records, Dictionaries? dict}) async {
  // 草稿功能会读 shared_preferences → 测试里给个空 mock (否则平台通道可能挂起)
  SharedPreferences.setMockInitialValues({});
  // ⚠ 表单是 ListView (懒构建): 默认 800px 视口只建得出前 3 个滑块,
  //   后面 3 个在屏外 → find.byType(Slider) 找不到。
  //   把视口调高, 让 6 个滑块全部构建 (测的是数据映射, 不是滚动行为)。
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host(records: records, dict: dict));
  await tester.pumpAndSettle();
}

/// 读某个滑块当前值 —— 表单用 Slider, 通过 value 断言
///
/// ⚠ 2026-09-24 顺序变了 (「理疗前 → 后」合并成一张对比卡, 按指标分组):
///   0 = 疼痛·前 | 1 = 疼痛·后 | 2 = 睡眠·前 | 3 = 睡眠·后 | 4 = 情绪·前 | 5 = 情绪·后
///   (旧版是两块卡: 0/1/2 = 前 疼痛/睡眠/情绪, 3/4/5 = 后 疼痛/睡眠/情绪)
List<double> sliderValues(WidgetTester tester) =>
    tester.widgetList<Slider>(find.byType(Slider)).map((s) => s.value).toList();

void main() {
  group("① 沿用上次: 本次「前」= 上次「后」", () {
    testWidgets("预填把上次的 post 灌进本次的 pre", (tester) async {
      await pump(tester, records: [lastRecord()]);

      // 表单有 6 个滑块 (pre/post × pain/sleep/mood)
      final vals = sliderValues(tester);
      expect(vals.length, 6, reason: "理疗前/后 × 疼痛/睡眠/情绪 = 6 个滑块");

      // pre: pain=3 sleep=4 mood=5  ← 来自上次的 post
      //   (新顺序: 前/后按指标相邻 → 前 = 偶数下标 0/2/4)
      expect(vals[0], 3, reason: "prePain 应 = 上次 postPain");
      expect(vals[2], 4, reason: "preSleep 应 = 上次 postSleep");
      expect(vals[4], 5, reason: "preMood 应 = 上次 postMood");
    });

    testWidgets("本次的「后」默认 = 「前」→ 改善量 0 (不虚报效果)", (tester) async {
      await pump(tester, records: [lastRecord()]);
      final vals = sliderValues(tester);
      expect(vals[1], vals[0], reason: "postPain 默认 = prePain");
      expect(vals[3], vals[2], reason: "postSleep 默认 = preSleep");
      expect(vals[5], vals[4], reason: "postMood 默认 = preMood");
    });

    testWidgets("没有历史记录 → 保留出厂默认 (疼痛 5/3 · 睡眠 5/5 · 情绪 5/5)",
        (tester) async {
      // 2026-09-24: 睡眠/情绪 改 1-10 分制, 默认 5 (原来 1-5 默认 3)
      await pump(tester, records: const []);
      final vals = sliderValues(tester);
      expect(vals[0], 5, reason: "疼痛·前 默认 5");
      expect(vals[1], 3, reason: "疼痛·后 默认 3");
      expect(vals[2], 5, reason: "睡眠·前 默认 5 (10 分制中位)");
      expect(vals[3], 5, reason: "睡眠·后 默认 5");
      expect(vals[4], 5, reason: "情绪·前 默认 5");
      expect(vals[5], 5, reason: "情绪·后 默认 5");
    });

    testWidgets("上次缺某个评分 → 该字段保留默认 (不覆盖成 null/0)", (tester) async {
      await pump(
        tester,
        records: [lastRecord(post: const {"pain_level": 2})],
      );
      final vals = sliderValues(tester);
      expect(vals[0], 2, reason: "有 pain → 用上次的");
      expect(vals[2], 5, reason: "没 sleep → 保留默认 5 (10 分制)");
      expect(vals[4], 5, reason: "没 mood → 保留默认 5 (10 分制)");
    });
  });

  group("② 提示条 (不提示 = 提速归零)", () {
    testWidgets("沿用成功 → 显示「已按 X 那次填好」+ 清空重填", (tester) async {
      await pump(tester, records: [lastRecord(serviceDate: "2026-09-12")]);
      expect(find.textContaining("已按"), findsOneWidget);
      expect(find.textContaining("2026-09-12"), findsOneWidget);
      expect(find.text("清空重填"), findsOneWidget);
      expect(find.textContaining("没变化可直接保存"), findsOneWidget);
    });

    testWidgets("首次到店 → 不显示提示条", (tester) async {
      await pump(tester, records: const []);
      expect(find.text("清空重填"), findsNothing);
    });

    testWidgets("点「清空重填」→ 回到默认值 + 提示条消失", (tester) async {
      await pump(tester, records: [lastRecord()]);
      // 先用上次的值确认预填生效
      expect(sliderValues(tester)[0], 3);

      await tester.tap(find.text("清空重填"));
      await tester.pumpAndSettle();

      final vals = sliderValues(tester);
      expect(vals[0], 5, reason: "pain·前 回到默认 5");
      expect(vals[1], 3, reason: "pain·后 回到默认 3");
      expect(vals[3], 5, reason: "睡眠·后 回默认 5 (2026-09-24 起 10 分制)");
      expect(find.text("清空重填"), findsNothing, reason: "提示条应消失");
    });
  });

  group("③ 健壮性", () {
    testWidgets("沿用失败 (service 抛错) 不崩, 退化成默认值", (tester) async {
      final tokens = AppThemes.resolve(null);
      await tester.binding.setSurfaceSize(const Size(1200, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dictionaryServiceProvider.overrideWithValue(_FakeDictionaryService(_dict)),
            wellnessRecordServiceProvider.overrideWithValue(
              _ThrowingWellnessRecordService(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(tokens),
            home: const WellnessRecordFormPage(customerId: "c1"),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 表单照样能开, 用默认值
      expect(sliderValues(tester)[0], 5);
    });

    testWidgets("真主题下渲染: 不出现无 color 的文本 (白字 bug 防线)", (tester) async {
      await pump(tester, records: [lastRecord()]);
      final paragraphs = tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      );
      var checked = 0;
      for (final rp in paragraphs) {
        final style = rp.text.style;
        if (style?.fontSize == null) continue;
        checked++;
        expect(style?.color, isNotNull,
            reason: '「${rp.text.toPlainText()}」设了字号但没 color');
      }
      expect(checked, greaterThan(0));
    });
  });
}

class _ThrowingWellnessRecordService extends WellnessRecordService {
  _ThrowingWellnessRecordService() : super(Dio());

  @override
  Future<List<WellnessRecord>> list({String? customerId, int limit = 50}) async {
    throw Exception("network down");
  }
}
