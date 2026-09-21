// ============================================
// 跟进提醒 — web (预览站) 空实现
// ============================================
// web 没有本地通知能力 (flutter_local_notifications 不支持 web, 且依赖 dart:io 会炸 web build)。
// 这里保持与真实现**同样的 API**, 让调用方不需要 if (kIsWeb) 到处判断:
//   requestPermission() → true (不拦用户开开关, 界面行为一致)
//   scheduleDaily()/cancel() → 什么都不做 (静默)
// 见 follow_up_reminder.dart 头部的平台差异说明。

import 'follow_up_reminder.dart';

class _WebFollowUpReminder implements FollowUpReminder {
  @override
  void Function()? onTap;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleDaily({required int dueCount}) async {}

  @override
  Future<void> cancel() async {}
}

FollowUpReminder createFollowUpReminder() => _WebFollowUpReminder();
