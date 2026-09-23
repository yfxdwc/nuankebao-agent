// ============================================
// 沙龙管理页 (主理人 / 会务)
// v0.1.5 Phase 7 | 3 个 tab: 报名情况 / 邀请名单 / 带约任务
// 含: 添加邀请 / RSVP 状态核销 / 移除邀请 / 分配带约任务 / 取消任务
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/salon.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/salon_providers.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.g.dart';
class SalonManagePage extends ConsumerStatefulWidget {
  final String salonId;
  const SalonManagePage({super.key, required this.salonId});

  @override
  ConsumerState<SalonManagePage> createState() => _SalonManagePageState();
}

class _SalonManagePageState extends ConsumerState<SalonManagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('沙龙管理'),
        toolbarHeight: 64,
        actions: [
          // 取消沙龙: 主理人 + 未取消 状态 才显示
          _CancelSalonAction(
            salonId: widget.salonId,
            busy: _cancelling,
            onBusy: (v) => setState(() => _cancelling = v),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: AppTheme.fontMd),
          tabs: const [
            Tab(text: '报名情况', height: AppSpace.s52),
            Tab(text: '邀请名单', height: AppSpace.s52),
            Tab(text: '带约任务', height: AppSpace.s52),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildSignupTab(),
          _buildInvitationsTab(),
          _buildQuotasTab(),
        ],
      ),
      floatingActionButton: _tab.index == 1
          ? FloatingActionButton.extended(
              onPressed: _showAddInvitation,
              icon: const Icon(Icons.person_add_alt, size: AppSize.iconXl),
              label: const Text('添加邀请',
                  style: TextStyle(fontSize: AppTheme.fontMd)),
            )
          : _tab.index == 2
              ? FloatingActionButton.extended(
                  onPressed: _showAssignQuota,
                  icon: const Icon(Icons.flag_outlined, size: AppSize.iconXl),
                  label: const Text('分配任务',
                      style: TextStyle(fontSize: AppTheme.fontMd)),
                )
              : null,
    );
  }

  // ============================================
  // Tab 1: 报名情况
  // ============================================
  Widget _buildSignupTab() {
    final asyncAgg = ref.watch(salonAggregatesProvider(widget.salonId));
    return asyncAgg.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(salonAggregatesProvider(widget.salonId)),
      ),
      data: (agg) => ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 32),
        children: [
          _statGrid(agg),
          const SizedBox(height: AppSpace.s20),
          const Text(
            '沙龙信息',
            style: TextStyle(
              fontSize: AppTheme.fontMd,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpace.s8),
          _salonInfoCard(),
        ],
      ),
    );
  }

  Widget _statGrid(SalonAggregates agg) {
    final stats = <({String label, String value})>[
      (label: '已接受', value: '${agg.accepted}'),
      (label: '待回复', value: '${agg.pending}'),
      (label: '已婉拒', value: '${agg.declined}'),
      (label: '已到场 (实到)', value: '${agg.attended}'),
      (label: '受邀总数', value: '${agg.invitedTotal}'),
      (label: '会务人数', value: '${agg.staffCount}'),
      (label: '预计带约总人数', value: '${agg.expectedGuests}'),
      (label: '已登记客人', value: '${agg.guestRegistered}'),
      (
        label: '名额剩余',
        value:
            agg.capacityRemaining == null ? '不限' : '${agg.capacityRemaining}',
      ),
      (label: '带约任务人数', value: '${agg.quotaAssignees}'),
      (label: '带约任务总额', value: '${agg.quotaTotal}'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children:
          stats.map((s) => _statCard(label: s.label, value: s.value)).toList(),
    );
  }

  Widget _statCard({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.s12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.surfaceSunken),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTheme.fontXxl,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: AppSpace.s4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: AppTheme.fontSm,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _salonInfoCard() {
    final asyncSalon = ref.watch(salonDetailProvider(widget.salonId));
    return asyncSalon.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpace.s24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: ListTile(
          title: const Text('沙龙信息暂时加载不出来',
              style: TextStyle(fontSize: AppTheme.fontMd)),
          trailing: TextButton(
            onPressed: () =>
                ref.invalidate(salonDetailProvider(widget.salonId)),
            child: const Text('重试'),
          ),
        ),
      ),
      data: (s) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.title,
                style: const TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              _infoRow('状态', s.status.label),
              _infoRow('时间', _fmtRange(s.startAt, s.endAt)),
              _infoRow('地点', s.addressLine.isEmpty ? '待定' : s.addressLine),
              _infoRow('费用', s.feeLabel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppSpace.s64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // Tab 2: 邀请名单
  // ============================================
  Widget _buildInvitationsTab() {
    final asyncList = ref.watch(salonInvitationsProvider(widget.salonId));
    return asyncList.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(salonInvitationsProvider(widget.salonId)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.group_add_outlined,
            title: '还没有邀请人',
            hint: '点右下角「添加邀请」把客人请进来',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 120),
          itemCount: items.length,
          itemBuilder: (context, i) => _invitationTile(items[i]),
        );
      },
    );
  }

  Widget _invitationTile(SalonInvitation inv) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: AppTheme.primaryLight.withOpacity(0.6),
          child: Text(
            inv.inviteeName.isNotEmpty ? inv.inviteeName.substring(0, 1) : '?',
            style: const TextStyle(
              fontSize: AppTheme.fontMd,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                inv.inviteeName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (inv.roleInSalon == 'organizer')
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.s8),
                child: _miniTag('主理人', AppTheme.accent),
              )
            else if (inv.isStaff)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.s8),
                child: _miniTag(
                  inv.staffRole != null && inv.staffRole!.isNotEmpty
                      ? '会务·${inv.staffRole}'
                      : '会务',
                  AppTheme.primary,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (inv.inviteePhone != null && inv.inviteePhone!.isNotEmpty)
                Text(
                  inv.inviteePhone!,
                  style: const TextStyle(fontSize: AppTheme.fontSm),
                ),
              Text(
                '带约 ${inv.expectedGuestCount} 人',
                style: const TextStyle(fontSize: AppTheme.fontSm),
              ),
            ],
          ),
        ),
        trailing: _invitationStatusChip(inv.status),
        onTap: () => _showInvitationActions(inv),
      ),
    );
  }

  Widget _miniTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTheme.fontXs,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _invitationStatusChip(SalonInvitationStatus status) {
    final color = _invitationStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.r10),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: AppTheme.fontSm,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _invitationStatusColor(SalonInvitationStatus status) {
    switch (status) {
      case SalonInvitationStatus.accepted:
        return AppTheme.primary;
      case SalonInvitationStatus.tentative:
        return AppTheme.accent;
      case SalonInvitationStatus.declined:
        return AppTheme.danger;
      case SalonInvitationStatus.waitlist:
        return AppColors.salonWaitlist;
      case SalonInvitationStatus.attended:
        return AppTheme.primaryDark;
      case SalonInvitationStatus.absent:
        return AppTheme.danger;
      case SalonInvitationStatus.cancelled:
        return AppColors.textDisabled;
      case SalonInvitationStatus.pending:
        return AppColors.textDisabled;
    }
  }

  Future<void> _showInvitationActions(SalonInvitation inv) async {
    final actions = <({String value, String label, IconData icon})>[
      (value: 'accepted', label: '标记已接受', icon: Icons.check_circle_outline),
      (value: 'tentative', label: '标记待定', icon: Icons.help_outline),
      (value: 'declined', label: '标记婉拒', icon: Icons.cancel_outlined),
      (value: 'waitlist', label: '标记候补', icon: Icons.hourglass_empty),
      (value: 'attended', label: '标记已到场', icon: Icons.how_to_reg),
      (value: 'absent', label: '标记未到场', icon: Icons.person_off_outlined),
      (value: 'remove', label: '移除邀请', icon: Icons.delete_outline),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.s20, 16, 20, 8),
                child: Text(
                  '${inv.inviteeName} · ${inv.status.label}',
                  style: const TextStyle(
                    fontSize: AppTheme.fontLg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              for (final a in actions)
                ListTile(
                  leading: Icon(
                    a.icon,
                    size: AppSize.iconXl,
                    color: a.value == 'remove'
                        ? AppTheme.danger
                        : AppTheme.textSecondary,
                  ),
                  title: Text(
                    a.label,
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      color: a.value == 'remove'
                          ? AppTheme.danger
                          : AppTheme.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(a.value),
                ),
              const SizedBox(height: AppSpace.s8),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == 'remove') {
      await _confirmRemoveInvitation(inv);
    } else {
      await _updateInvitationStatus(inv, picked);
    }
  }

  Future<void> _updateInvitationStatus(
    SalonInvitation inv,
    String status,
  ) async {
    try {
      await ref
          .read(salonServiceProvider)
          .updateInvitation(widget.salonId, inv.id, {'status': status});
      invalidateSalon(ref, widget.salonId);
      if (!mounted) return;
      _snack('已更新: ${SalonInvitationStatus.fromApi(status).label}');
    } catch (e) {
      if (!mounted) return;
      _snack('操作失败, 请检查网络');
    }
  }

  Future<void> _confirmRemoveInvitation(SalonInvitation inv) async {
    final ok = await _confirm(
      title: '确定移除邀请?',
      content: '移除后「${inv.inviteeName}」将看不到这个沙龙',
      confirmLabel: '移除',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(salonServiceProvider)
          .removeInvitation(widget.salonId, inv.id);
      invalidateSalon(ref, widget.salonId);
      if (!mounted) return;
      _snack('已移除');
    } catch (e) {
      if (!mounted) return;
      _snack('移除失败, 请检查网络');
    }
  }

  Future<void> _showAddInvitation() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddInvitationDialog(salonId: widget.salonId),
    );
    if (ok == true && mounted) _snack('已添加邀请');
  }

  // ============================================
  // Tab 3: 带约任务
  // ============================================
  Widget _buildQuotasTab() {
    final asyncList = ref.watch(salonQuotasProvider(widget.salonId));
    return asyncList.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(salonQuotasProvider(widget.salonId)),
      ),
      data: (quotas) {
        if (quotas.isEmpty) {
          return const EmptyState(
            icon: Icons.flag_outlined,
            title: '还没有带约任务',
            hint: '点右下角「分配任务」给受邀者定个带约目标',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 120),
          itemCount: quotas.length,
          itemBuilder: (context, i) => _quotaCard(quotas[i]),
        );
      },
    );
  }

  Widget _quotaCard(SalonQuota q) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    q.assignedToName ?? '未知',
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _miniTag(
                  q.isFulfilled ? '已达标' : '进行中',
                  q.isFulfilled ? AppTheme.primary : AppTheme.accent,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            Text(
              '带约 ${q.quotaValue} 人',
              style: const TextStyle(
                fontSize: AppTheme.fontLg,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryDark,
              ),
            ),
            const SizedBox(height: AppSpace.s10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.r8),
              child: LinearProgressIndicator(
                value: q.ratio,
                minHeight: 12,
                backgroundColor: AppColors.surfaceSunken,
              ),
            ),
            const SizedBox(height: AppSpace.s8),
            Text(
              '已完成 ${q.progress} / ${q.quotaValue} · 已登记 ${q.guestCount} · 自报 ${q.expectedGuestCount} 人',
              style: const TextStyle(fontSize: AppTheme.fontSm),
            ),
            const SizedBox(height: AppSpace.s4),
            Text(
              q.deadlineAt == null
                  ? '截止时间: 未设置'
                  : '截止时间: ${_fmtDateTime(q.deadlineAt!)}',
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            ),
            if (q.note != null && q.note!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s4),
              Text(
                '备注: ${q.note}',
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _confirmCancelQuota(q),
                icon: const Icon(
                  Icons.close,
                  size: AppSize.iconLg,
                  color: AppTheme.danger,
                ),
                label: const Text(
                  '取消任务',
                  style: TextStyle(fontSize: AppTheme.fontMd),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancelQuota(SalonQuota q) async {
    final ok = await _confirm(
      title: '确定取消任务?',
      content: '将取消「${q.assignedToName ?? '这位受邀者'}」的带约任务',
      confirmLabel: '取消任务',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(salonServiceProvider).cancelQuota(widget.salonId, q.id);
      invalidateSalon(ref, widget.salonId);
      if (!mounted) return;
      _snack('已取消任务');
    } catch (e) {
      if (!mounted) return;
      _snack('取消失败, 请检查网络');
    }
  }

  Future<void> _showAssignQuota() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AssignQuotaDialog(salonId: widget.salonId),
    );
    if (ok == true && mounted) _snack('已分配任务');
  }

  // ============================================
  // 小工具
  // ============================================
  Future<bool> _confirm({
    required String title,
    required String content,
    String confirmLabel = '确定',
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
          content,
          style: const TextStyle(fontSize: AppTheme.fontMd),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: danger
                ? ElevatedButton.styleFrom(backgroundColor: AppTheme.danger)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  String _fmtDateTime(DateTime dt) {
    final now = DateTime.now();
    final year = dt.year == now.year ? '' : '${dt.year}年';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$year${dt.month}月${dt.day}日 $hh:$mm';
  }

  String _fmtRange(DateTime? start, DateTime? end) {
    if (start == null) return '待定';
    if (end == null) return _fmtDateTime(start);
    return '${_fmtDateTime(start)} - ${_fmtDateTime(end)}';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
  }
}

// ============================================
// 添加邀请弹窗
// ============================================
class _AddInvitationDialog extends ConsumerStatefulWidget {
  final String salonId;
  const _AddInvitationDialog({required this.salonId});

  @override
  ConsumerState<_AddInvitationDialog> createState() =>
      _AddInvitationDialogState();
}

class _AddInvitationDialogState extends ConsumerState<_AddInvitationDialog> {
  static final RegExp _phoneRe = RegExp(r'^1[3-9]\d{9}$');

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _staffRoleCtrl = TextEditingController();
  final _guestCountCtrl = TextEditingController();
  String _role = 'attendee';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _staffRoleCtrl.dispose();
    _guestCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请填写姓名');
      return;
    }
    if (!_phoneRe.hasMatch(phone)) {
      _snack('手机号格式不对, 请检查');
      return;
    }
    int? guestCount;
    final guestText = _guestCountCtrl.text.trim();
    if (guestText.isNotEmpty) {
      guestCount = int.tryParse(guestText);
      if (guestCount == null || guestCount < 0) {
        _snack('预计带约人数请填数字');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref.read(salonServiceProvider).addInvitation(widget.salonId, {
        'name': name,
        'phone': phone,
        'roleInSalon': _role,
        if (_role == 'staff' && _staffRoleCtrl.text.trim().isNotEmpty)
          'staffRole': _staffRoleCtrl.text.trim(),
        if (guestCount != null) 'expectedGuestCount': guestCount,
      });
      invalidateSalon(ref, widget.salonId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('添加失败, 请检查网络或手机号是否重复');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加邀请'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(labelText: '姓名 *'),
            ),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(labelText: '手机号 *'),
            ),
            const SizedBox(height: AppSpace.s12),
            DropdownButtonFormField<String>(
              value: _role,
              isExpanded: true,
              itemHeight: 56,
              decoration: const InputDecoration(labelText: '身份'),
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textPrimary,
              ),
              items: const [
                DropdownMenuItem(value: 'attendee', child: Text('受邀者')),
                DropdownMenuItem(value: 'staff', child: Text('会务')),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _role = v ?? 'attendee'),
            ),
            if (_role == 'staff') ...[
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: _staffRoleCtrl,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  labelText: '会务角色',
                  hintText: '如: 主持 / 讲师',
                ),
              ),
            ],
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: _guestCountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(
                labelText: '预计带约人数',
                hintText: '不填 = 0 人',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? '提交中...' : '确定'),
        ),
      ],
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
  }
}

