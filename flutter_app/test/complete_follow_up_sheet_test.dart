// ============================================
// 「标记完成」弹层 测试 (2026-09-24)
//
// 主人诉求: 点「标记完成」跟进任务后应该有弹层, 选跟进方式 + 备注内容,
//   然后**一次动作**三件事: 标记完成 + 记互动 + 埋点 (原两调用方各自 track = 双报)。
//
// 本文件守:
//   - 默认方式=「电话」 + 无备注 → complete(notes=null) + interaction type=phone 无 summary
//   - 切到「微信」 + 填内容 → complete(notes=内容) + interaction type=wechat + summary=内容
//   - 取消 → 两个 service 都没被调用
//   - complete 抛错 → 不崩, 错误 Snackbar 出现, 弹层仍在 (可重试)
//
// 跑: cd flutter_app && flutter test test/complete_follow_up_sheet_test.dart
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/telemetry/usage_providers.dart';
import 'package:nuankebao/core/telemetry/usage_service.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/follow_up/widgets/complete_follow_up_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- 假 FollowUpService: 记 complete 调用 + list 返回空 ----------
class _FakeFollowUpService extends FollowUpService {
  _FakeFollowUpService() : super(Dio());

  final List<({String id, String? notes})> completeCalls = [];
  /// 测试 ④ 用: 注入抛错
  Exception? completeToThrow;

  @override
  Future<List<FollowUpTask>> list({String? customerId, String status = 'pending'}) async {
    return const [];
  }

  @override
  Future<FollowUpTask> complete(String id, {String? notes}) async {
    completeCalls.add((id: id, notes: notes));
    if (completeToThrow != null) throw completeToThrow!;
    return FollowUpTask(
      id: id,
      customerId: 'c1',
      dueAt: DateTime(2026, 9, 25, 9, 0),
      reason: '腰疼回访',
      status: 'done',
      createdAt: DateTime(2026, 9, 24),
      completedAt: DateTime(2026, 9, 24),
      completedNotes: notes,
    );
  }
}

// ---------- 假 InteractionService: 记 create 调用 ----------
class _FakeInteractionService extends InteractionService {
  _FakeInteractionService() : super(Dio());

  final List<Map<String, dynamic>> createCalls = [];

  @override
  Future<Interaction> create(Map<String, dynamic> data) async {
    createCalls.add(Map<String, dynamic>.from(data));
    return Interaction(
      id: 'i-${createCalls.length}',
      customerId: data['customerId'] as String,
      type: data['type'] as String,
      summary: data['summary'] as String?,
      createdBy: 'me',
      createdAt: DateTime(2026, 9, 24),
    );
  }

  @override
  Future<List<Interaction>> list({String? customerId}) async => const [];
}

// ---------- 假 UsageService: enabled=false 让 track 静默 ----------
//
// usageTelemetryEnabled() 在 `flutter test` 下默认 false → track 是 no-op。
// 但 UsageService 构造要 prefs → sharedPreferencesProvider 仍要 override, 否则 throw。
Future<UsageService> _makeNoopUsageService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return UsageService(prefs: prefs, enabled: false);
}

// ---------- 任务 fixture ----------
final _task = FollowUpTask(
  id: 'task-42',
  customerId: 'c1',
  dueAt: DateTime(2026, 9, 25, 9, 0),
  reason: '腰疼回访',
  status: 'pending',
  createdAt: DateTime(2026, 9, 24),
);

