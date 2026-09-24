// ============================================
// CustomerFollowUpSection —— 跟进任务 tile 渲染测试 (2026-09-24)
//
// 主人反馈: 「点击跟进后, 直接创建了当天的跟进任务, 并且创建时就是已过期状态。
//   当前日期的待办状态应该还没过期。」
//
// 验证:
//   · dueAt=昨天 → 文案「MM-dd · 已过期」
//   · dueAt=今天 → 文案「今天到期」, 且**不**含「已过期」字样
//   · dueAt=明天 → 文案「明天到期」
//
// 跑: cd flutter_app && flutter test test/customer_follow_up_section_test.dart
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart' show AppTheme;
import 'package:nuankebao/core/theme/tokens.g.dart' show AppThemes;
import 'package:nuankebao/modules/customer/widgets/customer_activity_cards.dart';

/// Fake FollowUpService —— list 返回注入的 tasks, 其它 throw。
class _FakeFollowUpService extends FollowUpService {
  _FakeFollowUpService(this._fakeList) : super(Dio());

  final List<FollowUpTask> _fakeList;
  int listCalls = 0;

  @override
  Future<List<FollowUpTask>> list({
    String? customerId,
    String status = 'pending',
  }) async {
    listCalls++;
    return _fakeList;
  }
}

Widget _wrap({required Widget child, required FollowUpService fake}) {
  // 不挂全 page (避免副作用), 只挂 section widget + 假 service + 真主题。
  return ProviderScope(
    overrides: [
      followUpServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [child]),
        ),
      ),
    ),
  );
}

/// 构造一个本地时区的 DateTime (年/月/日/时/分) —— 不带 Z, 默认 toLocal 视角。
DateTime _local(int y, int m, int d, [int h = 9, int min = 0]) =>
    DateTime(y, m, d, h, min);

/// 泵 + 等到 ConsumerStatefulWidget 走完首帧。
Future<void> _pumpUntilSettled(WidgetTester tester) async {
  await tester.pump();
  // runAsync 让 FakeTime 推真实时间, 等 FutureProvider resolve + frame rebuild。
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  });
}

void main() {
  testWidgets(
    'dueAt=昨天 (本地 23:59, now=今天 10:00) → 显示「MM-dd · 已过期」',
    (tester) async {
      // 锚 now = 今天 10:00; dueAt = 昨天 23:59 → 应该判「已过期」
      final now = _local(2026, 9, 24, 10, 0);
      // 用相对 now 的「昨天」+「今天」, 避免测试在不同年份漂移 (用 2026 锚)。
      final yesterday = now.subtract(const Duration(days: 1));
      final dueAt = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59);
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't-overdue',
          customerId: 'c1',
          dueAt: dueAt,
          reason: '回访昨日到店',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.textContaining('已过期'), findsOneWidget,
          reason: '昨天任务应显示「已过期」');
      expect(find.textContaining('回访昨日到店'), findsOneWidget);
    },
  );

  testWidgets(
    'dueAt=今天 (now=同一天晚些时候) → 显示「今天到期」, 且**不**含「已过期」',
    (tester) async {
      // 锚 now = 今天 20:00; dueAt = 今天 08:00 → 今天到期
      final now = _local(2026, 9, 24, 20, 0);
      final dueAt = _local(2026, 9, 24, 8, 0);
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't-today',
          customerId: 'c1',
          dueAt: dueAt,
          reason: '问她腰好点没',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.text('今天到期'), findsOneWidget,
          reason: '今天到期 ≠ 已过期 (核心诉求)');
      expect(find.textContaining('已过期'), findsNothing,
          reason: '「今天到期」绝对不能同时显示「已过期」');
      expect(find.textContaining('问她腰好点没'), findsOneWidget);
    },
  );

  testWidgets(
    'dueAt=明天 → 显示「明天到期」',
    (tester) async {
      final now = _local(2026, 9, 24, 9, 0);
      final tomorrow = now.add(const Duration(days: 1));
      final dueAt = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't-tmr',
          customerId: 'c1',
          dueAt: dueAt,
          reason: '约下次到店',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.text('明天到期'), findsOneWidget);
      expect(find.textContaining('已过期'), findsNothing);
      expect(find.textContaining('约下次到店'), findsOneWidget);
    },
  );

  testWidgets(
    'dueAt=更远 (8 天后) → 显示「MM-dd 到期」 (无「已过期」无「今天到期」)',
    (tester) async {
      final now = _local(2026, 9, 24, 9, 0);
      final dueAt = now.add(const Duration(days: 8));
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't-far',
          customerId: 'c1',
          dueAt: dueAt,
          reason: '下月再联系',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.textContaining('到期'), findsOneWidget);
      expect(find.textContaining('已过期'), findsNothing);
      expect(find.text('今天到期'), findsNothing);
      expect(find.text('明天到期'), findsNothing);
    },
  );

  testWidgets(
    '列表同时含「逾期」和「今天」 → 各自走不同分支 (回归: 不会再都被标「已过期」)',
    (tester) async {
      final now = _local(2026, 9, 24, 20, 0);
      final yesterday = now.subtract(const Duration(days: 1));
      final dueOverdue = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59);
      final dueToday = _local(2026, 9, 24, 8, 0);
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't1',
          customerId: 'c1',
          dueAt: dueOverdue,
          reason: '逾期一条',
          status: 'pending',
          createdAt: now,
        ),
        FollowUpTask(
          id: 't2',
          customerId: 'c1',
          dueAt: dueToday,
          reason: '今天一条',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.textContaining('已过期'), findsOneWidget,
          reason: '逾期那条必须显示「已过期」');
      expect(find.text('今天到期'), findsOneWidget,
          reason: '今天那条必须显示「今天到期」');
      // 找两个 reason 都出现 (整体渲染没崩)
      expect(find.textContaining('逾期一条'), findsOneWidget);
      expect(find.textContaining('今天一条'), findsOneWidget);
    },
  );
}