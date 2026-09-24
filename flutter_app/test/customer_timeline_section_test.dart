// ============================================
// CustomerTimelineSection 单测 (2026-09-24 拍板重构)
//
// 守护:
//   ① 默认「全部记录」→ 养生 + 互动混排 + 倒序 + 工具栏显示当前「全部」+「添加记录」按钮
//   ② 点筛选下拉 + 「养生记录」→ 只剩养生
//   ③ 点筛选下拉 + 「互动记录」→ 只剩互动
//   ④ 点添加记录下拉 → 菜单有「添加养生记录」与「添加联系记录」两项
//   ⑤ 健壮性: 养生 OK + 互动失败 → 养生行还在 (互不遮蔽)
//   ⑥ 养生行副文含改善指标 (「疼痛 8→3 ↓5」)
//   ⑦ 选下拉中「添加联系记录」→ 走弹层 + 调 interactionService.create
//   ⑧ 超过 20 条 → 列表底部显示「共 N 条 · 只显示最近 20 条」
//
// ⏵ 2026-09-24 续拍 (本 commit):
//   「内容选择标签折叠为下拉 + 添加记录收纳到下拉」, 测试改用下拉打开/点选的口径;
//   按钮文本不再外露, 所以
//    · ① 不能断言 `find.text('添加养生记录')` —— 它只在菜单打开时才出现
//    · ②③ 不能 `tap(finder.text('养生记录'))` —— 主页面默认显示「全部记录」, 「养生记录」
//      路径只能通过打开筛选下拉 → 点选才会出现
//
// 跑: cd flutter_app && flutter test test/customer_timeline_section_test.dart
// ============================================

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
import 'package:nuankebao/core/theme/tokens.g.dart' show AppThemes;
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

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<WellnessRecord> wellness,
  required List<Interaction> interactions,
  WellnessRecordService? wellnessService,
  InteractionService? interactionService,
  DictionaryService? dictionaryService,
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
          // 2026-09-24 卡片化后: section 内部是「固定表头 + Expanded(可滚列表)」,
          //   需要**有界高度** —— Scaffold body 直接给 (不再套 SingleChildScrollView,
          //   否则 Expanded 在无界约束下会报错)。
          body: CustomerTimelineSection(customerId: '798'),
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

