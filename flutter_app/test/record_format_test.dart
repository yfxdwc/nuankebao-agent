// ============================================
// 养生记录纯函数 单测 (2026-09-24 迁移自 record_tile_test)
//
// 来源: 原 `test/record_tile_test.dart`, 纯函数部分 (serviceItemName / bodyPartNames
//   / MetricDelta / metricDeltas) 搬到本文件; RecordTile widget 渲染用例删除
//   (新行组件 AppListRow 由 `customer_timeline_section_test.dart` 覆盖)。
//
// 守护的东西:
//   ① 字典翻译: serviceItemId/bodyPartIds → 名字; 查不到**不显示 #id** (宁可回落笼统文案)
//   ② 改善判定: 疼痛"降"是好事、睡眠"升"是好事 —— 方向相反最容易写反
//   ③ 只显示**前后都填了**的指标 (只填一半算改善 = 编数据)
//   ④ metricDeltaSummary: 行副文里那段「疼痛 8→3 ↓5」字串压得对
// ============================================

import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/dictionaries.dart';
import 'package:nuankebao/core/models/wellness_record.dart';
import 'package:nuankebao/modules/customer/widgets/record_format.dart';

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
  String? nextAdviceDate,
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
      nextAdviceDate: nextAdviceDate,
    );

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

  // ── ④ metricDeltaSummary (时间线副文) ──
  group("metricDeltaSummary", () {
    test("改善 (疼痛降) → '疼痛 8→3 ↓5'", () {
      final r = _rec(pre: {'pain_level': 8}, post: {'pain_level': 3});
      expect(metricDeltaSummary(r), '疼痛 8→3 ↓5');
    });

    test("改善 (睡眠升) → '睡眠 5→7 ↑2'", () {
      final r = _rec(
        pre: {'sleep_quality': 5},
        post: {'sleep_quality': 7},
      );
      expect(metricDeltaSummary(r), '睡眠 5→7 ↑2');
    });

    test("变差 (疼痛升) → '疼痛 4→8 ↑4'", () {
      final r = _rec(pre: {'pain_level': 4}, post: {'pain_level': 8});
      expect(metricDeltaSummary(r), '疼痛 4→8 ↑4');
    });

    test("持平 → 无箭头 '疼痛 8→8'", () {
      final r = _rec(pre: {'pain_level': 8}, post: {'pain_level': 8});
      expect(metricDeltaSummary(r), '疼痛 8→8');
    });

    test("多条 → ' · ' 拼接 (疼痛 + 睡眠)", () {
      final r = _rec(
        pre: {'pain_level': 8, 'sleep_quality': 5},
        post: {'pain_level': 4, 'sleep_quality': 7},
      );
      expect(metricDeltaSummary(r), '疼痛 8→4 ↓4 · 睡眠 5→7 ↑2');
    });

    test("无指标 → 空串 (副文不带 '疼痛:无' 这类空字段)", () {
      expect(metricDeltaSummary(_rec(pre: {}, post: {})), '');
    });
  });

  // ── ⑥ 下次建议日期提示 (adviceHint + adviceOverdue) ──
  group("adviceHint (⑥)", () {
    final now = DateTime(2026, 9, 24, 14);

    test("nextAdviceDate 为 null → 返回 null", () {
      expect(adviceHint(_rec(), now: now), isNull);
    });

    test("未逾期 (今天) → 「建议 MM-dd 回访」", () {
      final r = _rec(nextAdviceDate: '2026-09-24');
      expect(adviceHint(r, now: now), '建议 09-24 回访');
      expect(adviceOverdue(r, now: now), isFalse);
    });

    test("未逾期 (明天) → 「建议 MM-dd 回访」", () {
      final r = _rec(nextAdviceDate: '2026-09-25');
      expect(adviceHint(r, now: now), '建议 09-25 回访');
      expect(adviceOverdue(r, now: now), isFalse);
    });

    test("已逾期 4 天 → 「建议 MM-dd · 已过 4 天」", () {
      final r = _rec(nextAdviceDate: '2026-09-20');
      expect(adviceHint(r, now: now), '建议 09-20 · 已过 4 天');
      expect(adviceOverdue(r, now: now), isTrue);
    });

    test("解析失败 → 返回 null (不㕵错)", () {
      expect(adviceHint(_rec(nextAdviceDate: 'not-a-date'), now: now), isNull);
      expect(adviceOverdue(_rec(nextAdviceDate: 'not-a-date'), now: now), isFalse);
    });
  });

  // ── ⑦ 相对时间 (relativeDayLabel) ──
  group("relativeDayLabel (⑦)", () {
    final now = DateTime(2026, 9, 24, 14);

    test("今天 → 「今天」", () {
      expect(relativeDayLabel('2026-09-24', now: now), '今天');
    });

    test("昨天 → 「昨天」", () {
      expect(relativeDayLabel('2026-09-23', now: now), '昨天');
    });

    test("3 天前 → 「3 天前」", () {
      expect(relativeDayLabel('2026-09-21', now: now), '3 天前');
    });

    test("跨月 30 天前 → 「30 天前」", () {
      expect(relativeDayLabel('2026-08-25', now: now), '30 天前');
    });

    test("null → 空串", () {
      expect(relativeDayLabel(null, now: now), '');
    });

    test("解析失败 → 空串", () {
      expect(relativeDayLabel('not-a-date', now: now), '');
    });
  });

  // ── ⑨ 日期分组桶 (bucketOf) ──
  group("bucketOf (⑨)", () {
    final now = DateTime(2026, 9, 24, 14); // 周四

    test("今天 (diff=0) → today", () {
      expect(bucketOf('2026-09-24', now: now), TimelineBucket.today);
    });

    test("昨天 (diff=-1) → yesterday", () {
      expect(bucketOf('2026-09-23', now: now), TimelineBucket.yesterday);
    });

    test("本周 (diff in [-6, -2]) → thisWeek", () {
      expect(bucketOf('2026-09-22', now: now), TimelineBucket.thisWeek); // 前天
      expect(bucketOf('2026-09-18', now: now), TimelineBucket.thisWeek); // 周一
    });

    test("本月 (diff in [-29, -7]) → thisMonth", () {
      expect(bucketOf('2026-09-17', now: now), TimelineBucket.thisMonth);
      expect(bucketOf('2026-09-10', now: now), TimelineBucket.thisMonth);
    });

    test("30 天以上 / 跨月远端 → earlier", () {
      expect(bucketOf('2026-08-20', now: now), TimelineBucket.earlier);
    });

    test("解析失败 → earlier 兜底", () {
      expect(bucketOf(null, now: now), TimelineBucket.earlier);
      expect(bucketOf('not-a-date', now: now), TimelineBucket.earlier);
    });
  });
}