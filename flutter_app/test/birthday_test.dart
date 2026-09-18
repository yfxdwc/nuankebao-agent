// 生日工具单测 (主人 2026-09-18 拍: 阳历/农历 + 提醒窗口)
// 农历锚点用公开常识校验 (春节/中秋), 不跟实现自证
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/utils/birthday.dart';

void main() {
  group('阳历', () {
    test('今天就是生日 → 0 天', () {
      expect(
        daysUntilBirthday(
            month: 9, day: 18, from: DateTime(2026, 9, 18)),
        0,
      );
    });

    test('还没到 (今年内) → 正数天数', () {
      expect(
        daysUntilBirthday(month: 12, day: 31, from: DateTime(2026, 9, 18)),
        104,
      );
    });

    test('今年已过 → 算到明年', () {
      expect(
        daysUntilBirthday(month: 3, day: 8, from: DateTime(2026, 9, 18)),
        171, // 2026-09-18 → 2027-03-08
      );
    });

    test('2/29 在平年按 3/1 算 (不漏)', () {
      final d = nextBirthdayDate(month: 2, day: 29, from: DateTime(2027, 1, 1));
      expect(d, DateTime(2027, 3, 1));
    });

    test('月/日 缺一个 → 算不出来 (null)', () {
      expect(daysUntilBirthday(month: 8, day: null), isNull);
      expect(daysUntilBirthday(month: null, day: 15), isNull);
    });
  });

  group('农历 (lunar 包校验)', () {
    test('2026 春节 = 正月初一 = 2026-02-17', () {
      final d = nextBirthdayDate(
          month: 1, day: 1, calendar: 'lunar', from: DateTime(2026, 1, 1));
      expect(d, DateTime(2026, 2, 17));
    });

    test('2025 春节 = 2025-01-29 (已过 → 算到 2026)', () {
      final d = nextBirthdayDate(
          month: 1, day: 1, calendar: 'lunar', from: DateTime(2025, 3, 1));
      expect(d, DateTime(2026, 2, 17));
    });

    test('2024 中秋 = 八月十五 = 2024-09-17', () {
      final d = nextBirthdayDate(
          month: 8, day: 15, calendar: 'lunar', from: DateTime(2024, 1, 1));
      expect(d, DateTime(2024, 9, 17));
    });

    test('2026 中秋 = 八月十五 = 2026-09-25', () {
      final d = nextBirthdayDate(
          month: 8, day: 15, calendar: 'lunar', from: DateTime(2026, 1, 1));
      expect(d, DateTime(2026, 9, 25));
    });

    test('农历文案 = 八月十五 (农历)', () {
      expect(
        birthdayLabel(month: 8, day: 15, calendar: 'lunar'),
        '八月十五 (农历)',
      );
      expect(birthdayLabel(month: 12, day: 30, calendar: 'lunar'), '腊月三十 (农历)');
      expect(birthdayLabel(month: 1, day: 2, calendar: 'lunar'), '正月初二 (农历)');
    });
  });

  group('提醒窗口', () {
    test('提前 7 天: 还有 5 天 → 在窗口内', () {
      expect(
        isInBirthdayRemindWindow(
            month: 9, day: 23, remindDays: 7, from: DateTime(2026, 9, 18)),
        isTrue,
      );
    });

    test('提前 3 天: 还有 5 天 → 不在窗口内', () {
      expect(
        isInBirthdayRemindWindow(
            month: 9, day: 23, remindDays: 3, from: DateTime(2026, 9, 18)),
        isFalse,
      );
    });

    test('不提醒 (null) → 永远 false', () {
      expect(
        isInBirthdayRemindWindow(
            month: 9, day: 18, remindDays: null, from: DateTime(2026, 9, 18)),
        isFalse,
      );
    });

    test('生日当天 (0 天) 在窗口内', () {
      expect(
        isInBirthdayRemindWindow(
            month: 9, day: 18, remindDays: 0, from: DateTime(2026, 9, 18)),
        isTrue,
      );
    });
  });

  test('只知道年份 → 文案提示, 倒计时 null', () {
    expect(birthdayLabel(month: null, day: null, year: 1945), '只知道年份 1945');
    expect(daysUntilBirthday(month: null, day: null), isNull);
  });
}