/// 打开下拉 + 选 menu item 的合并 helper;
/// 选完会 await 几帧 pump, 让 menu 关闭 + setState 生效。
///
/// PopupMenu 在 Overlay 里渲染, 进入动画约 200ms, 因此第一步用 pumpAndSettle
/// 等动画结束再点 menu item; 否则 hitTest 会落在 menu 容器外, 命中警告。
Future<void> _pickFromMenu(
  WidgetTester tester, {
  required Finder trigger,
  required String itemLabel,
}) async {
  // 打开菜单 + 等动画过完
  await tester.tap(trigger, warnIfMissed: false);
  await tester.pumpAndSettle();
  // 菜单里点「itemLabel」 —— 用 .last 取最深命中 (菜单 PopupMenuItem 内嵌的那一份)
  await tester.tap(find.text(itemLabel).last, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '① 默认「全部记录」→ 养生 + 互动混排 + 倒序 + 工具栏显示当前「全部」+「添加记录」按钮',
    (tester) async {
      // 4 条 (2 养生 + 2 互动), 日期交错
      // 期望倒序:
      //   互动 09-23
      //   养生 09-22
      //   互动 09-21
      //   养生 09-20
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

      // ⏵ 2026-09-24: 工具栏断言 —— 筛选下拉显示默认「全部记录」, 添加记录按钮显示「添加记录」
      //   (文案不再是「添加养生记录」「添加联系记录」, 因为它们被收进了下拉菜单)
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

      // 养生摘要
      expect(find.textContaining('共 2 次'), findsOneWidget);

      // 4 行都画了
      // 养生行: 项目名「肩颈经络理疗」+ 部位 + 改善副文
      expect(find.text('肩颈经络理疗'), findsNWidgets(2));
      expect(find.textContaining('疼痛 8→3 ↓5'), findsNWidgets(2));

      // 互动行: 默认 type=phone → 「电话」label
      expect(find.text('电话'), findsNWidgets(2));

      // ⚠ 菜单未打开时「养生记录」「互动记录」不外露 (是下拉菜单项)
      expect(find.text('养生记录'), findsNothing);
      expect(find.text('互动记录'), findsNothing);
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

      // ⏵ 2026-09-24: 过滤下拉 → 点选「养生记录」菜单项
      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '养生记录');

      // 养生行 2 条
      expect(find.text('肩颈经络理疗'), findsNWidgets(2));
      // 互动行 0 条
      expect(find.text('电话'), findsNothing);
      expect(find.text('微信'), findsNothing);
      // 当前过滤已改为「养生记录」 → 下拉同时显示这个文本
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

      // 点选「互动记录」
      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '互动记录');

      // 养生行 0 条
      expect(find.text('肩颈经络理疗'), findsNothing);
      // 互动行 2 条 (phone + wechat)
      expect(find.text('电话'), findsOneWidget);
      expect(find.text('微信'), findsOneWidget);
      // 当前过滤已改为「互动记录」
      expect(
          find.descendant(
              of: find.byKey(kFilterDropdown), matching: find.text('互动记录')),
          findsOneWidget);
    },
  );

  testWidgets(
    '④ 空态: 默认「全部记录」无数据 → 显示「还没有记录」',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: const [],
      );

      expect(find.text('还没有记录'), findsOneWidget);
    },
  );

  testWidgets(
    '④ 空态: 过滤到「互动记录」且无互动 → 显示「还没记过联系」',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [_wellness(id: 'w1', serviceDate: '2026-09-22')],
        interactions: const [],
      );

      // 点选「互动记录」下拉项
      await _pickFromMenu(tester,
          trigger: find.byKey(kFilterDropdown), itemLabel: '互动记录');

      expect(find.text('还没记过联系'), findsOneWidget);
    },
  );

  testWidgets(
    '⑤ 健壮性: 养生 OK + 互动 provider 报错 → 养生行还在 (互不遮蔽)',
    (tester) async {
      // 互动 service 抛错, 养生正常
      final fakeInteraction = _FakeInteractionService([]);
      // ⚠ 不用 throwOnList — 因为 FutureProvider 内部直接捕获, 没捕获时把异常透到 UI
      // 改成让 list 抛错:
      final throwingInteraction = _ThrowingInteractionService();
      await _pumpSection(
        tester,
        wellness: [_wellness(id: 'w1', serviceDate: '2026-09-22')],
        interactions: const [],
        interactionService: throwingInteraction,
      );

      // 养生行应该还在 (不被另一边的错误拖垮)
      expect(find.text('肩颈经络理疗'), findsOneWidget);
      // 副文里的改善指标也在
      expect(find.textContaining('疼痛 8→3'), findsOneWidget);

      // ⚠ throwingInteraction 没被用, 避免 unused 警告
      expect(fakeInteraction.createCalls, isEmpty);
    },
  );

  testWidgets(
    '⑥ 养生行副文含改善指标 (「疼痛 8→3 ↓5」)',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: [_wellness(id: 'w1', serviceDate: '2026-09-22')],
        interactions: const [],
      );

      expect(find.textContaining('疼痛 8→3 ↓5'), findsOneWidget);
    },
  );

  testWidgets(
    '⑦ 点「添加记录」下拉 → 菜单出现「添加养生记录」与「添加联系记录」两项',
    (tester) async {
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: const [],
      );

      // 点「添加记录」按钮
      await tester.tap(find.byKey(kAddRecordDropdown));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 菜单内两项 — 「添加养生记录」「添加联系记录」都在
      expect(find.text('添加养生记录'), findsOneWidget);
      expect(find.text('添加联系记录'), findsOneWidget);
    },
  );

  testWidgets(
    '⑧ 选下拉中「添加联系记录」→ 走弹层 + 调 interactionService.create',
    (tester) async {
      final fakeInteraction = _FakeInteractionService(const []);
      await _pumpSection(
        tester,
        wellness: const [],
        interactions: const [],
        interactionService: fakeInteraction,
      );

      // 打开「添加记录」下拉 → 选「添加联系记录」
      await _pickFromMenu(tester,
          trigger: find.byKey(kAddRecordDropdown), itemLabel: '添加联系记录');
      await tester.pumpAndSettle();

      // 弹层标题 (菜单项 + 弹层标题可能同时存在, 用 findsWidgets 接受)
      expect(find.text('添加联系记录'), findsWidgets);
      // 弹层按钮「保存」 (跟「标记完成」区分)
      expect(find.text('保存'), findsOneWidget);
      // 弹层没有「标记完成」字样 (验证走的不是 completeTask 分支)
      expect(find.text('标记完成'), findsNothing);

      // 提交 (默认 phone)
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // create 被调用 + customerId / type 都对
      expect(fakeInteraction.createCalls, hasLength(1));
      expect(fakeInteraction.createCalls.single['customerId'], '798');
      expect(fakeInteraction.createCalls.single['type'], 'phone');
    },
  );

  testWidgets(
    '⑨ 超过 20 条 → 列表底部显示「共 N 条 · 只显示最近 20 条」',
    (tester) async {
      // 21 条互动 → 截断 + 显示截断 footer
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

      // 截断 footer
      expect(find.textContaining('只显示最近 20 条'), findsOneWidget);
    },
  );
}

/// 抛错 service (用于「互动 provider 报错 → 养生 OK 互不遮蔽」用例)
class _ThrowingInteractionService extends InteractionService {
  _ThrowingInteractionService() : super(Dio());

  @override
  Future<List<Interaction>> list({String? customerId}) async {
    throw Exception('mock interaction list failure');
  }
}
