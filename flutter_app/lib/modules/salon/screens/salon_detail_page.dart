// ============================================
// 沙龙详情页 (v0.1.5 Phase 7)
// ============================================
// 按角色显示不同区块:
//   受邀者: 我的回复 + 我带来的人 (登记二级客人)
//   主理人/会务: AppBar 管理入口 + 发公告
// 全部区块都做了空值隐藏 (后端没填就不显示空行).
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/http/api_client.dart';
import '../../../core/models/salon.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/salon_providers.dart';
import '../widgets/salon_rsvp_sheet.dart';
import '../widgets/salon_section.dart';
import '../widgets/salon_status_chip.dart';

class SalonDetailPage extends ConsumerStatefulWidget {
  final String salonId;

  const SalonDetailPage({super.key, required this.salonId});

  @override
  ConsumerState<SalonDetailPage> createState() => _SalonDetailPageState();
}

class _SalonDetailPageState extends ConsumerState<SalonDetailPage> {
  final TextEditingController _activityCtrl = TextEditingController();
  bool _sendingActivity = false;

  @override
  void dispose() {
    _activityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSalon = ref.watch(salonDetailProvider(widget.salonId));
    final salon = asyncSalon.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('沙龙详情'),
        actions: [
          if (salon != null && salon.viewer.canManage)
            IconButton(
              icon: const Icon(Icons.tune, size: 28),
              tooltip: '管理',
              onPressed: () => context.push('/salons/${widget.salonId}/manage'),
            ),
          if (salon != null && salon.viewer.isOrganizer)
            IconButton(
              icon: const Icon(Icons.edit, size: 28),
              tooltip: '编辑',
              onPressed: () => context.push('/salons/${widget.salonId}/edit'),
            ),
        ],
      ),
      body: asyncSalon.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(salonDetailProvider(widget.salonId)),
        ),
        data: (salon) => _buildBody(salon),
      ),
    );
  }

  // ==========================================
  // 主体
  // ==========================================

  Widget _buildBody(Salon salon) {
    final invitations = ref
            .watch(salonInvitationsProvider(widget.salonId))
            .valueOrNull ??
        const <SalonInvitation>[];
    final activities =
        ref.watch(salonActivitiesProvider(widget.salonId)).valueOrNull ??
            const <SalonActivity>[];
    final attachments =
        ref.watch(salonAttachmentsProvider(widget.salonId)).valueOrNull ??
            const <SalonAttachment>[];
    final isInvitee = salon.viewer.myInvitationId != null;
    final staffs = invitations.where((inv) => inv.isStaff).toList();

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _header(salon),
          const SizedBox(height: 12),
          if (salon.status == SalonStatus.cancelled) ...[
            _cancelledBanner(activities),
            const SizedBox(height: 12),
          ],
          if (isInvitee) ...[
            _myReplyCard(salon),
            const SizedBox(height: 12),
          ],
          _timePlaceSection(salon, invitations),
          const SizedBox(height: 12),
          if (salon.agenda.isNotEmpty) ...[
            _agendaSection(salon),
            const SizedBox(height: 12),
          ],
          if (_hasTransport(salon)) ...[
            _transportSection(salon),
            const SizedBox(height: 12),
          ],
          if (_hasCatering(salon)) ...[
            _cateringSection(salon),
            const SizedBox(height: 12),
          ],
          if (_hasLodging(salon)) ...[
            _lodgingSection(salon),
            const SizedBox(height: 12),
          ],
          _dressFeeSection(salon),
          const SizedBox(height: 12),
          if (staffs.isNotEmpty) ...[
            _staffSection(staffs),
            const SizedBox(height: 12),
          ],
          if (invitations.isNotEmpty) ...[
            _inviteeSection(invitations),
            const SizedBox(height: 12),
          ],
          if (isInvitee) ...[
            _myGuestsSection(),
            const SizedBox(height: 12),
          ],
          if (attachments.isNotEmpty) ...[
            _attachmentsSection(attachments),
            const SizedBox(height: 12),
          ],
          _activitiesSection(salon, activities),
        ],
      ),
    );
  }

  // ==========================================
  // 1) 头部
  // ==========================================

  Widget _header(Salon salon) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              salon.title,
              style: const TextStyle(
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (salon.subtitle != null && salon.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                salon.subtitle!,
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SalonStatusChip(status: salon.status),
                SalonRoleChip(label: salon.viewer.roleLabel),
                if (salon.viewer.myInvitationId != null &&
                    salon.viewer.myStatus != null)
                  SalonInviteStatusChip(status: salon.viewer.myStatus!),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 22, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '主理人: ${salon.organizerName ?? '—'}',
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                  ),
                ),
              ],
            ),
            if (salon.description != null && salon.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                salon.description!,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 2) 我的回复 (仅受邀者)
  // ==========================================

  Widget _cancelledBanner(List<SalonActivity> activities) {
    // 找最近一条 salon_cancelled 系统动态, 拿 metadata.reason
    String? reason;
    for (final a in activities) {
      if (a.type == 'system' &&
          a.metadata != null &&
          a.metadata!['event'] == 'salon_cancelled') {
        reason = a.metadata!['reason'] as String? ?? a.content;
        break;
      }
    }
    if (reason == null || reason.isEmpty) {
      reason = '主理人取消了这场沙龙';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cancel_outlined,
              size: 24, color: AppTheme.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '沙龙已取消',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: AppTheme.fontMd,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _myReplyCard(Salon salon) {
    final viewer = salon.viewer;
    final status = viewer.myStatus ?? SalonInvitationStatus.pending;
    final guestCount = viewer.myExpectedGuestCount ?? 0;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.reply, size: 26, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '我的回复',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '我的回复: ${status.label}',
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (guestCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '预计带约 $guestCount 人',
                style: const TextStyle(fontSize: AppTheme.fontMd),
              ),
            ],
            if (viewer.myQuotaValue != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined,
                        size: 22, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '主理人请您邀约 ${viewer.myQuotaValue} 人到场',
                        style: const TextStyle(
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8A5A1F),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            BigButton(
              label: '修改我的回复',
              icon: Icons.edit_note,
              onPressed: () => showSalonRsvpSheet(context, ref, salon),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 3) 时间地点
  // ==========================================

  Widget _timePlaceSection(Salon salon, List<SalonInvitation> invitations) {
    // 会务电话: 取第一个填了手机号的会务 (受邀者之间互相看不到号码)
    SalonInvitation? staffWithPhone;
    for (final inv in invitations) {
      if (inv.isStaff &&
          inv.inviteePhone != null &&
          inv.inviteePhone!.isNotEmpty) {
        staffWithPhone = inv;
        break;
      }
    }

    final endText = salon.endAt == null
        ? null
        : (salon.startAt != null && salonSameDay(salon.startAt!, salon.endAt!)
            ? formatSalonHm(salon.endAt!)
            : formatSalonFullDateTime(salon.endAt));

    return SalonSection(
      title: '时间地点',
      icon: Icons.schedule,
      child: Column(
        children: [
          SalonInfoRow(
            icon: Icons.play_arrow_outlined,
            label: '开始',
            value: salon.startAt == null
                ? null
                : formatSalonFullDateTime(salon.startAt),
          ),
          SalonInfoRow(
            icon: Icons.stop_outlined,
            label: '结束',
            value: endText,
          ),
          SalonInfoRow(
            icon: Icons.hourglass_bottom,
            label: '报名截止',
            value: salon.registrationDeadlineAt == null
                ? null
                : formatSalonFullDateTime(salon.registrationDeadlineAt),
          ),
          SalonInfoRow(
            icon: Icons.place_outlined,
            label: '地点',
            value: salon.addressLine.isEmpty ? null : salon.addressLine,
          ),
          if (staffWithPhone != null)
            SalonInfoRow(
              icon: Icons.phone_in_talk_outlined,
              label: '会务电话',
              value: '${staffWithPhone.inviteeName} ${staffWithPhone.inviteePhone}',
              onTap: () => _callPhone(staffWithPhone!.inviteePhone!),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // 4) 日程
  // ==========================================

  Widget _agendaSection(Salon salon) {
    return SalonSection(
      title: '日程',
      icon: Icons.list_alt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < salon.agenda.length; i++)
            _agendaRow(salon.agenda[i], showDivider: i > 0),
        ],
      ),
    );
  }

  Widget _agendaRow(SalonAgendaItem item, {required bool showDivider}) {
    final start = item.start?.trim() ?? '';
    final end = item.end?.trim() ?? '';
    final timeText = start.isEmpty && end.isEmpty
        ? ''
        : (start.isEmpty
            ? end
            : (end.isEmpty ? start : '$start - $end'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider) const Divider(height: 21),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (timeText.isNotEmpty)
              SizedBox(
                width: 110,
                child: Text(
                  timeText,
                  style: const TextStyle(
                    fontSize: AppTheme.fontSm,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryDark,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.desc != null && item.desc!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.desc!,
                      style: const TextStyle(
                        fontSize: AppTheme.fontSm,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // 5) 交通指引
  // ==========================================

  Widget _transportSection(Salon salon) {
    return SalonSection(
      title: '交通指引',
      icon: Icons.directions_outlined,
      child: Column(
        children: [
          SalonInfoRow(
            icon: Icons.directions_bus_outlined,
            label: '公交/地铁',
            value: salon.transportPublic,
          ),
          SalonInfoRow(
            icon: Icons.directions_car_outlined,
            label: '自驾',
            value: salon.transportDriving,
          ),
          SalonInfoRow(
            icon: Icons.airport_shuttle_outlined,
            label: '接站',
            value: salon.transportPickup,
          ),
          SalonInfoRow(
            icon: Icons.local_parking_outlined,
            label: '停车',
            value: salon.parkingInfo,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 6) 餐饮安排
  // ==========================================

  Widget _cateringSection(Salon salon) {
    return SalonSection(
      title: '餐饮安排',
      icon: Icons.restaurant_outlined,
      child: Column(
        children: [
          SalonInfoRow(
            icon: Icons.restaurant,
            label: '用餐',
            value: salon.cateringMealType == null ? null : salon.cateringLabel,
          ),
          SalonInfoRow(
            icon: Icons.ramen_dining_outlined,
            label: '菜系',
            value: salon.cateringCuisine,
          ),
          SalonInfoRow(
            icon: Icons.schedule,
            label: '用餐时间',
            value: salon.cateringTime,
          ),
          SalonInfoRow(
            icon: Icons.no_food_outlined,
            label: '饮食要求',
            value: salon.cateringDietary,
          ),
          SalonInfoRow(
            icon: Icons.payments_outlined,
            label: '费用',
            value: salon.cateringPayer,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 7) 住宿安排
  // ==========================================

  Widget _lodgingSection(Salon salon) {
    final price = salon.lodgingPriceCents;
    return SalonSection(
      title: '住宿安排',
      icon: Icons.hotel_outlined,
      child: Column(
        children: [
          SalonInfoRow(
            icon: Icons.hotel,
            label: '酒店',
            value: salon.lodgingHotelName,
          ),
          SalonInfoRow(
            icon: Icons.meeting_room_outlined,
            label: '房型',
            value: salon.lodgingRoomType,
          ),
          SalonInfoRow(
            icon: Icons.payments_outlined,
            label: '价格',
            value: price == null ? null : '¥${(price / 100).toStringAsFixed(0)}',
          ),
          SalonInfoRow(
            icon: Icons.hourglass_bottom,
            label: '预定截止',
            value: salon.lodgingDeadlineAt == null
                ? null
                : formatSalonFullDateTime(salon.lodgingDeadlineAt),
          ),
          SalonInfoRow(
            icon: Icons.person_outline,
            label: '联系人',
            value: salon.lodgingContactName,
          ),
          SalonInfoRow(
            icon: Icons.phone_in_talk_outlined,
            label: '联系电话',
            value: salon.lodgingContactPhone,
            onTap: salon.lodgingContactPhone == null
                ? null
                : () => _callPhone(salon.lodgingContactPhone!),
          ),
          SalonInfoRow(
            icon: Icons.edit_note,
            label: '备注',
            value: salon.lodgingNote,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 8) 着装与费用
  // ==========================================

  Widget _dressFeeSection(Salon salon) {
    return SalonSection(
      title: '着装与费用',
      icon: Icons.checkroom_outlined,
      child: Column(
        children: [
          SalonInfoRow(
            icon: Icons.checkroom,
            label: '着装',
            value: salon.dressCode,
          ),
          SalonInfoRow(
            icon: Icons.payments_outlined,
            label: '费用',
            value: salon.feeLabel,
          ),
          SalonInfoRow(
            icon: Icons.info_outline,
            label: '说明',
            value: salon.feeNote,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 9) 会务人员
  // ==========================================

  Widget _staffSection(List<SalonInvitation> staffs) {
    return SalonSection(
      title: '会务人员',
      icon: Icons.support_agent,
      child: Column(
        children: [
          for (final staff in staffs) _staffRow(staff),
        ],
      ),
    );
  }

  Widget _staffRow(SalonInvitation staff) {
    final phone = staff.inviteePhone;
    final name = staff.inviteeName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.primaryLight.withOpacity(0.5),
            child: Text(
              name.isEmpty ? '?' : name[0],
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (staff.staffRole != null && staff.staffRole!.isNotEmpty)
                  Text(
                    staff.staffRole!,
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (phone != null && phone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone, size: 28, color: AppTheme.primary),
              tooltip: '拨打电话',
              onPressed: () => _callPhone(phone),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // 10) 受邀名单
  // ==========================================

  Widget _inviteeSection(List<SalonInvitation> invitations) {
    const maxShown = 20;
    final shown = invitations.take(maxShown).toList();

    return SalonSection(
      title: '受邀名单',
      icon: Icons.people_outline,
      trailing: Text(
        '共 ${invitations.length} 人',
        style: const TextStyle(
          fontSize: AppTheme.fontSm,
          color: AppTheme.textSecondary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final inv in shown) _inviteeRow(inv),
          if (invitations.length > maxShown) ...[
            const SizedBox(height: 8),
            Text(
              '仅显示前 $maxShown 位, 共 ${invitations.length} 人',
              style: const TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inviteeRow(SalonInvitation inv) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              inv.inviteeName,
              style: const TextStyle(fontSize: AppTheme.fontMd),
            ),
          ),
          if (inv.isStaff) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.franchiseeA.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '会务',
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.franchiseeA,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SalonInviteStatusChip(status: inv.status),
        ],
      ),
    );
  }

  // ==========================================
  // 11) 我带来的人 (仅受邀者)
  // ==========================================

  Widget _myGuestsSection() {
    final asyncGuests = ref.watch(
      salonGuestsProvider((salonId: widget.salonId, mine: true)),
    );

    return SalonSection(
      title: '我带来的人',
      icon: Icons.group_add_outlined,
      trailing: TextButton.icon(
        onPressed: _showAddGuestDialog,
        icon: const Icon(Icons.add, size: 22),
        label: const Text('添加', style: TextStyle(fontSize: AppTheme.fontSm)),
      ),
      child: asyncGuests.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ),
        error: (e, _) => const Text(
          '加载失败, 下拉刷新试试',
          style: TextStyle(
            fontSize: AppTheme.fontSm,
            color: AppTheme.textSecondary,
          ),
        ),
        data: (guests) {
          if (guests.isEmpty) {
            return const Text(
              '还没有登记, 点右上角「添加」登记您要带来的客人',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            );
          }
          return Column(
            children: [
              for (final guest in guests) _guestRow(guest),
            ],
          );
        },
      ),
    );
  }

  Widget _guestRow(SalonGuest guest) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guest.name,
                  style: const TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${guest.relationLabel} · ${guest.status.label}',
                  style: const TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 26, color: AppTheme.danger),
            tooltip: '删除',
            onPressed: () => _confirmDeleteGuest(guest),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 12) 沙龙资料
  // ==========================================

  Widget _attachmentsSection(List<SalonAttachment> attachments) {
    return SalonSection(
      title: '沙龙资料',
      icon: Icons.attach_file,
      child: Column(
        children: [
          for (final attachment in attachments)
            InkWell(
              onTap: () => _openAttachment(attachment),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      attachment.fileType == 'image'
                          ? Icons.image_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 26,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        attachment.name,
                        style: const TextStyle(fontSize: AppTheme.fontMd),
                      ),
                    ),
                    const Icon(Icons.open_in_new,
                        size: 20, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // 13) 动态
  // ==========================================

  Widget _activitiesSection(Salon salon, List<SalonActivity> activities) {
    // 倒序: 新动态在上
    final sorted = [...activities]..sort(
        (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0),
      );

    return SalonSection(
      title: '动态',
      icon: Icons.campaign_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sorted.isEmpty)
            const Text(
              '还没有动态, 发一条问问主理人吧',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            )
          else
            for (final activity in sorted) _activityRow(activity),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _activityCtrl,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: '说点什么...'),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _sendingActivity
                    ? null
                    : () => _sendActivity(type: 'comment'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(56, 56),
                  maximumSize: const Size(56, 56),
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _sendingActivity
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 26),
              ),
            ],
          ),
          if (salon.viewer.canManage) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _sendingActivity
                  ? null
                  : () => _sendActivity(type: 'announcement'),
              icon: const Icon(Icons.campaign, size: 24),
              label: const Text('发公告'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activityRow(SalonActivity activity) {
    final name = (activity.authorName == null || activity.authorName!.isEmpty)
        ? '参与者'
        : activity.authorName!;
    final timeText = formatSalonMonthDayTime(activity.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primaryLight.withOpacity(0.5),
            child: Text(
              name[0],
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppTheme.fontSm,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (activity.type != 'comment') ...[
                      const SizedBox(width: 6),
                      _activityTypeTag(activity.type),
                    ],
                    const Spacer(),
                    if (timeText.isNotEmpty)
                      Text(
                        timeText,
                        style: const TextStyle(
                          fontSize: AppTheme.fontXs,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  activity.content,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityTypeTag(String type) {
    final String label;
    final Color color;
    switch (type) {
      case 'announcement':
        label = '公告';
        color = AppTheme.accent;
        break;
      case 'question':
        label = '提问';
        color = AppTheme.franchiseeA;
        break;
      default:
        label = '系统';
        color = const Color(0xFF6B6B6B);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: AppTheme.fontXs,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  // ==========================================
  // 写操作
  // ==========================================

  Future<void> _refreshAll() {
    ref.invalidate(salonInvitationsProvider(widget.salonId));
    ref.invalidate(salonActivitiesProvider(widget.salonId));
    ref.invalidate(salonAttachmentsProvider(widget.salonId));
    ref.invalidate(salonGuestsProvider((salonId: widget.salonId, mine: true)));
    // 返回 detail 的 future → RefreshIndicator 等到数据回来才收圈
    return ref.refresh(salonDetailProvider(widget.salonId).future);
  }

  Future<void> _sendActivity({required String type}) async {
    final content = _activityCtrl.text.trim();
    if (content.isEmpty) {
      _toast(type == 'announcement' ? '请先输入公告内容' : '请先输入内容');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sendingActivity = true);
    try {
      await ref.read(salonServiceProvider).addActivity(widget.salonId, {
        'content': content,
        'type': type,
        if (type == 'announcement') 'visibility': 'all',
      });
      _activityCtrl.clear();
      invalidateSalon(ref, widget.salonId);
      if (!mounted) return;
      setState(() => _sendingActivity = false);
      messenger.showSnackBar(
        SnackBar(content: Text(type == 'announcement' ? '公告已发布' : '已发送')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendingActivity = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('发送失败, 请检查网络')),
      );
    }
  }

  Future<void> _showAddGuestDialog() async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AddGuestDialog(),
    );
    if (data == null || !mounted) return;

    final name = (data['name'] as String).trim();
    final phone = (data['phone'] as String).trim();
    if (name.isEmpty) {
      _toast('请填写姓名');
      return;
    }
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      _toast('请填写正确的手机号');
      return;
    }

    try {
      await ref.read(salonServiceProvider).addGuest(widget.salonId, {
        'name': name,
        'phone': phone,
        'relation': data['relation'],
      });
      invalidateSalon(ref, widget.salonId);
      _toast('已登记');
    } catch (_) {
      _toast('登记失败, 请检查手机号和网络');
    }
  }

  Future<void> _confirmDeleteGuest(SalonGuest guest) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定删除?'),
        content: Text('删除「${guest.name}」后不能恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('删除', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref.read(salonServiceProvider).deleteGuest(widget.salonId, guest.id);
      invalidateSalon(ref, widget.salonId);
      _toast('已删除');
    } catch (_) {
      _toast('删除失败, 请检查网络');
    }
  }

  // ==========================================
  // 小工具
  // ==========================================

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      _toast('无法拨号, 号码: $phone');
    }
  }

  Future<void> _openAttachment(SalonAttachment attachment) async {
    var url = attachment.fileUrl;
    if (!url.startsWith('http') && url.startsWith('/')) {
      url = '${ApiClient.baseOrigin}$url';
    }
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      _toast('打开失败, 请稍后再试');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _hasText(String? value) => value != null && value.isNotEmpty;

  bool _hasTransport(Salon salon) =>
      _hasText(salon.transportPublic) ||
      _hasText(salon.transportDriving) ||
      _hasText(salon.transportPickup) ||
      _hasText(salon.parkingInfo);

  bool _hasCatering(Salon salon) =>
      _hasText(salon.cateringMealType) ||
      _hasText(salon.cateringCuisine) ||
      _hasText(salon.cateringDietary) ||
      _hasText(salon.cateringTime) ||
      _hasText(salon.cateringPayer);

  bool _hasLodging(Salon salon) =>
      _hasText(salon.lodgingHotelName) ||
      _hasText(salon.lodgingRoomType) ||
      salon.lodgingPriceCents != null ||
      _hasText(salon.lodgingContactName) ||
      _hasText(salon.lodgingContactPhone) ||
      salon.lodgingDeadlineAt != null ||
      _hasText(salon.lodgingNote);
}

// ============================================
// 登记二级客人弹窗
// ============================================

class _AddGuestDialog extends StatefulWidget {
  const _AddGuestDialog();

  @override
  State<_AddGuestDialog> createState() => _AddGuestDialogState();
}

class _AddGuestDialogState extends State<_AddGuestDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  String _relation = 'client';

  static const Map<String, String> _relations = {
    'client': '客户',
    'friend': '朋友',
    'family': '家人',
    'colleague': '同事',
    'other': '其他',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('登记带来的客人'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(labelText: '姓名'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '手机号'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _relation,
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(labelText: '关系'),
              items: _relations.entries
                  .map((entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _relation = value ?? 'client'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({
              'name': _nameCtrl.text.trim(),
              'phone': _phoneCtrl.text.trim(),
              'relation': _relation,
            });
          },
          child: const Text('保存', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    );
  }
}