// ============================================
// 分配带约任务弹窗
// ============================================
class _AssignQuotaDialog extends ConsumerStatefulWidget {
  final String salonId;
  const _AssignQuotaDialog({required this.salonId});

  @override
  ConsumerState<_AssignQuotaDialog> createState() => _AssignQuotaDialogState();
}

class _AssignQuotaDialogState extends ConsumerState<_AssignQuotaDialog> {
  final _quotaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selectedUserId;
  bool _saving = false;

  @override
  void dispose() {
    _quotaCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(List<SalonInvitation> candidates) async {
    final uid = _selectedUserId ?? candidates.first.inviteeUserId;
    if (uid == null) return;
    final n = int.tryParse(_quotaCtrl.text.trim());
    if (n == null || n < 1) {
      _snack('请填写要求带约人数 (至少 1 人)');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(salonServiceProvider).upsertQuota(
            widget.salonId,
            assignedToUserId: uid,
            quotaValue: n,
            note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          );
      invalidateSalon(ref, widget.salonId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('分配失败, 请检查网络');
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncInvites = ref.watch(salonInvitationsProvider(widget.salonId));
    return asyncInvites.when(
      loading: () => const AlertDialog(
        title: Text('分配任务'),
        content: SizedBox(
          height: AppSpace.s100,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => AlertDialog(
        title: const Text('分配任务'),
        content: const Text(
          '受邀者名单加载失败, 请稍后再试',
          style: TextStyle(fontSize: AppTheme.fontMd),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('关闭'),
          ),
        ],
      ),
      data: (items) {
        final candidates = items
            .where(
                (i) => i.roleInSalon == 'attendee' && i.inviteeUserId != null)
            .toList();
        if (candidates.isEmpty) {
          return AlertDialog(
            title: const Text('分配任务'),
            content: const Text(
              '还没有 app 用户受邀者\n\n只有装了「暖客宝」app 的受邀者才能领带约任务, 先去「邀请名单」添加一个吧',
              style: TextStyle(fontSize: AppTheme.fontMd),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('知道了'),
              ),
            ],
          );
        }
        final selected = _selectedUserId ?? candidates.first.inviteeUserId!;
        return AlertDialog(
          title: const Text('分配带约任务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: selected,
                  isExpanded: true,
                  itemHeight: 56,
                  decoration: const InputDecoration(labelText: '指派给'),
                  style: const TextStyle(
                    fontSize: AppTheme.fontMd,
                    color: AppTheme.textPrimary,
                  ),
                  items: candidates
                      .map((c) => DropdownMenuItem<String>(
                            value: c.inviteeUserId,
                            child: Text(
                              c.inviteeName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _selectedUserId = v),
                ),
                const SizedBox(height: AppSpace.s12),
                TextField(
                  controller: _quotaCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                  decoration: const InputDecoration(
                    labelText: '要求带约人数 *',
                    hintText: '如: 3',
                  ),
                ),
                const SizedBox(height: AppSpace.s12),
                TextField(
                  controller: _noteCtrl,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                  decoration: const InputDecoration(
                    labelText: '备注 (可选)',
                    hintText: '如: 带 3 位老客户',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: _saving ? null : () => _submit(candidates),
              child: Text(_saving ? '提交中...' : '确定'),
            ),
          ],
        );
      },
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
  }
}

// ============================================
// 取消沙龙 (AppBar action + 详细说明弹层)
// ============================================
// 单独抽出来避免污染主 widget: 自己 watch salon 详情判断可见性 / 权限
// ============================================

class _CancelSalonAction extends ConsumerWidget {
  final String salonId;
  final bool busy;
  final ValueChanged<bool> onBusy;
  const _CancelSalonAction({
    required this.salonId,
    required this.busy,
    required this.onBusy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSalon = ref.watch(salonDetailProvider(salonId));
    final salon = asyncSalon.valueOrNull;
    // 已取消的不显示; 非主理人不显示
    final visible = salon != null &&
        salon.viewer.isOrganizer &&
        salon.status != SalonStatus.cancelled;
    if (!visible) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.cancel_outlined, size: AppSize.iconXl, color: AppTheme.danger),
      tooltip: '取消沙龙',
      onPressed: busy
          ? null
          : () => _showCancelDialog(context, ref),
    );
  }

  Future<void> _showCancelDialog(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('取消沙龙', style: TextStyle(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '取消后受邀者会在沙龙详情页看到这条说明, 请把原因写清楚。',
                style: TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: reasonCtrl,
                maxLines: 4,
                minLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '取消说明 (10-500 字)',
                  hintText: '如: 场地临时维修, 改期到下周五同一时间',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('再想想'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () {
                if (reasonCtrl.text.trim().length < 10) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('至少写 10 个字, 让受邀者明白')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('确认取消'),
            ),
          ],
        );
      },
    );

    if (result != true || !context.mounted) return;
    onBusy(true);
    try {
      final svc = ref.read(salonServiceProvider);
      await svc.cancel(salonId, reason: reasonCtrl.text.trim());
      ref.invalidate(salonDetailProvider(salonId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('沙龙已取消, 受邀者会在详情页看到说明')),
        );
        // 回到详情页 (看 banner 效果)
        context.go('/salons/$salonId');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消失败: $e')),
        );
      }
    } finally {
      onBusy(false);
    }
  }
}
