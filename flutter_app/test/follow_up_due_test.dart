// ============================================
// 跟进任务 到期日帮助函数 —— 纯函数单测 (2026-09-24 用户反馈)
//
// 主人 2026-09-24 原话: 「点击跟进后, 直接创建了当天的跟进任务, 并且创建时就是已过期状态。
//   当前日期的待办状态应该还没过期。」
//
// 根因: `t.dueAt.isBefore(DateTime.now())` 按时间戳比 → 建完下一秒就误判"已过期";
//   另: API 返 UTC, 直接用 `.year/.month/.day` 在 CST 早晨会把今天误判昨天。
//
// 验证口径:
//   · 「今天到期」 → 不逾期
//   · 「昨天到期」 → 逾期
//   · 「明天到期」 → 不逾期
//   · followUpDaysUntilDue: 0 / 1 / -1 三档
//   · UTC 输入 + 指定 now → 内部自动转本地 (核心: 防 CST 早晨跨日坑)
//
// 跑: cd flutter_app && flutter test test/follow_up_due_test.dart
// ============================================

import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/follow_up.dart';

void main() {
  group('isFollowUpOverdue', () {
    test('今天 08:00 (now=今天 20:00) 不逾期', () {
      // 今天 08:00 local 的 dueAt, 当前是今天 20:00 local → 仍在「今天」 → 不逾期。
      final dueAt = DateTime(2026, 9, 24, 8, 0);
      final now = DateTime(2026, 9, 24, 20, 0);
      expect(isFollowUpOverdue(dueAt, now: now), isFalse,
          reason: '今天到期 ≠ 逾期 (核心诉求)');
    });

    test('昨天 23:59 (now=今天 00:01) 逾期', () {
      // 跨日边界: dueAt 昨天 23:59, now 今天 00:01 → 昨天 < 今天 → 逾期
      final dueAt = DateTime(2026, 9, 23, 23, 59);
      final now = DateTime(2026, 9, 24, 0, 1);
      expect(isFollowUpOverdue(dueAt, now: now), isTrue,
          reason: '昨天到期 → 逾期 (跨日边界)');
    });

    test('明天到期 → 不逾期', () {
      final dueAt = DateTime(2026, 9, 25, 9, 0);
      final now = DateTime(2026, 9, 24, 9, 0);
      expect(isFollowUpOverdue(dueAt, now: now), isFalse);
    });

    test('当前时刻 (now == dueAt) → 不算逾期', () {
      // 即时建单的口径: dueAt=now.toIsoString → 边界条件不算逾期
      final dueAt = DateTime(2026, 9, 24, 12, 0);
      final now = DateTime(2026, 9, 24, 12, 0);
      expect(isFollowUpOverdue(dueAt, now: now), isFalse);
    });

    test('「明天 00:00」 (now=今天 23:59:59) → 不逾期 (跨日即将到点)', () {
      final dueAt = DateTime(2026, 9, 25, 0, 0);
      final now = DateTime(2026, 9, 24, 23, 59, 59);
      expect(isFollowUpOverdue(dueAt, now: now), isFalse);
    });
  });

  group('followUpDaysUntilDue', () {
    test('0 = 今天', () {
      expect(followUpDaysUntilDue(
        DateTime(2026, 9, 24, 8, 0),
        now: DateTime(2026, 9, 24, 20, 0),
      ), 0);
    });

    test('1 = 明天', () {
      expect(followUpDaysUntilDue(
        DateTime(2026, 9, 25, 9, 0),
        now: DateTime(2026, 9, 24, 9, 0),
      ), 1);
    });

    test('-1 = 昨天 (逾期 1 天)', () {
      expect(followUpDaysUntilDue(
        DateTime(2026, 9, 23, 23, 59),
        now: DateTime(2026, 9, 24, 0, 1),
      ), -1);
    });

    test('7 = 本周边界', () {
      expect(followUpDaysUntilDue(
        DateTime(2026, 10, 1, 9, 0),
        now: DateTime(2026, 9, 24, 9, 0),
      ), 7);
    });

    test('8 = 更远 (本周之后)', () {
      expect(followUpDaysUntilDue(
        DateTime(2026, 10, 2, 9, 0),
        now: DateTime(2026, 9, 24, 9, 0),
      ), 8);
    });
  });

  group('followUpDueDay + UTC 跨日防护 (CST 早晨坑)', () {
    test('UTC 输入 → 内部 .toLocal() 后取本地日期', () {
      // 模拟 API 返的 UTC ISO: 2026-09-24T17:00:00Z
      // 本机 CST (UTC+8) → 本地 2026-09-25 01:00
      // 旧实现直接 .year/.month/.day 在 UTC 是 09-24 (对了); 但
      // 若 UTC 是 2026-09-23T20:00:00Z → 本地 2026-09-24 04:00,
      //   旧实现 .year/.month/.day 在 UTC 是 09-23 → 误判成「昨天」。
      final utcInput = DateTime.utc(2026, 9, 23, 20, 0);
      // 本机时区跑测试无所谓 (CI 通常是 UTC); 验证函数对同一 input
      //   总是给「本地日期的 00:00」 (toLocal 后置零)。
      final day = followUpDueDay(utcInput);
      final local = utcInput.toLocal();
      expect(day, DateTime(local.year, local.month, local.day),
          reason: 'followUpDueDay 必然 = toLocal 后的 00:00');
    });

    test('daysUntilDue 对 UTC 输入 + 指定 local now → 仍然按本地日期算', () {
      // 强制构造一个跨日场景:
      //   dueAt UTC = 2026-09-23T20:00:00Z  (本地: 2026-09-24 04:00 CST)
      //   now 本地 = 2026-09-24 02:00 CST
      // 预期: dueAt 的本地日期 == now 的本地日期 == 09-24 → diff = 0
      // 旧实现 (直接用 UTC 年月日算) 会判 -1 → 逾期 (用户反馈坑)
      final dueUtc = DateTime.utc(2026, 9, 23, 20, 0); // 本地 2026-09-24 04:00
      // now 必须用本地时区构造; 用「假定 CI 在 UTC」: 把 CST 早晨换算成 UTC
      //   2026-09-24 02:00 CST = 2026-09-23T18:00:00Z
      // 我们不假设时区, 只断言「diff 跟直接走 .toLocal 后的字段差一致」。
      final now = DateTime(2026, 9, 24, 2, 0); // 用本地构造
      final diff = followUpDaysUntilDue(dueUtc, now: now);
      // expected = (due 的本地年/月/日).diff(now 的本地年/月/日).inDays
      final expectedDiff = DateTime(
        dueUtc.toLocal().year,
        dueUtc.toLocal().month,
        dueUtc.toLocal().day,
      ).difference(DateTime(now.year, now.month, now.day)).inDays;
      expect(diff, expectedDiff,
          reason: 'daysUntilDue 必须按本地日期比, 不受 UTC 影响');
    });
  });

  group('与后端 urgency.ts 同口径 (互查)', () {
    test('isOverdue=false 等价 daysBetween==0', () {
      // 后端 src/lib/follow-up/urgency.ts: daysBetween > 0 = 已逾期
      // Flutter: followUpDaysUntilDue < 0 = 已逾期
      // 互查: daysUntilDue=0 (今天) → not overdue ✓
      final dueAt = DateTime(2026, 9, 24, 9, 0);
      final now = DateTime(2026, 9, 24, 18, 0);
      expect(isFollowUpOverdue(dueAt, now: now), isFalse);
      expect(followUpDaysUntilDue(dueAt, now: now), 0);
    });

    test('isOverdue=true 等价 daysBetween>0', () {
      // 互查: daysUntilDue=-3 (逾期 3 天) → overdue ✓
      final dueAt = DateTime(2026, 9, 21, 9, 0);
      final now = DateTime(2026, 9, 24, 9, 0);
      expect(isFollowUpOverdue(dueAt, now: now), isTrue);
      expect(followUpDaysUntilDue(dueAt, now: now), -3);
    });
  });
}