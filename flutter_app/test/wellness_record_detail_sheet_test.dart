// ============================================
// 养生详情底部弹层 测试 (2026-09-25 第 13/14 项)
//
// 守护:
//   ① override wellnessRecordByIdProvider 给数据 → 打开弹层 → 断言出现与详情页一致的区段标题
//      (「部位」「理疗前状态」「理疗后效果」「操作过程」「客户反馈」)
//   ② 加载态 → 显示 AppSkeletonList(rows: 5)
//   ③ minimal record: 空 processNote / customerFeedback / 无 bodyPart → 对应区段不出现
//
// 跑: cd flutter_app && flutter test test/wellness_record_detail_sheet_test.dart
// ============================================

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/models/dictionaries.dart';
import 'package:nuankebao/core/models/wellness_record.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart' show AppTheme;
import 'package:nuankebao/core/theme/tokens.g.dart' show AppThemes;
import 'package:nuankebao/core/widgets/app_skeleton.dart' show AppSkeletonList;
import 'package:nuankebao/modules/wellness/widgets/wellness_record_detail_sheet.dart';

// ---------- 假 service ----------

class _FakeWellnessService extends WellnessRecordService {
  _FakeWellnessService(this._record) : super(Dio());

  final WellnessRecord? _record;

  @override
  Future<WellnessRecord> getById(String id) async {
    if (_record == null) throw Exception('mock 404');
    return _record;
  }
}

class _PendingWellnessService extends WellnessRecordService {
  _PendingWellnessService() : super(Dio());
  @override
  Future<WellnessRecord> getById(String id) {
    return Completer<WellnessRecord>().future;
  }
}

class _FakeDictionaryService extends DictionaryService {
  _FakeDictionaryService(this._dict) : super(Dio());

  final Dictionaries _dict;

  @override
  Future<Dictionaries> all() async => _dict;
}

// ---------- fixtures ----------

const _dict = Dictionaries(
  bodyParts: [BodyPart(id: '1', name: '肩颈')],
  serviceItems: [ServiceItem(id: '2', name: '肩颈经络理疗')],
);

WellnessRecord _fullRecord() => WellnessRecord(
      id: 'w1',
      customerId: 'c1',
      serviceDate: '2026-09-22',
      serviceItemId: '2',
      bodyPartIds: const ['1'],
      preCondition: const {'pain_level': 8, 'sleep_quality': 3, 'mood': 4},
      postCondition: const {'pain_level': 3, 'sleep_quality': 7, 'mood': 8},
      processNote: '重点做肩颈',
      customerFeedback: '觉得轻松了',
      createdAt: DateTime(2026, 9, 22, 10),
    );

WellnessRecord _minimalRecord() => WellnessRecord(
      id: 'w2',
      customerId: 'c1',
      serviceDate: '2026-09-20',
      serviceItemId: '2',
      bodyPartIds: const [],
      preCondition: const {'pain_level': 5},
      postCondition: const {'pain_level': 4},
      createdAt: DateTime(2026, 9, 20, 10),
    );

/// 泵根, 打开弹层, settle。
/// 设置大屏高 (1200) 让 ListView 全部装下, 保证可滚区所有 widget 都进 element tree
/// —— DraggableScrollableSheet 默认 90% 屏高 + ListView 默认装下所有 children;
///   但列表 UI 测试中, 「屏外」item 可能被 culling, 设置足够大屏让全部可见可画。
Future<void> _pumpSheet(
  WidgetTester tester, {
  required WellnessRecordService ws,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wellnessRecordServiceProvider.overrideWithValue(ws),
        dictionaryServiceProvider
            .overrideWithValue(_FakeDictionaryService(_dict)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(AppThemes.sage),
        home: Consumer(
          builder: (innerCtx, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showWellnessRecordDetailSheet(
                  innerCtx,
                  ref,
                  recordId: 'w1',
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① 打开弹层 → 显示与详情页一致的区段标题 + 编辑入口', (tester) async {
    await _pumpSheet(tester, ws: _FakeWellnessService(_fullRecord()));

    // 弹层头部 (AppSheetHeader title)
    expect(find.text('养生详情'), findsOneWidget);

    // 与详情页一致的区段标题 (大屏装下所有 children)
    expect(find.text('部位'), findsOneWidget);
    expect(find.text('理疗前状态'), findsOneWidget);
    expect(find.text('理疗后效果'), findsOneWidget);
    expect(find.text('操作过程'), findsOneWidget);
    expect(find.text('客户反馈'), findsOneWidget);

    // 「编辑」入口 (AppSheetHeader 的 TextButton)
    expect(find.text('编辑'), findsOneWidget);
  });

  testWidgets('② 加载态 → AppSkeletonList(rows: 5)', (tester) async {
    final ws = _PendingWellnessService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          wellnessRecordServiceProvider.overrideWithValue(ws),
          dictionaryServiceProvider
              .overrideWithValue(_FakeDictionaryService(_dict)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(AppThemes.sage),
          home: Consumer(
            builder: (innerCtx, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showWellnessRecordDetailSheet(
                    innerCtx,
                    ref,
                    recordId: 'w1',
                  ),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    // 不 settle (future 永不返回), 仅 pump 让弹层进入框架
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AppSkeletonList), findsOneWidget);
    // loading 态不应出现数据区段标题
    expect(find.text('理疗前状态'), findsNothing);
  });

  testWidgets(
      '③ minimal record: 空 processNote / customerFeedback / no bodyPart → 对应区段不出现',
      (tester) async {
    await _pumpSheet(tester, ws: _FakeWellnessService(_minimalRecord()));

    // 有数据区段在
    expect(find.text('理疗前状态'), findsOneWidget);
    expect(find.text('理疗后效果'), findsOneWidget);

    // 空字段区段不渲染
    expect(find.text('操作过程'), findsNothing);
    expect(find.text('客户反馈'), findsNothing);
    expect(find.text('部位'), findsNothing);
  });
}