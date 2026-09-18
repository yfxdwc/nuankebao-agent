// ============================================
// 沙龙二级客人管理页 (主理人 / 会务)
// v0.1.5 Phase 7 | 按「谁带来的」分组 + 状态 / 到场核销 / 删除
// 受邀者进这个页面会被后端限制为只看自己带来的客人
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/salon.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/salon_providers.dart';

class SalonGuestsPage extends ConsumerStatefulWidget {
  final String salonId;
  const SalonGuestsPage({super.key, required this.salonId});

  @override
  ConsumerState<SalonGuestsPage> createState() => _SalonGuestsPageState();
}

class _SalonGuestsPageState extends ConsumerState<SalonGuestsPage> {
  @override
  Widget build(BuildContext context) {
    final asyncGuests = ref.watch(
      salonGuestsProvider((salonId: widget.salonId, mine: false)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('带来的客人'), toolbarHeight: 64),
      body: asyncGuests.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(
            salonGuestsProvider((salonId: widget.salonId, mine: false)),
          ),
        ),
        data: (guests) {
          if (guests.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline,
              title: '还没有登记客人',
              hint: '受邀者登记后这里能看到',
            );
          }
          return _buildGroupedList(guests);
        },
      ),
    );
  }

  Widget _buildGroupedList(List<SalonGuest> guests) {
    final grouped = <String, List<SalonGuest>>{};
    for (final g in guests) {
      final name = (g.broughtByName == null || g.broughtByName!.trim().isEmpty)
          ? '未知'
          : g.broughtByName!.trim();
      grouped.putIfAbsent(name, () => <SalonGuest>[]).add(g);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              '${entry.key} 带来的 (${entry.value.length} 位)',
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          for (final guest in entry.value) _guestCard(guest),
        ],
      ],
    );
  }

  Widget _guestCard(SalonGuest g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: AppTheme.primaryLight.withOpacity(0.6),
          child: Text(
            g.name.isNotEmpty ? g.name.substring(0, 1) : '?',
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
                g.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (g.actualAttended)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _miniTag('已到场', AppTheme.primary),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _miniTag(g.relationLabel, const Color(0xFF6D6D6D)),
                  const SizedBox(width: 8),
                  _miniTag(g.status.label, _guestStatusColor(g.status)),
                ],
              ),
              if (g.phone != null && g.phone!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: InkWell(
                    onTap: () => _call(g.phone!),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.phone,
                          size: 20,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          g.phone!,
                          style: const TextStyle(
                            fontSize: AppTheme.fontMd,
                            color: AppTheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 28),
        onTap: () => _showGuestActions(g),
      ),
    );
  }

  Widget _miniTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
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

  Color _guestStatusColor(SalonGuestStatus status) {
    switch (status) {
      case SalonGuestStatus.accepted:
        return AppTheme.primary;
      case SalonGuestStatus.declined:
        return AppTheme.danger;
      case SalonGuestStatus.attended:
        return AppTheme.primaryDark;
      case SalonGuestStatus.absent:
        return AppTheme.danger;
      case SalonGuestStatus.cancelled:
        return const Color(0xFF8A8A8A);
      case SalonGuestStatus.pending:
        return AppTheme.accent;
    }
  }

  Future<void> _showGuestActions(SalonGuest g) async {
    final actions = <({String key, String label, IconData icon})>[
      (key: 'accepted', label: '会来', icon: Icons.check_circle_outline),
      (key: 'declined', label: '不来了', icon: Icons.cancel_outlined),
      (key: 'attended', label: '已到场', icon: Icons.how_to_reg),
      (key: 'absent', label: '未到场', icon: Icons.person_off_outlined),
      (key: 'remove', label: '删除这位客人', icon: Icons.delete_outline),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '${g.name} · ${g.status.label}',
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
                    size: 28,
                    color: a.key == 'remove'
                        ? AppTheme.danger
                        : AppTheme.textSecondary,
                  ),
                  title: Text(
                    a.label,
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      color: a.key == 'remove'
                          ? AppTheme.danger
                          : AppTheme.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(a.key),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == 'remove') {
      await _confirmDelete(g);
    } else {
      await _updateGuest(g, picked);
    }
  }

  Future<void> _updateGuest(SalonGuest g, String key) async {
    final payload = <String, Map<String, dynamic>>{
      'accepted': {'status': 'accepted', 'actualAttended': false},
      'declined': {'status': 'declined', 'actualAttended': false},
      'attended': {'status': 'attended', 'actualAttended': true},
      'absent': {'status': 'absent', 'actualAttended': false},
    }[key];
    if (payload == null) return;
    try {
      await ref
          .read(salonServiceProvider)
          .updateGuest(widget.salonId, g.id, payload);
      invalidateSalon(ref, widget.salonId);
      if (!mounted) return;
      _snack('已更新: ${SalonGuestStatus.fromApi(key).label}');
    } catch (e) {
      if (!mounted) return;
      _snack('操作失败, 请检查网络');
    }
  }

  Future<void> _confirmDelete(SalonGuest g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定删除?'),
        content: Text(
          '删除后「${g.name}」的登记信息就没有了',
          style: const TextStyle(fontSize: AppTheme.fontMd),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(salonServiceProvider).deleteGuest(widget.salonId, g.id);
      invalidateSalon(ref, widget.salonId);
      if (!mounted) return;
      _snack('已删除');
    } catch (e) {
      if (!mounted) return;
      _snack('删除失败, 请检查网络');
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack('拨号失败, 请手动拨打 $phone');
    } catch (e) {
      if (mounted) _snack('拨号失败, 请手动拨打 $phone');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
  }
}
