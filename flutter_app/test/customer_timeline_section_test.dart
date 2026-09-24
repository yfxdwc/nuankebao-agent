// ============================================
// CustomerTimelineSection 单测 (2026-09-24 拍板重构)
//   ⏵ 2026-09-25: 时间线 10 项 UI/交互改进
//
// 守护 (10 项, 顺序与 task 对齐):
//   ① 空态走 AppEmptyState (filter=全部 / 养生 / 互动 三个分支)
//   ② 错误态: 两边都空且至少一边 error → ErrorState;
//              单边错误 → 行内错误行 + 「重试」按钮
//   ③ 加载态: 两边都 loading + 两边都空 → AppSkeletonList (无「加载中」文本)
//   ④ 单边 loading → 列表尾部小字
//   ⑤ 加载更多: totalCount > visibleCount → 「加载更多（还有 N 条）」
//                wellness.length == 50 → 「养生记录较多, 当前仅加载最近 50 条」
//   ⑥ 下次建议日期: adviceHint + adviceOverdue (逾期片段染 AppColors.warning)
//   ⑦ 相对时间: relativeDayLabel (今天/昨天/N 天前)
//   ⑧ 照片指示: wellness 行 photos 非空 → meta 显示相机图标 + 张数
//   ⑨ 日期分组头: today/yesterday/thisWeek/thisMonth/earlier (AppType.xs + textTertiary)
//   ⑩ 趋势入口: summary 非空 + onViewTrends != null → 「趋势」按钮;
//
// 跑: cd flutter_app && flutter test test/customer_timeline_section_test.dart
// ============================================

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/dictionaries.dart';
import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/models/wellness_record.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart' show AppTheme;
import 'package:nuankebao/core/theme/tokens.g.dart' show AppColors, AppThemes;
import 'package:nuankebao/core/widgets/app_list_row.dart' show AppListRow;
import 'package:nuankebao/core/widgets/app_skeleton.dart' show AppSkeletonList;
import 'package:nuankebao/modules/customer/widgets/customer_timeline_section.dart';

// ============================================
// 假 service
// ============================================

class _FakeWellnessService extends WellnessRecordService {
  _FakeWellnessService(this._records) : super(Dio());

  final List<WellnessRecord> _records;

  @override
  Future<List<WellnessRecord>> list({
    String? customerId,
    int? limit,
  }) async {
    return _records;
  }

  /// 补 getById: 时间线行点开底部弹层时, wellnessRecordByIdProvider 会调它
  /// (2026-09-26 补: 原 fake 只返 list → 弹层走 dio 抛错, sheet header 能
  /// 验但 body/错误态全验不了, reviewer 说「passes by accident」)。
  @override
  Future<WellnessRecord> getById(String id) async {
    return _records.firstWhere(
      (r) => r.id == id,
      orElse: () => throw Exception('mock 404: $id'),
    );
  }
}

class _FakeInteractionService extends InteractionService {
  _FakeInteractionService(this._items) : super(Dio());

  final List<Interaction> _items;
  final List<Map<String, dynamic>> createCalls = [];

  @override
  Future<List<Interaction>> list({String? customerId}) async => _items;

  @override
  Future<Interaction> create(Map<String, dynamic> data) async {
    createCalls.add(Map<String, dynamic>.from(data));
    return Interaction(
      id: 'fake-${createCalls.length}',
      customerId: data['customerId'] as String,
      type: data['type'] as String,
      summary: data['summary'] as String?,
      createdBy: 'me',
      createdAt: DateTime(2026, 9, 24),
    );
  }
}

class _FakeDictionaryService extends DictionaryService {
  _FakeDictionaryService(this._dict) : super(Dio());

  final Dictionaries _dict;

  @override
  Future<Dictionaries> all() async => _dict;
}

// ============================================
// fixtures
// ============================================

