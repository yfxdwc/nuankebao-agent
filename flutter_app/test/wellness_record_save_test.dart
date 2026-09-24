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

  testWidgets('②-b 下次建议日期快捷档位 = 明天 / 3 / 7 / 10 天后', (tester) async {
    final wellness = _FakeWellnessService();
    await _pump(
      tester,
      form: const WellnessRecordFormPage(customerId: 'c1'),
      wellness: wellness,
      followUps: _FakeFollowUpService(),
    );

    // 主人 2026-09-24: 「快速选择标签改为: 明天、3天后、7天后、10天后」
    expect(find.text('明天'), findsOneWidget);
    expect(find.text('3 天后'), findsOneWidget);
    expect(find.text('7 天后'), findsOneWidget);
    expect(find.text('10 天后'), findsOneWidget);
    // 旧的档位不该再出现
    expect(find.text('14 天后'), findsNothing);
    expect(find.text('30 天后'), findsNothing);

    // 点「明天」→ 日期按钮显示明天, 且该 chip 选中
    await tester.tap(find.text('明天'));
    await tester.pumpAndSettle();

    final tmr = DateTime.now().add(const Duration(days: 1));
    final label =
        '${tmr.year}-${tmr.month.toString().padLeft(2, '0')}-${tmr.day.toString().padLeft(2, '0')}';
    expect(find.text(label), findsOneWidget,
        reason: '点「明天」后日期按钮显示明天日期');
    final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '明天'));
    expect(chip.selected, isTrue, reason: '选中的档位要高亮');
  });

  testWidgets('③ 常用短语: 同一个短语连点**不会**重复写入', (tester) async {
    final wellness = _FakeWellnessService();
    await _pump(
      tester,
      form: const WellnessRecordFormPage(customerId: 'c1'),
      wellness: wellness,
      followUps: _FakeFollowUpService(),
    );

    // 第 1 个 TextField = 「操作过程」(服务项目是弹层字段, 不是 TextField)
    TextField processField() => tester.widget<TextField>(find.byType(TextField).first);

    await tester.tap(find.widgetWithText(ActionChip, '动作到位'));
    await tester.pumpAndSettle();
    expect(processField().controller!.text, '动作到位');

    // 连点第二次 → 不再追加; chip 变「已加」态 (不可点)
    await tester.tap(find.widgetWithText(ActionChip, '动作到位'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(processField().controller!.text, '动作到位',
        reason: '同一短语不能重复写入 (主人 2026-09-24 报的 bug)');
    final chip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, '动作到位'));
    expect(chip.onPressed, isNull, reason: '已加的短语 chip 不可再点');

    // 换一个短语 → 正常追加 (用 ` · ` 分隔)
    await tester.tap(find.widgetWithText(ActionChip, '加了拔罐'));
    await tester.pumpAndSettle();
    expect(processField().controller!.text, '动作到位 · 加了拔罐');
  });

  testWidgets('③-b 手动把短语打进文本框 → chip 也认「已加」', (tester) async {
    final wellness = _FakeWellnessService();
    await _pump(
      tester,
      form: const WellnessRecordFormPage(customerId: 'c1'),
      wellness: wellness,
      followUps: _FakeFollowUpService(),
    );

    final field = tester.widget<TextField>(find.byType(TextField).first);
    field.controller!.text = '今天动作到位, 客户说舒服';
    await tester.pumpAndSettle();

    // 手打进去之后 → 再点同一个 chip 不会重复追加 (tap 时二次判定)
    await tester.tap(find.widgetWithText(ActionChip, '动作到位'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(field.controller!.text, '今天动作到位, 客户说舒服',
        reason: '手打进去的也算已加 (含子串判定), 不会重复追加');

    // 这次 tap 触发了重建 → chip 应该已经变成「已加」(不可点)
    final chip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, '动作到位'));
    expect(chip.onPressed, isNull, reason: '重建后 chip 显示为已加');
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
