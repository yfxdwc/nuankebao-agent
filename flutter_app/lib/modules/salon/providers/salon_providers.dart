// ============================================
// 沙龙模块 providers (v0.1.5 Phase 7)
// ============================================
// 约定:
//   - 写操作 (RSVP / 加邀请 / 加客人 / 发动态) 调 service 后 `ref.invalidate`
//     对应 provider 刷新 (本项目风格, 不用 stateNotifier)
//   - 列表按 role 缓存 (我主理的 / 我受邀的 分开拉)
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/salon.dart';
import '../../../core/providers/service_providers.dart';

/// 沙龙列表: [role] = 'organizing' (我主理的) / 'invited' (我受邀的) / 'all'
/// includeFinished 固定 true —— 「已结束」由 UI 自己过滤展示 (历史要能回看)
final salonsProvider = FutureProvider.family<List<Salon>, String>(
  (ref, role) async {
    return ref.watch(salonServiceProvider).list(role: role);
  },
);

/// 沙龙详情 (含我的身份 / 统计)
final salonDetailProvider = FutureProvider.family<Salon, String>(
  (ref, salonId) async {
    return ref.watch(salonServiceProvider).getById(salonId);
  },
);

/// 邀请名单 (主理人/会务: 全部; 受邀者: 按可见性设置)
final salonInvitationsProvider =
    FutureProvider.family<List<SalonInvitation>, String>(
  (ref, salonId) async {
    return ref.watch(salonServiceProvider).invitations(salonId);
  },
);

/// 带约任务 (主理人/会务: 全部; 受邀者: 只有自己的)
final salonQuotasProvider = FutureProvider.family<List<SalonQuota>, String>(
  (ref, salonId) async {
    return ref.watch(salonServiceProvider).quotas(salonId);
  },
);

/// 二级客人 (mine=true 只看自己带来的)
final salonGuestsProvider =
    FutureProvider.family<List<SalonGuest>, ({String salonId, bool mine})>(
  (ref, arg) async {
    return ref.watch(salonServiceProvider).guests(arg.salonId, mine: arg.mine);
  },
);

/// 动态流 (公告 / 留言 / 系统消息)
final salonActivitiesProvider =
    FutureProvider.family<List<SalonActivity>, String>(
  (ref, salonId) async {
    return ref.watch(salonServiceProvider).activities(salonId);
  },
);

/// 沙龙资料 (附件)
final salonAttachmentsProvider =
    FutureProvider.family<List<SalonAttachment>, String>(
  (ref, salonId) async {
    return ref.watch(salonServiceProvider).attachments(salonId);
  },
);

/// 聚合统计 (主理人/会务视角; 受邀者会 404 → UI 不拉)
final salonAggregatesProvider =
    FutureProvider.family<SalonAggregates, String>(
  (ref, salonId) async {
    return ref.watch(salonServiceProvider).aggregates(salonId);
  },
);

/// 刷新一个沙龙相关的所有 provider (详情/名单/任务/客人/动态/聚合)
/// 用法: 写操作成功后 `invalidateSalon(ref, salonId)`
void invalidateSalon(WidgetRef ref, String salonId) {
  ref.invalidate(salonDetailProvider(salonId));
  ref.invalidate(salonInvitationsProvider(salonId));
  ref.invalidate(salonQuotasProvider(salonId));
  ref.invalidate(salonGuestsProvider((salonId: salonId, mine: false)));
  ref.invalidate(salonGuestsProvider((salonId: salonId, mine: true)));
  ref.invalidate(salonActivitiesProvider(salonId));
  ref.invalidate(salonAttachmentsProvider(salonId));
  ref.invalidate(salonAggregatesProvider(salonId));
  // 列表 (两侧 tab) 的统计也会变
  ref.invalidate(salonsProvider('invited'));
  ref.invalidate(salonsProvider('organizing'));
  ref.invalidate(salonsProvider('all'));
}
