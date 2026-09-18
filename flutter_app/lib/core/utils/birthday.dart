// ============================================
// 生日工具 (主人 2026-09-18 拍: 生日提醒)
//
// 支持阳历 / **农历** 两种历法 → 算「距下次生日还有几天」/「下个生日是几月几号」
// 农历转换用 `lunar` 包 (6tail, MIT): Lunar.fromYmd(农历年, 月, 日).getSolar()
//
// 边界 (重要):
//   - 月 / 日 任一为空 → 算不出来, 返回 null (客户只填了年份也要能跑)
//   - 农历: 闰月不参与 (生日按普通月算, 正数月); 若某年该月是闰月 → 取正月初一那天
//   - 2/29 (阳历) 在平年 → 按 3/1 算? 不, 按「2 月最后一天」= 2/28 (主人可用, 不报错)
//   - 只做「未来 0-370 天」范围, 不回溯历史
// ============================================

import 'package:lunar/lunar.dart';

class BirthdayInfo {
  /// 距下次生日还有几天 (0 = 今天就是生日)
  final int daysUntil;
  /// 下次生日的阳历日期 (yyyy-MM-dd)
  final DateTime nextSolarDate;
  /// 生日文案 (例: '八月十五 (农历)' / '3月8日' / '只知道年份 1965')
  final String label;

  const BirthdayInfo({
    required this.daysUntil,
    required this.nextSolarDate,
    required this.label,
  });

  String get countdownLabel {
    if (daysUntil == 0) return '今天生日 🎂';
    if (daysUntil == 1) return '明天生日';
    return '$daysUntil 天后生日';
  }
}

/// 农历月日 → 文案 (数字转中文, 中老年看得懂)
String _lunarChinese(int month, int day) {
  const digits = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  String m() {
    if (month == 1) return '正月';
    if (month <= 10) return '${digits[month]}月';
    return month == 11 ? '冬月' : '腊月';
  }

  String d() {
    if (day <= 10) return '初${digits[day] == '十' ? '十' : digits[day]}';
    if (day < 20) return '十${digits[day - 10]}';
    if (day == 20) return '二十';
    if (day < 30) return '廿${digits[day - 20]}';
    return day == 30 ? '三十' : '廿${digits[day - 20]}';
  }

  return '${m()}${d()}';
}

/// 生日文案 (列表/详情显示用)
String birthdayLabel({
  required int? month,
  required int? day,
  String calendar = 'solar',
  int? year,
}) {
  if (month == null || day == null) {
    if (year != null) return '只知道年份 $year';
    return '未填';
  }
  if (calendar == 'lunar') {
    return '${_lunarChinese(month, day)} (农历)';
  }
  return '$month月$day日';
}

/// 下次生日的阳历日期 (含今天); 算不出来返回 null
DateTime? nextBirthdayDate({
  required int? month,
  required int? day,
  String calendar = 'solar',
  DateTime? from,
}) {
  if (month == null || day == null) return null;
  final today = from ?? DateTime.now();
  final base = DateTime(today.year, today.month, today.day);

  if (calendar == 'lunar') {
    // 农历: 试当年 + 下一年, 取第一个 >= 今天
    for (final y in [base.year, base.year + 1]) {
      try {
        final solar = Lunar.fromYmd(y, month, day).getSolar();
        final date = DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
        if (!date.isBefore(base)) return date;
      } catch (_) {
        // 该年没有这个农历日 (如 三十 在只有 29 天的月份) → 跳到下一年
        continue;
      }
    }
    return null;
  }

  // 阳历 (2/29 平年 → 按 3/1 算, 不会漏)
  DateTime build(int y) {
    final d = DateTime(y, month, day);
    if (d.month == month && d.day == day) return d;
    // 该年没有这个日期 (2/29) → 用 3/1
    return DateTime(y, 3, 1);
  }

  final thisYear = build(base.year);
  if (!thisYear.isBefore(base)) return thisYear;
  return build(base.year + 1);
}

/// 距下次生日还有几天 (含今天 = 0); 算不出来 null
int? daysUntilBirthday({
  required int? month,
  required int? day,
  String calendar = 'solar',
  DateTime? from,
}) {
  final next = nextBirthdayDate(
    month: month,
    day: day,
    calendar: calendar,
    from: from,
  );
  if (next == null) return null;
  final today = from ?? DateTime.now();
  final base = DateTime(today.year, today.month, today.day);
  return next.difference(base).inDays;
}

/// 完整信息 (文案 + 倒计时 + 下次阳历日期)
BirthdayInfo? birthdayInfo({
  required int? month,
  required int? day,
  String calendar = 'solar',
  int? year,
  DateTime? from,
}) {
  final next = nextBirthdayDate(
    month: month,
    day: day,
    calendar: calendar,
    from: from,
  );
  if (next == null) return null;
  final today = from ?? DateTime.now();
  final base = DateTime(today.year, today.month, today.day);
  return BirthdayInfo(
    daysUntil: next.difference(base).inDays,
    nextSolarDate: next,
    label: birthdayLabel(
      month: month,
      day: day,
      calendar: calendar,
      year: year,
    ),
  );
}

/// 是否落在「我设置的提醒窗口」内 (7/3/0 天前)
/// remindDays = null → 不提醒 → false
bool isInBirthdayRemindWindow({
  required int? month,
  required int? day,
  String calendar = 'solar',
  int? remindDays,
  DateTime? from,
}) {
  if (remindDays == null) return false;
  final d = daysUntilBirthday(
    month: month,
    day: day,
    calendar: calendar,
    from: from,
  );
  if (d == null) return false;
  return d <= remindDays;
}

/// 提醒强度文案
String remindLabel(int? remindDays) {
  switch (remindDays) {
    case 7:
      return '提前 7 天提醒';
    case 3:
      return '提前 3 天提醒';
    case 0:
      return '生日当天提醒';
    default:
      return '不提醒';
  }
}
