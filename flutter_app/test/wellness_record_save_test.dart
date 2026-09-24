// ============================================
// 养生记录表单 —— 保存链路 (2026-09-24 批量改进)
//
// 主人 2026-09-24: 「做你建议的1到12条+14条」—— 本文件守其中的数据正确性部分:
//   ① **编辑不改日期** (P0 bug: 原来 _submit 一律发今天, 编辑老记录会挪到今天)
//   ② 新建发今天 + 服务项目/部位/评分都进 payload
//   ③ 身体部位已选置顶 + 未选超 8 个折叠
//
// 用 GoRouter (表单保存成功会 context.pop(), 没 router 会抛)
//
// 跑: cd flutter_app && flutter test test/wellness_record_save_test.dart
// ============================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nuankebao/core/models/dictionaries.dart';
import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/models/wellness_record.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/modules/wellness/screens/wellness_record_form_page.dart';

class _FakeWellnessService extends WellnessRecordService {
  _FakeWellnessService({this.existing}) : super(Dio());

  final WellnessRecord? existing;
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, dynamic>> updated = [];

  @override
  Future<WellnessRecord> getById(String id) async => existing!;

  @override
  Future<List<WellnessRecord>> list({String? customerId, int limit = 50}) async =>
      const [];

  @override
  Future<WellnessRecord> create(Map<String, dynamic> data) async {
    created.add(Map<String, dynamic>.from(data));
    return _asRecord(data);
  }

  @override
  Future<WellnessRecord> update(String id, Map<String, dynamic> data) async {
    updated.add(Map<String, dynamic>.from(data));
    return _asRecord(data);
  }

  WellnessRecord _asRecord(Map<String, dynamic> d) => WellnessRecord(
        id: 'new',
        customerId: '${d['customerId']}',
        serviceDate: '${d['serviceDate']}',
        serviceItemId: '${d['serviceItemId']}',
        createdAt: DateTime(2026, 9, 24),
      );
}

class _FakeFollowUpService extends FollowUpService {
  _FakeFollowUpService() : super(Dio());
  int createCalls = 0;

  @override
  Future<List<FollowUpTask>> list({String? customerId, String status = 'pending'}) async =>
      const [];

  @override
  Future<FollowUpTask> create(Map<String, dynamic> data) async {
    createCalls++;
    return FollowUpTask(
      id: 't1',
      customerId: '${data['customerId']}',
      dueAt: DateTime.parse('${data['dueAt']}'),
      reason: '${data['reason']}',
      status: 'pending',
      createdAt: DateTime(2026, 9, 24),
    );
  }
}

class _FakeDictAdapter implements HttpClientAdapter {
  _FakeDictAdapter(this.payload);
  final Map<String, dynamic> payload;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(payload), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dictionaries _dict({int bodyParts = 3}) => Dictionaries(
      bodyParts: [
        for (var i = 0; i < bodyParts; i++) BodyPart(id: '$i', name: '部位$i'),
      ],
      serviceItems: const [
        ServiceItem(id: 's1', name: '肩颈经络理疗'),
        ServiceItem(id: 's9', name: '碧波庭-脉动负压提拉按摩'),
      ],
      products: const [],
    );

WellnessRecord _oldRecord() => WellnessRecord(
      id: 'r1',
      customerId: 'c1',
      serviceDate: '2026-09-14',
      serviceItemId: 's1',
      bodyPartIds: const ['0'],
      preCondition: const {'pain_level': 8, 'sleep_quality': 2, 'mood': 3},
      postCondition: const {'pain_level': 3, 'sleep_quality': 4, 'mood': 5},
      createdAt: DateTime(2026, 9, 14),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Widget form,
  required WellnessRecordService wellness,
  required FollowUpService followUps,
  Dictionaries? dict,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _FakeDictAdapter((dict ?? _dict()).toJson());
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => ctx.push('/form'),
                child: const Text('打开表单'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(path: '/form', builder: (_, __) => form),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      wellnessRecordServiceProvider.overrideWithValue(wellness),
      followUpServiceProvider.overrideWithValue(followUps),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开表单'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① 新建: payload 里 serviceDate = 今天 (默认)', (tester) async {
    final wellness = _FakeWellnessService();
    await _pump(
      tester,
      form: const WellnessRecordFormPage(customerId: 'c1'),
      wellness: wellness,
      followUps: _FakeFollowUpService(),
    );

    // 记录日期区块默认显示「今天」
    expect(find.text('记录日期'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(wellness.created, hasLength(1));
    final today = DateTime.now();
    final expectDate =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    expect(wellness.created.single['serviceDate'], expectDate);
  });

  testWidgets('② 编辑: **保留原记录日期** (P0 bug 回归 —— 以前会被改成今天)',
      (tester) async {
    final wellness = _FakeWellnessService(existing: _oldRecord());
    await _pump(
      tester,
      form: const WellnessRecordFormPage(recordId: 'r1'),
      wellness: wellness,
      followUps: _FakeFollowUpService(),
    );

    // 表单里显示的是原日期 (2026-09-14), 不是「今天」
    expect(find.text('2026-09-14'), findsOneWidget);
    expect(find.text('今天'), findsNothing);

    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(wellness.updated, hasLength(1));
    expect(wellness.updated.single['serviceDate'], '2026-09-14',
        reason: '编辑绝不能把记录日期改成今天 (时间线/趋势/复购周期全跟着错)');
  });

  testWidgets('③ 身体部位: 已选置顶 + 未选超 8 个折叠', (tester) async {
    final wellness = _FakeWellnessService(existing: _oldRecord());
    await _pump(
      tester,
      form: const WellnessRecordFormPage(recordId: 'r1'),
      wellness: wellness,
      followUps: _FakeFollowUpService(),
      dict: _dict(bodyParts: 14),
    );

    // 原记录选了「部位0」→ 它应排在最前 (左上角位置最小)
    final first = tester.getTopLeft(find.text('部位0'));
    final second = tester.getTopLeft(find.text('部位1'));
    expect(first.dy, lessThanOrEqualTo(second.dy),
        reason: '已选的「部位0」要置顶');
    if (first.dy == second.dy) {
      expect(first.dx, lessThanOrEqualTo(second.dx));
    }

    // 14 个部位 - 1 已选 = 13 未选; 折叠后只显示 8 个 → 「还有 5 个」
    expect(find.text('还有 5 个'), findsOneWidget);
    expect(find.text('部位13'), findsNothing, reason: '折叠时第 13 个不该渲染');

    // 展开 → 全部可见
    await tester.tap(find.text('还有 5 个'));
    await tester.pumpAndSettle();
    expect(find.text('部位13'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });
}