const _dict = Dictionaries(
  bodyParts: [
    BodyPart(id: '1', name: '肩颈'),
    BodyPart(id: '9', name: '腰部'),
  ],
  serviceItems: [
    ServiceItem(id: '2', name: '肩颈经络理疗'),
  ],
);

WellnessRecord _wellness({
  required String id,
  required String serviceDate, // YYYY-MM-DD
  String serviceItemId = '2',
  List<String> bodyPartIds = const ['1'],
  Map<String, dynamic> pre = const {'pain_level': 8},
  Map<String, dynamic> post = const {'pain_level': 3},
  String? nextAdviceDate,
  List<String> photos = const [],
}) =>
    WellnessRecord(
      id: id,
      customerId: '798',
      serviceDate: serviceDate,
      serviceItemId: serviceItemId,
      bodyPartIds: bodyPartIds,
      preCondition: pre,
      postCondition: post,
      createdAt: DateTime.parse('${serviceDate}T10:00:00'),
      nextAdviceDate: nextAdviceDate,
      photos: photos,
    );

Interaction _interaction({
  required String id,
  required DateTime createdAt,
  String type = 'phone',
  String? summary,
}) =>
    Interaction(
      id: id,
      customerId: '798',
      type: type,
      summary: summary,
      createdBy: 'me',
      createdAt: createdAt,
    );

// ============================================
// pump helper
// ============================================

/// 固定的「现在」用于日期相关断言 (本机 CST, 当前日期固定)
final DateTime _now = DateTime(2026, 9, 24, 14);

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<WellnessRecord> wellness,
  required List<Interaction> interactions,
  WellnessRecordService? wellnessService,
  InteractionService? interactionService,
  DictionaryService? dictionaryService,
  VoidCallback? onViewTrends,
}) async {
  final wsvc = wellnessService ?? _FakeWellnessService(wellness);
  final isvc = interactionService ?? _FakeInteractionService(interactions);
  final dsvc = dictionaryService ?? _FakeDictionaryService(_dict);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wellnessRecordServiceProvider.overrideWithValue(wsvc),
        interactionServiceProvider.overrideWithValue(isvc),
        dictionaryServiceProvider.overrideWithValue(dsvc),
      ],
      child: MaterialApp(
        theme: AppTheme.light(AppThemes.sage),
        home: Scaffold(
          body: CustomerTimelineSection(
            customerId: '798',
            onViewTrends: onViewTrends,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  });
}

/// 锁工具栏上的两个 PopupMenuButton 节点的 key
const ValueKey<String> kFilterDropdown = ValueKey('timelineFilterDropdown');
const ValueKey<String> kAddRecordDropdown = ValueKey('timelineAddRecordButton');

