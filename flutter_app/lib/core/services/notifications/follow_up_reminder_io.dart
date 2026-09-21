// ============================================
// 跟进提醒 — native (Android/iOS) 真实现
// ============================================
// 用 flutter_local_notifications 排一条**每天固定时刻**的本地通知 (§5 L3)。
//   - Android: 用 inexactAllowWhileIdle 排程 —— **不要** SCHEDULE_EXACT_ALARM 权限
//     (Android 14 起要用户手动授权, 为了"每天 08:30"这种提醒去要精确闹钟权限不划算;
//      误差可能是几分钟到半小时, 对"今天要联系谁"完全够用)
//   - iOS: DarwinInitializationSettings 不预先要权限, 等用户开开关时 [requestPermission] 再要
//
// 通知 id 固定 (1): 重排 = 覆盖旧的, 不会攒一堆重复通知。

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'follow_up_reminder.dart';

/// 固定的通知 id (重复排程用同一个 → 互相覆盖)
const int _notificationId = 1;

/// 点通知 → 冷启动 / 后台唤醒时, 首次拿到回调就先存起来, 等 onTap 注入后再触发
final _plugin = FlutterLocalNotificationsPlugin();

class _IoFollowUpReminder implements FollowUpReminder {
  @override
  void Function()? onTap;

  bool _inited = false;

  Future<void> _ensureInit() async {
    if (_inited) return;

    // 时区: 用设备真实时区排"每天 08:30" (tz.local 默认是 UTC, 不设会晚 8 小时)
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      // 取不到设备时区 (老 Android / 权限受限) → tz.local 保持默认。
      // 不抛错: 提醒晚几个小时也好过整个开关打不开
      debugPrint('[FollowUpReminder] 取设备时区失败, 用默认: $e');
    }

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => onTap?.call(),
    );

    _inited = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureInit();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? true; // null = 系统版本 < 33, 默认有权限
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  @override
  Future<void> scheduleDaily({required int dueCount}) async {
    await _ensureInit();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'follow_up_daily',
        '跟进提醒',
        channelDescription: '每天早上提醒今天要跟进的客户',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      _notificationId,
      '今天的跟进提醒',
      FollowUpReminder.bodyFor(dueCount),
      _nextInstanceOfReminderTime(),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // 每天同一时刻重复 (系统自己排, 不需要 App 常驻)
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel() async {
    await _ensureInit();
    await _plugin.cancel(_notificationId);
  }

  /// 下一个 08:30 (今天已过 → 明天)
  tz.TZDateTime _nextInstanceOfReminderTime() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      FollowUpReminder.hour,
      FollowUpReminder.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

FollowUpReminder createFollowUpReminder() => _IoFollowUpReminder();
