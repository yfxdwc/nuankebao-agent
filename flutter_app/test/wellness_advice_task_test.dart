// ============================================
// 养生记录「下次建议日期」→ 自动建跟进任务 (2026-09-24)
//
// 主人问题: 「添加养生记录页中如果选择了下次建议日期，保存后是否应该自动创建
//   跟进任务?」→ 是 (明确指定的跟进时点 = 可落地的指引)。
//
// 守什么:
//   ① 没有 pending 任务 → 建一条: dueAt = 建议日期当天 09:00 (本地),
//      reason = 「按建议日期回访」
//   ② 已有 pending 任务 → **不重复建** (返回 null; 与每日生成脚本
//      「一人同时只留一条 pending」同口径)
//   ③ 建任务失败 → 异常往上抛 (调用方静默: 记录已保存才是主操作)
//
// 纯函数 + 假 service, 不依赖 widget tree (表单里只是接线 + SnackBar)。
//
// 跑: cd flutter_app && flutter test test/wellness_advice_task_test.dart
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/modules/wellness/screens/wellness_record_form_page.dart'
    show createAdviceFollowUpTaskIfAbsent;

class _FakeFollowUpService extends FollowUpService {
  _FakeFollowUpService({this.pending = const [], this.createError})
      : super(Dio());

  final List<FollowUpTask> pending;
  final Object? createError;

  int listCalls = 0;
  final List<Map<String, dynamic>> createCalls = [];

  @override
  Future<List<FollowUpTask>> list({
    String? customerId,
    String status = 'pending',
  }) async {
    listCalls++;
    return pending;
  }

  @override
  Future<FollowUpTask> create(Map<String, dynamic> data) async {
    createCalls.add(Map<String, dynamic>.from(data));
    if (createError != null) throw createError!;
    return FollowUpTask(
      id: 'new-1',
      customerId: data['customerId'] as String,
      dueAt: DateTime.parse(data['dueAt'] as String),
      reason: data['reason'] as String,
      status: 'pending',
      createdAt: DateTime(2026, 9, 24),
    );
  }
}

FollowUpTask _pendingTask() => FollowUpTask(
      id: 'p1',
      customerId: 'c1',
      dueAt: DateTime(2026, 9, 20, 9),
      reason: '原有待办',
      status: 'pending',
      createdAt: DateTime(2026, 9, 15),
    );

void main() {
  test('① 没有 pending → 按建议日期建任务 (当天 09:00 本地)', () async {
    final fake = _FakeFollowUpService();
    final advice = DateTime(2026, 10, 8);

    final task = await createAdviceFollowUpTaskIfAbsent(
      followUps: fake,
      customerId: 'c1',
      adviceDate: advice,
    );

    expect(fake.listCalls, 1, reason: '先查该客户有没有 pending');
    expect(fake.createCalls, hasLength(1));
    final body = fake.createCalls.single;
    expect(body['customerId'], 'c1');
    expect(body['reason'], '按建议日期回访');
    // 建议日期是"日", 任务需要"时间点" → 当天 09:00 (本地) 转 UTC
    final due = DateTime.parse(body['dueAt'] as String).toLocal();
    expect([due.year, due.month, due.day, due.hour], [2026, 10, 8, 9]);
    expect(task, isNotNull);
  });

  test('② 已有 pending → 不重复建 (返回 null, 也没发 create)', () async {
    final fake = _FakeFollowUpService(pending: [_pendingTask()]);

    final task = await createAdviceFollowUpTaskIfAbsent(
      followUps: fake,
      customerId: 'c1',
      adviceDate: DateTime(2026, 10, 8),
    );

    expect(task, isNull, reason: '一人同时只留一条 pending');
    expect(fake.createCalls, isEmpty);
  });

  test('③ create 失败 → 异常上抛 (由调用方静默, 不影响记录已保存)', () async {
    final fake = _FakeFollowUpService(createError: Exception('boom'));

    await expectLater(
      createAdviceFollowUpTaskIfAbsent(
        followUps: fake,
        customerId: 'c1',
        adviceDate: DateTime(2026, 10, 8),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