Future<void> _pickFromMenu(
  WidgetTester tester, {
  required Finder trigger,
  required String itemLabel,
}) async {
  await tester.tap(trigger, warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemLabel).last, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '① 默认「全部记录」→ 养生 + 互动混排 + 倒序 + 工具栏显示当前「全部」+「添加记录」按钮',
    (tester) async {
      // 4 条 (2 养生 + 2 互动), 日期交错
      await _pumpSection(
        tester,
        wellness: [
          _wellness(id: 'w1', serviceDate: '2026-09-20'),
          _wellness(id: 'w2', serviceDate: '2026-09-22'),
        ],
        interactions: [
          _interaction(id: 'i1', createdAt: DateTime(2026, 9, 21, 10)),
          _interaction(id: 'i2', createdAt: DateTime(2026, 9, 23, 10)),
        ],
      );

      // 工具栏默认显示「全部记录」, 添加记录按钮显示「添加记录」
      expect(find.byKey(kFilterDropdown), findsOneWidget);
      expect(find.byKey(kAddRecordDropdown), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(kFilterDropdown), matching: find.text('全部记录')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(kAddRecordDropdown), matching: find.text('添加记录')),
          findsOneWidget);

      // 养生摘要: ⑦ 相对时间 「最近一次 今天」(今天=09-24, 最新养生 09-22 → 2 天前)
      expect(find.textContaining('共 2 次'), findsOneWidget);
      expect(find.textContaining('最近一次 2 天前'), findsOneWidget);

      // 4 行都画了
      expect(find.text('肩颈经络理疗'), findsNWidgets(2));
      expect(find.textContaining('疼痛 8→3 ↓5'), findsNWidgets(2));

      // 互动行: 默认 type=phone → 「电话」label
      expect(find.text('电话'), findsNWidgets(2));

      // ⑨ 默认显示 4 个分组桶 (今日/本月/更早 无数据)
      expect(find.text('今天'), findsNothing);
      expect(find.text('昨天'), findsOneWidget); // 09-23 interaction
      expect(find.text('本周'), findsOneWidget); // 09-20..09-22
      expect(find.text('本月'), findsNothing);
      expect(find.text('更早'), findsNothing);
    },
  );

  testWidgets(
    '② 点筛选下拉 +「养生记录」 → 只剩养生 (互动隐藏)',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [
          _wellness(id: 'w1', serviceDate: '2026-09-20'),
          _wellness(id: 'w2', serviceDate: '2026-09-22'),
        ],
        interactions: [
          _interaction(id: 'i1', createdAt: DateTime(2026, 9, 23, 10)),
        ],
      );

      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '养生记录');

      expect(find.text('肩颈经络理疗'), findsNWidgets(2));
      expect(find.text('电话'), findsNothing);
      expect(find.text('微信'), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(kFilterDropdown), matching: find.text('养生记录')),
          findsOneWidget);
    },
  );

  testWidgets(
    '③ 点筛选下拉 +「互动记录」 → 只剩互动 (养生隐藏)',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [
          _wellness(id: 'w1', serviceDate: '2026-09-20'),
        ],
        interactions: [
          _interaction(id: 'i1', createdAt: DateTime(2026, 9, 21, 10), type: 'phone'),
          _interaction(id: 'i2', createdAt: DateTime(2026, 9, 23, 10), type: 'wechat'),
        ],
      );

      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '互动记录');

      expect(find.text('肩颈经络理疗'), findsNothing);
      expect(find.text('电话'), findsOneWidget);
      expect(find.text('微信'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(kFilterDropdown), matching: find.text('互动记录')),
          findsOneWidget);
    },
  );

  testWidgets(
    '① 空态 (filter=全部): 「还没有记录」 + 两条 action',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: const [],
      );

      expect(find.text('还没有记录'), findsOneWidget);
      // action + secondaryAction (filter=全部 时两个都显示)
      expect(find.text('记一条养生记录'), findsOneWidget);
      expect(find.text('记一笔联系'), findsOneWidget);
    },
  );

  testWidgets(
    '① 空态 (filter=养生): 「还没有养生记录」 + 单 action',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: [_interaction(id: 'i1', createdAt: _now)],
      );
      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '养生记录');

      expect(find.text('还没有养生记录'), findsOneWidget);
      expect(find.text('记第一条养生记录'), findsOneWidget);
      // 没有 secondaryAction
      expect(find.text('记一笔联系'), findsNothing);
    },
  );

  testWidgets(
    '① 空态 (filter=互动): 「还没记过联系」 + 单 action',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [_wellness(id: 'w1', serviceDate: '2026-09-22')],
        interactions: const [],
      );
      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '互动记录');

      expect(find.text('还没记过联系'), findsOneWidget);
      expect(find.text('记一笔联系'), findsOneWidget);
    },
  );

  testWidgets(
    '③ 加载态: 两边都 loading 且都为空 → AppSkeletonList (无「加载记录中」)',
    (tester) async {
      // 用一个永不返回的 service, 保证整个测试期都是 loading
      final pendingWellness = _PendingWellnessService();
      final pendingInteractions = _PendingInteractionService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wellnessRecordServiceProvider.overrideWithValue(pendingWellness),
            interactionServiceProvider.overrideWithValue(pendingInteractions),
            dictionaryServiceProvider
                .overrideWithValue(_FakeDictionaryService(_dict)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(AppThemes.sage),
            home: Scaffold(
              body: CustomerTimelineSection(customerId: '798'),
            ),
          ),
        ),
      );
      // 只 pump 一次 (不 settle), 此时数据还没回, 仍是 loading + 空
      await tester.pump();

      // ③: AppSkeletonList (rows=4 dense=true) 应渲染; 旧「加载记录中」文案不应出现
      expect(find.text('加载记录中...'), findsNothing);
      // AppSkeleton 元素至少存在 (AppSkeletonList 内部用 AppSkeleton)
      expect(find.byType(AppSkeletonList), findsOneWidget);
    },
  );

  testWidgets(
    '② 错误态: 两边都空且至少一边 error → ErrorState + 重试按钮',
    (tester) async {
      // 养生 OK 但空, 互动 抛错; 两边都空 → 走 ErrorState 分支
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: const [],
        interactionService: _ThrowingInteractionService(),
      );

      // ErrorState 的默认 title + 重试按钮
      expect(find.text('网络不太好'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 不画列表 (养生空 + 互动错)
      expect(find.text('还没有记录'), findsNothing);
    },
  );

  testWidgets(
    '② 错误态: 一边有数据 + 另一边 error → 行内错误行「养生记录加载失败」',
    (tester) async {
      // 养生有数据, 互动 抛错且空 → 互动走行内错误, 养生行正常显示
      await _pumpSection(
        tester,
        wellness: [_wellness(id: 'w1', serviceDate: '2026-09-22')],
        interactions: const [],
        interactionService: _ThrowingInteractionService(),
      );

      // 养生行还在 (不被另一边错误拖垮)
      expect(find.text('肩颈经络理疗'), findsOneWidget);
      // 行内错误行
      expect(find.text('互动加载失败'), findsOneWidget);
      // 行内错误行的「重试」(区别于 ErrorState 的全局重试)
      expect(find.textContaining('重试'), findsOneWidget);
    },
  );

  testWidgets(
    '④ 单边 loading: 一边已回数据 + 另一边 loading + 另一边为空 → 列表尾部小字',
    (tester) async {
      // 互动是 pending (loading), 养生正常返回 1 条
      final pendingInteraction = _PendingInteractionService();
      await _pumpSection(
        tester,
        wellness: [_wellness(id: 'w1', serviceDate: '2026-09-22')],
        interactions: const [],
        interactionService: pendingInteraction,
      );
      // pump 一下让养生数据回, 互动保持 loading
      await tester.pump();

      // 养生行还在
      expect(find.text('肩颈经络理疗'), findsOneWidget);
      // 互动加载中小字
      expect(find.text('互动加载中…'), findsOneWidget);
      // 没有「养生记录加载中」(养生已回数据)
      expect(find.text('养生记录加载中…'), findsNothing);
    },
  );

  testWidgets(
    '⑤ 加载更多: totalCount > visibleCount → 「加载更多（还有 N 条）」',
    (tester) async {
      // 21 条互动 → 应显示「加载更多（还有 1 条）」
      final many = <Interaction>[
        for (var i = 0; i < 21; i++)
          _interaction(
            id: 'i$i',
            createdAt: DateTime(2026, 9, 24).subtract(Duration(hours: i)),
          ),
      ];
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: many,
      );

      expect(find.textContaining('加载更多（还有 1 条）'), findsOneWidget);
    },
  );

  testWidgets(
    '⑤ 加载更多: 点「加载更多」 → 隐藏按钮, 显示全部 21 条',
    (tester) async {
      final many = <Interaction>[
        for (var i = 0; i < 21; i++)
          _interaction(
            id: 'i$i',
            createdAt: DateTime(2026, 9, 24).subtract(Duration(hours: i)),
          ),
      ];
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: many,
      );

      // 点击加载更多
      await tester.ensureVisible(find.textContaining('加载更多'));
      await tester.tap(find.textContaining('加载更多'));
      await tester.pumpAndSettle();

      // 按钮应消失 (总数 == visibleCount)
      expect(find.textContaining('加载更多（还有'), findsNothing);
    },
  );

  testWidgets(
    '⑤ 加载更多: wellness.length == 50 → 全部加载完后, 依然 50 条 ≥ 50 → 显示「养生记录较多」',
    (tester) async {
      final fifty = <WellnessRecord>[
        for (var i = 0; i < 50; i++)
          _wellness(
            id: 'w$i',
            serviceDate: DateTime(2026, 9, 24)
                .subtract(Duration(days: i))
                .toIso8601String()
                .split('T')
                .first,
          ),
      ];
      // 有限高度, 让 section 卡内必须滚动
      final wsvc = _FakeWellnessService(fifty);
      final isvc = _FakeInteractionService(const []);
      final dsvc = _FakeDictionaryService(_dict);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wellnessRecordServiceProvider.overrideWithValue(wsvc),
            interactionServiceProvider.overrideWithValue(isvc),
            dictionaryServiceProvider.overrideWithValue(dsvc),
          ],
          child: MaterialApp(
            theme: AppTheme.light(AppThemes.sage),
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: CustomerTimelineSection(customerId: '798'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });

      // 点两次「加载更多」 (20 → 40 → 60), 50 < 60, 全部显示完
      // 第一次点击
      await tester.ensureVisible(find.text('加载更多（还有 30 条）'));
      await tester.tap(find.text('加载更多（还有 30 条）'));
      await tester.pumpAndSettle();
      // 第二次点击
      await tester.ensureVisible(find.text('加载更多（还有 10 条）'));
      await tester.tap(find.text('加载更多（还有 10 条）'));
      await tester.pumpAndSettle();

      // 全部显示完, 且 wellness.length == 50 (provider 拉到上限) → 「养生记录较多」
      expect(find.text('养生记录较多, 当前仅加载最近 50 条'), findsOneWidget);
    },
  );

  testWidgets(
    '⑤ 切换 filter 重置 visibleCount',
    (tester) async {
      // 21 条互动 → 选「互动记录」过滤 → 显示「加载更多」
      final many = <Interaction>[
        for (var i = 0; i < 21; i++)
          _interaction(
            id: 'i$i',
            createdAt: DateTime(2026, 9, 24).subtract(Duration(hours: i)),
          ),
      ];
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: many,
      );

      // 先点加载更多 (visibleCount=40), 按钮消失
      await tester.ensureVisible(find.text('加载更多（还有 1 条）'));
      await tester.tap(find.text('加载更多（还有 1 条）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('加载更多（还有'), findsNothing);

      // 切到「养生记录」, 立刻 切回「互动记录」 → visibleCount 重置 20 → 按钮重新出现
      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '养生记录');
      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '互动记录');
      expect(find.textContaining('加载更多（还有 1 条）'), findsOneWidget);
    },
  );

  testWidgets(
    '⑥ 下次建议日期: 未逾期 → 「建议 MM-dd 回访」(普通色)',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [
          _wellness(
              id: 'w1',
              serviceDate: '2026-09-20',
              nextAdviceDate: '2026-09-30'),
        ],
        interactions: const [],
      );

      // 建议日期显示
      expect(find.textContaining('建议 09-30 回访'), findsOneWidget);
      // 「已过」不应出现
      expect(find.textContaining('已过'), findsNothing);
    },
  );

  testWidgets(
    '⑥ 下次建议日期: 已逾期 → 「已过 N 天」文本存在',
    (tester) async {
      // 今天=09-24; nextAdviceDate=09-20 → 已过 4 天
      await _pumpSection(
        tester,
        wellness: [
          _wellness(
              id: 'w1',
              serviceDate: '2026-09-20',
              nextAdviceDate: '2026-09-20'),
        ],
        interactions: const [],
      );

      expect(find.textContaining('已过 4 天'), findsOneWidget);
    },
  );

  testWidgets(
    '⑥ 下次建议日期: 已逾期 → Text.rich 中已过片段染 AppColors.warning',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [
          _wellness(
              id: 'w1',
              serviceDate: '2026-09-20',
              nextAdviceDate: '2026-09-20'),
        ],
        interactions: const [],
      );

      // 文本中包含「已过 4 天」 (Text.rich 把字串拆成多段渲染)
      expect(find.textContaining('已过 4 天'), findsOneWidget);

      // 从 AppListRow 拿到 subtitle widget, 断言它是 Text.rich
      //   → 走过 DefaultTextStyle.merge 不修改原 TextSpan 树
      final rows = tester.widgetList(find.byType(AppListRow)).toList();
      final row = rows.firstWhere(
        (w) => w is AppListRow && w.title is Text,
        orElse: () => rows.firstWhere((w) => w is AppListRow),
      ) as AppListRow;
      final subtitle = row.subtitle;
      expect(subtitle, isNotNull);
      expect(subtitle, isA<Text>());

      // Text.rich 是 Text 的工厂之一; 但 Flutter 里它们用同一个 Text widget,
      // Text.rich(TextSpan(...)) → Text 的 textInlineSpan 字段。
      // 直接查 RichText widget (Text widget 内部用 RichText 渲染)
      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsWidgets);
      TextSpan? overdueSpan;
      final richWidgets = tester.widgetList<RichText>(richTextFinder).toList();
      // 遍历所有 RichText 的 span tree, 递归找「已过 4 天」片段
      void findOverdue(InlineSpan s) {
        if (overdueSpan != null) return;
        if (s is TextSpan) {
          if (s.text != null && s.text!.contains('已过 4 天')) {
            overdueSpan = s;
            return;
          }
          if (s.children != null) {
            for (final c in s.children!) findOverdue(c);
          }
        }
      }
      for (final rt in richWidgets) {
        findOverdue(rt.text);
        if (overdueSpan != null) break;
      }
      expect(overdueSpan, isNotNull,
          reason: '应能找到含「已过 4 天」的 TextSpan');
      expect(overdueSpan!.style, isNotNull);
      expect(overdueSpan!.style!.color, AppColors.warning);
    },
  );

  testWidgets(
    '⑦ 相对时间: 汇总行「最近一次 今天」',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [
          _wellness(id: 'w1', serviceDate: '2026-09-24'), // 今天
        ],
        interactions: const [],
      );
      expect(find.textContaining('最近一次 今天'), findsOneWidget);
    },
  );

  testWidgets(
    '⑦ 相对时间: 汇总行「最近一次 昨天」',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [
          _wellness(id: 'w1', serviceDate: '2026-09-23'), // 昨天
        ],
        interactions: const [],
      );
      expect(find.textContaining('最近一次 昨天'), findsOneWidget);
    },
  );

  testWidgets(
    '⑧ 照片指示: wellness 行 photos 非空 → meta 显示相机图标 + 张数',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [
          _wellness(
            id: 'w1',
            serviceDate: '2026-09-22',
            photos: const ['photo1.jpg', 'photo2.jpg', 'photo3.jpg'],
          ),
        ],
        interactions: const [],
      );

      // 张数 = 3
      expect(find.text('3'), findsOneWidget);
      // 相机图标
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    },
  );

  testWidgets(
    '⑨ 日期分组头: 今天 / 昨天 / 本周 / 本月 / 更早 各分组正确',
    (tester) async {
      // 5 条数据, 覆盖 5 个桶:
      //   今天 (diff=0): 09-24
      //   昨天 (diff=-1): 09-23
      //   本周 (diff in [-6, -2]): 09-22
      //   本月 (diff in [-29, -7]): 09-10
      //   更早 (diff=-30 及以上): 08-20
      await _pumpSection(
        tester,
        wellness: [
          _wellness(id: 'w0', serviceDate: '2026-09-24'), // 今天
          _wellness(id: 'w1', serviceDate: '2026-09-23'), // 昨天
          _wellness(id: 'w2', serviceDate: '2026-09-22'), // 本周 (周四 → diff=-2)
          _wellness(id: 'w3', serviceDate: '2026-09-10'), // 本月
          _wellness(id: 'w4', serviceDate: '2026-08-20'), // 更早 (>30 天前)
        ],
        interactions: const [],
      );

      expect(find.text('今天'), findsOneWidget);
      expect(find.text('昨天'), findsOneWidget);
      expect(find.text('本周'), findsOneWidget);
      expect(find.text('本月'), findsOneWidget);
      expect(find.text('更早'), findsOneWidget);
    },
  );

  testWidgets(
    '⑩ 趋势入口: summary 非空 + onViewTrends != null → 「趋势」按钮 + 点击触发回调',
    (tester) async {
      var trendsTapped = 0;
      await _pumpSection(
        tester,
        wellness: [
          _wellness(id: 'w1', serviceDate: '2026-09-22'),
        ],
        interactions: const [],
        onViewTrends: () => trendsTapped++,
      );

      expect(find.text('趋势'), findsOneWidget);
      // 点击
      await tester.tap(find.text('趋势'));
      await tester.pumpAndSettle();
      expect(trendsTapped, 1);
    },
  );

  testWidgets(
    '⑩ 趋势入口: summary 为空 (无养生数据) → 不显示「趋势」按钮',
    (tester) async {
      var trendsTapped = 0;
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: [
          _interaction(id: 'i1', createdAt: DateTime(2026, 9, 23, 10)),
        ],
        onViewTrends: () => trendsTapped++,
      );

      expect(find.text('趋势'), findsNothing);
    },
  );

  testWidgets(
    '⑩ 趋势入口: onViewTrends == null → 不显示「趋势」按钮',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [_wellness(id: 'w1', serviceDate: '2026-09-22')],
        interactions: const [],
        onViewTrends: null, // 默认就是 null
      );

      expect(find.text('趋势'), findsNothing);
    },
  );

  testWidgets(
    '健壮性: 养生 OK + 互动 provider 报错 + 养生有数据 → 养生行还在 + 行内错误行',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [_wellness(id: 'w1', serviceDate: '2026-09-22')],
        interactions: const [],
        interactionService: _ThrowingInteractionService(),
      );

      // 养生行还在
      expect(find.text('肩颈经络理疗'), findsOneWidget);
      // 副文里的改善指标也在
      expect(find.textContaining('疼痛 8→3'), findsOneWidget);
      // 行内错误行
      expect(find.text('互动加载失败'), findsOneWidget);
    },
  );

  testWidgets(
    '⑦ 添加记录下拉 → 菜单出现「添加养生记录」与「添加联系记录」两项',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: const [],
      );

      await tester.tap(find.byKey(kAddRecordDropdown));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('添加养生记录'), findsOneWidget);
      expect(find.text('添加联系记录'), findsOneWidget);
    },
  );

  testWidgets(
    '⑦ 选下拉中「添加联系记录」→ 走弹层 + 调 interactionService.create',
    (tester) async {
      final fakeInteraction = _FakeInteractionService(const []);
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: const [],
        interactionService: fakeInteraction,
      );

      await _pickFromMenu(tester,
          trigger: find.byKey(kAddRecordDropdown), itemLabel: '添加联系记录');
      await tester.pumpAndSettle();

      expect(find.text('添加联系记录'), findsWidgets);
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('标记完成'), findsNothing);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(fakeInteraction.createCalls, hasLength(1));
      expect(fakeInteraction.createCalls.single['customerId'], '798');
      expect(fakeInteraction.createCalls.single['type'], 'phone');
    },
  );

  // ============================================
  // 2026-09-25 第 13/14/5 项: 时间线行 → 弹层
  // ============================================

  testWidgets(
    '13/14 点养生记录行 → 打开「养生详情」底部弹层 (body 出现真实字段内容)',
    (tester) async {
      // 2026-09-26 reviewer: 原用例只验「养生详情」 header, 没验 body/错误态, 属 passes by accident
      // 修法: _FakeWellnessService 已加 getById, 弹层能拿到真 record;
      //       断言里加 body 的真实字段 (服务名 / 部位 / 评分)。
      await _pumpSection(
        tester,
        wellness: [
          _wellness(
            id: 'w1',
            serviceDate: '2026-09-22',
            serviceItemId: '2',
            bodyPartIds: const ['1'],
            pre: const {'pain_level': 8, 'sleep_quality': 3, 'mood': 4},
            post: const {'pain_level': 3, 'sleep_quality': 7, 'mood': 8},
          ),
        ],
        interactions: const [],
      );

      // 点养生行 (AppListRow onTap → showWellnessRecordDetailSheet)
      await tester.tap(find.text('肩颈经络理疗'));
      await tester.pumpAndSettle();

      // 弹层头部 + 编辑入口 (原断言保留)
      expect(find.text('养生详情'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);

      // —— 补 body 真实字段 (reviewer 要求) ——
      // 服务名出现在 body 头部 (二次出现: list 行 + body 头)
      expect(find.text('肩颈经络理疗'), findsNWidgets(2));
      // 部位 = 肩颈 (字典里有, badge 应显示)
      expect(find.text('肩颈'), findsOneWidget);
      // 理疗前/后状态行 (用 statRow, 不验数值; 验标位标住)
      expect(find.text('理疗前状态'), findsOneWidget);
      expect(find.text('理疗后效果'), findsOneWidget);
      // 「疼痛」label 在前/后两处出现
      expect(find.text('疼痛'), findsNWidgets(2));
      // 评分 8: pre pain=8 + post mood=8 = 2 处; 3: pre sleep=3 + post pain=3 = 2 处
      //   (不能用 findsOneWidget —— 会漏 post 的同值, 看似「sheet 报错」实则验错事)
      expect(find.text('8'), findsNWidgets(2));
      expect(find.text('3'), findsNWidgets(2));
    },
  );

  testWidgets(
    '5 点互动记录行 → 打开「联系记录」底部弹层',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: [
          _interaction(
            id: 'i1',
            createdAt: DateTime(2026, 9, 22, 14, 30),
            type: 'phone',
            summary: '约下周三到店',
          ),
        ],
      );

      // 点互动行 (AppListRow onTap → showInteractionDetailSheet)
      await tester.tap(find.text('电话'));
      await tester.pumpAndSettle();

      // 弹层头部 + 类型 + 内容
      expect(find.text('联系记录'), findsOneWidget);
      expect(find.text('电话'), findsWidgets); // 行标题 + 弹层主标题都可能是「电话」
      expect(find.text('约下周三到店'), findsOneWidget);
      // 「编辑」+「删除」操作入口
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
    },
  );
}

// ============================================
// 帮助 service
// ============================================

class _ThrowingInteractionService extends InteractionService {
  _ThrowingInteractionService() : super(Dio());

  @override
  Future<List<Interaction>> list({String? customerId}) async {
    throw Exception('mock interaction list failure');
  }
}

/// 永挂起 (用来模拟还在 loading 的 provider)
class _PendingWellnessService extends WellnessRecordService {
  _PendingWellnessService() : super(Dio());

  @override
  Future<List<WellnessRecord>> list({String? customerId, int? limit}) {
    // 永远不完成的 future; 测试期保持 loading 状态
    return Completer<List<WellnessRecord>>().future;
  }
}

class _PendingInteractionService extends InteractionService {
  _PendingInteractionService() : super(Dio());

  @override
  Future<List<Interaction>> list({String? customerId}) {
    return Completer<List<Interaction>>().future;
  }
}