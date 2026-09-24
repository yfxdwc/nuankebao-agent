// ============================================
// 养生记录编辑保存后 wellnessRecordByIdProvider 失效 (回归测试)
//
// Reviewer (独立评审) 反馈:
//   wellness_record_detail_sheet 的 body 共用 wellnessRecordByIdProvider(id),
//   编辑保存链路里 form_page 调了 `ref.invalidate(wellnessRecordByIdProvider(...))`,
//   但**没有**测试守护这条失效 —— 哪天有人不小心删了那行 invalidate,
//   弹层 / 详情页就会一直显示旧 processNote, 看起来「保存了但弹层没动」
//   (静默回归)。
//
// 本文件用 ProviderContainer 跨表生命周期:
//   1. 装一个 ProviderContainer, override service (getById 按内部状态切换)
//      + override dio 让字典加载 (form body 需要字典才渲染保存按钮)
//   2. 启 form_page (recordId='r1') → form 自己调 service.getById 读初值
//   3. 改 processNote TextField → tap 保存修改
//   4. form 走完 save → invalidates by-id provider, pop
//   5. 重新 read provider → 应该拿到新值 (processNote='NEW_NOTE')
//
// 跑: cd flutter_app && flutter test test/wellness_edit_invalidate_test.dart
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
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart' show AppTheme;
import 'package:nuankebao/core/theme/tokens.g.dart' show AppThemes;
import 'package:nuankebao/modules/wellness/screens/wellness_record_form_page.dart';

class _StatefulFakeService extends WellnessRecordService {
  _StatefulFakeService({
    required this.beforeUpdate,
    required this.afterUpdate,
  }) : super(Dio());

  final WellnessRecord beforeUpdate;
  final WellnessRecord afterUpdate;
  bool _wasUpdated = false;

  @override
  Future<WellnessRecord> getById(String id) async {
    return _wasUpdated ? afterUpdate : beforeUpdate;
  }

  @override
  Future<WellnessRecord> update(String id, Map<String, dynamic> data) async {
    _wasUpdated = true;
    return afterUpdate;
  }
}

class _FakeFollowUpService extends FollowUpService {
  _FakeFollowUpService() : super(Dio());
  @override
  Future<List<FollowUpTask>> list({String? customerId, String status = 'pending'}) async => const <FollowUpTask>[];
  @override
  Future<FollowUpTask> create(Map<String, dynamic> data) async => FollowUpTask(
        id: 'no-op',
        customerId: '${data['customerId']}',
        dueAt: DateTime.now(),
        reason: 'mock',
        status: 'pending',
        createdAt: DateTime.now(),
      );
}

class _FakeDictAdapter implements HttpClientAdapter {
  _FakeDictAdapter(this.payload);
  final Map<String, dynamic> payload;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(jsonEncode(payload), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

WellnessRecord _oldRecord() => WellnessRecord(
      id: 'r1',
      customerId: 'c1',
      serviceDate: '2026-09-14',
      serviceItemId: 's1',
      bodyPartIds: const [],
      preCondition: const {'pain_level': 8, 'sleep_quality': 5, 'mood': 5},
      postCondition: const {'pain_level': 3, 'sleep_quality': 7, 'mood': 8},
      processNote: 'OLD_NOTE',
      customerFeedback: 'OLD_FEEDBACK',
      createdAt: DateTime(2026, 9, 14),
    );

WellnessRecord _newRecord() => WellnessRecord(
      id: 'r1',
      customerId: 'c1',
      serviceDate: '2026-09-14',
      serviceItemId: 's1',
      bodyPartIds: const [],
      preCondition: const {'pain_level': 8, 'sleep_quality': 5, 'mood': 5},
      postCondition: const {'pain_level': 3, 'sleep_quality': 7, 'mood': 8},
      processNote: 'NEW_NOTE',
      customerFeedback: 'NEW_FEEDBACK',
      createdAt: DateTime(2026, 9, 14),
    );

const _dict = Dictionaries(
  bodyParts: [BodyPart(id: 'b1', name: '肩颈')],
  serviceItems: [
    ServiceItem(id: 's1', name: '肩颈经络理疗'),
    ServiceItem(id: 's9', name: '碧波庭-脉动负压提拉按摩'),
  ],
  products: [],
);

void main() {
  testWidgets(
    '编辑保存后 → wellnessRecordByIdProvider(r1) 重新 fetch, 返回新值 (processNote=NEW_NOTE)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      // form 的 ListView 在默认屏高下, TextField 可能被推下屈 —— 与 wellness_record_save_test 同样需要大屏
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final prefs = await SharedPreferences.getInstance();
      final svc = _StatefulFakeService(
        beforeUpdate: _oldRecord(),
        afterUpdate: _newRecord(),
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
        ..httpClientAdapter = _FakeDictAdapter(_dict.toJson());

      final container = ProviderContainer(
        overrides: <Override>[
          // settings_provider 不被 override 会抦 UnimplementedError
          // (UsageService.track() 会跳进 sharedPreferencesProvider)
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
          wellnessRecordServiceProvider.overrideWithValue(svc),
          followUpServiceProvider.overrideWithValue(_FakeFollowUpService()),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/edit',
        routes: [
          GoRoute(
            path: '/edit',
            builder: (_, __) => WellnessRecordFormPage(recordId: 'r1'),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(AppThemes.sage),
          ),
        ),
      );
      // form 的 initState 会跑 _loadDict() + _loadExisting() → 等异步完成
      await tester.pumpAndSettle();

      // 预热 by-id provider (form 自己直接读 service, 不会自动读这个 family)
      final provider = wellnessRecordByIdProvider('r1');
      final pre = await container.read(provider.future);
      expect(pre.processNote, 'OLD_NOTE',
          reason: '保存前 provider 应给 OLD');

      // 改 processNote TextField (表单里第一个 TextField = 操作过程)
      final fieldFinder = find.byType(TextField).first;
      expect(fieldFinder, findsOneWidget);
      await tester.enterText(fieldFinder, 'NEW_NOTE');
      await tester.pumpAndSettle();

      // 保存
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      // form 已 pop; provider 已被 invalidate (form._submit 调了 invalidate)
      // 重新 read → 应该触发 service.getById (内部 _wasUpdated=true) → 拿到 NEW
      final post = await container.read(provider.future);
      expect(post.processNote, 'NEW_NOTE',
          reason:
              '编辑保存后 by-id provider 必须重新 fetch, 否则弹层 / 详情页永远显示 OLD');
    },
  );
}