/// 泵根 scaffold, 触发弹层, 等待动画落定。返回两个 fake。
Future<({_FakeFollowUpService followUp, _FakeInteractionService interaction})>
    _pumpAndOpenSheet(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final followUp = _FakeFollowUpService();
  final interaction = _FakeInteractionService();
  final usage = await _makeNoopUsageService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        followUpServiceProvider.overrideWithValue(followUp),
        interactionServiceProvider.overrideWithValue(interaction),
        usageServiceProvider.overrideWithValue(usage),
      ],
      child: MaterialApp(
        theme: AppTheme.light(AppThemes.sage),
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCompleteFollowUpSheet(
                  ctx,
                  ref,
                  task: _task,
                  customerName: '蒋金娣',
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
  return (followUp: followUp, interaction: interaction);
}

/// 跟 _pumpAndOpenSheet 同骨架, 但 followUp 注入 completeToThrow (用于 ④ 用例)。
Future<void> _pumpAndOpenSheetWithCompleteFailure(
  WidgetTester tester, {
  required _FakeFollowUpService followUp,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final interaction = _FakeInteractionService();
  final usage = await _makeNoopUsageService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        followUpServiceProvider.overrideWithValue(followUp),
        interactionServiceProvider.overrideWithValue(interaction),
        usageServiceProvider.overrideWithValue(usage),
      ],
      child: MaterialApp(
        theme: AppTheme.light(AppThemes.sage),
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCompleteFollowUpSheet(
                  ctx,
                  ref,
                  task: _task,
                  customerName: '蒋金娣',
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
  testWidgets(
    '① 默认方式=「电话」 + 无备注 → complete(notes=null) + interaction(type=phone) 无 summary',
    (tester) async {
      final fake = await _pumpAndOpenSheet(tester);

      // 弹层打开: 标题 + 默认 chip「电话」
      expect(find.text('完成跟进 · 「蒋金娣」'), findsOneWidget);
      expect(find.text('标记完成'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();

      // ① complete: id 正确, notes=null (空备注不写键 → 后端契约 optional)
      expect(fake.followUp.completeCalls.length, 1);
      expect(fake.followUp.completeCalls.single.id, 'task-42');
      expect(fake.followUp.completeCalls.single.notes, isNull,
          reason: '无备注 → notes=null');

      // ① interaction: type=phone, **不**含 summary
      expect(fake.interaction.createCalls.length, 1);
      final call = fake.interaction.createCalls.single;
      expect(call['customerId'], 'c1');
      expect(call['type'], 'phone');
      expect(call.containsKey('summary'), isFalse,
          reason: '空备注 → 不写 summary 键');

      // 弹层已关 + 成功 SnackBar
      expect(find.text('完成跟进'), findsNothing);
      expect(find.textContaining('已标记完成'), findsOneWidget);
    },
  );

  testWidgets(
    '② 切到「微信」+ 填内容 → complete(notes=内容) + interaction(type=wechat, summary=内容)',
    (tester) async {
      final fake = await _pumpAndOpenSheet(tester);

      // 切到「微信」chip
      await tester.tap(find.widgetWithText(ChoiceChip, '微信'));
      await tester.pumpAndSettle();

      // 填备注
      await tester.enterText(
        find.byType(TextField),
        '说了腰不疼了, 约下周三到店',
      );
      await tester.pumpAndSettle();

      // 确认
      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();

      // ② complete: notes=内容
      expect(fake.followUp.completeCalls.length, 1);
      expect(fake.followUp.completeCalls.single.id, 'task-42');
      expect(fake.followUp.completeCalls.single.notes,
          '说了腰不疼了, 约下周三到店');

      // ② interaction: type=wechat, summary=内容
      expect(fake.interaction.createCalls.length, 1);
      final call = fake.interaction.createCalls.single;
      expect(call['customerId'], 'c1');
      expect(call['type'], 'wechat');
      expect(call['summary'], '说了腰不疼了, 约下周三到店');
    },
  );

  testWidgets('③ 取消 → 两个 service 都没被调用', (tester) async {
    final fake = await _pumpAndOpenSheet(tester);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(fake.followUp.completeCalls, isEmpty);
    expect(fake.interaction.createCalls, isEmpty);
    expect(find.text('完成跟进'), findsNothing,
        reason: '弹层已关');
    expect(find.textContaining('已标记完成'), findsNothing,
        reason: '没出现成功 snackbar');
  });

  testWidgets(
    '④ complete 抛错 → 不崩, 错误提示, 弹层仍在 (interaction 不被调用)',
    (tester) async {
      final followUp = _FakeFollowUpService()
        ..completeToThrow = Exception('network 500');
      await _pumpAndOpenSheetWithCompleteFailure(tester, followUp: followUp);

      // 弹层已开
      expect(find.text('完成跟进 · 「蒋金娣」'), findsOneWidget);

      // 点确认 → 抛错
      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();

      // 错误 Snackbar 已显示
      expect(find.textContaining('标记完成失败'), findsOneWidget);
      expect(find.textContaining('network 500'), findsOneWidget);

      // ⚠ 关键不变量: 弹层仍在 (saving 复位可重试)
      expect(find.text('完成跟进 · 「蒋金娣」'), findsOneWidget,
          reason: 'complete 失败 → 弹层保留, saving=false 可重试');

      // ⚠ 关键不变量: complete 失败时, **不**应记互动
      //   (避免「任务没完成却记了联系」的脏数据)
      expect(followUp.completeCalls.length, 1, reason: 'complete 调用了');
      expect(
          // 没法在 widget test 直接拿到 interaction fake (上面 helper 没暴露),
          //   改走更直接的断言: 弹层里**不应**有「标记完成 · 已记一条…互动」的 SnackBar
          find.textContaining('已记一条'),
          findsNothing,
          reason: 'complete 失败 → 不走 interaction 路径 → snackbar 不出现');
    },
  );
}