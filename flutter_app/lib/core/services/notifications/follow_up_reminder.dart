// ============================================
// 跟进提醒 — 本地通知 (主人 2026-09-20 拍 Q6: 要本地通知)
// ============================================
// 方案: docs/follow-up-list-plan.md §5 三层提醒的 **L3**, §10.3
//   每天 08:30 一条「今天有 N 位客户要跟进」→ 点击进 `/follow-ups` 待办页
//
// 为什么用 flutter_local_notifications (而不是服务端推送):
//   免费 + 不依赖 FCM (国内不可用) + 不需要服务端多一套推送链路 (方案 §5 后续项)
//
// ⚠ 平台差异 (条件 import, 见下):
//   - native (Android/iOS): 真实现 follow_up_reminder_io.dart
//   - web (预览站 public/app): 空实现 follow_up_reminder_stub.dart
//     —— flutter_local_notifications 依赖 dart:io (linux 实现走 dbus), web 编译会炸;
//        预览站是在用的东西 (nuankebao-flutter-web-watch.service 自动重建), 不能让它 build 不过
//
// 已知取舍 (写下来免得以后当 bug):
//   - **数字是"上次刷新时"的**: 本地通知不能跑后台任务去查库, 所以通知正文在
//     「打开 App + 待办数变化」时重排 (见 profile_page 的 _FollowUpReminderTile)。
//     连续几天不开 App → 数字会偏旧 (但提醒本身每天照响)。要"每天现算"就得服务端推送。
//   - **重复提醒靠系统**: zonedSchedule + matchDateTimeComponents.time = 每天同一时刻, App 不用常驻

import 'follow_up_reminder_stub.dart'
    if (dart.library.io) 'follow_up_reminder_io.dart' as platform;

abstract class FollowUpReminder {
  /// 提醒时刻 (主人 Q6: 每日 08:30 汇总, 一条就够, 不做"每分钟催")
  static const int hour = 8;
  static const int minute = 30;

  /// 通知正文 (N = 待办客户数)
  static String bodyFor(int dueCount) => dueCount > 0
      ? '今天有 $dueCount 位客户要跟进, 点开看看'
      : '今天没有待办跟进, 有空可以回访老客户';

  /// 请求系统通知权限 (Android 13+ / iOS)。
  /// 返回 false = 用户拒绝或系统不允许 → 调用方**不要**把开关打开
  Future<bool> requestPermission();

  /// 每天 [hour]:[minute] 提醒「今天有 [dueCount] 位客户要跟进」
  /// dueCount 传 0 也照常提醒 (文案换成"没有待办") —— 关掉提醒请用 [cancel]
  Future<void> scheduleDaily({required int dueCount});

  /// 取消提醒 (用户在「我的」把开关关掉)
  Future<void> cancel();

  /// 点通知后要跳到哪 (由 app.dart 注入 router, 本层不认识路由)
  set onTap(void Function()? handler);
}

/// 平台工厂 (条件 import: web → 空实现, native → 真实现)
FollowUpReminder createFollowUpReminder() => platform.createFollowUpReminder();
