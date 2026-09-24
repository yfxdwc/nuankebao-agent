// ============================================
// 沙龙 RSVP 弹层 (v0.1.5 Phase 7)
// ============================================
// 受邀者回复: 接受 / 待定 / 婉拒 + 预计带约人数 + 留言.
// 用法: showSalonRsvpSheet(context, ref, salon)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/salon.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';

import '../providers/salon_providers.dart';

import '../../../core/theme/tokens.g.dart';
/// 弹层只允许 3 个选项 → API 字符串 (model 里只有 SalonStatus.apiValue)
String _apiValueOf(SalonInvitationStatus status) {
  switch (status) {
    case SalonInvitationStatus.accepted:
      return 'accepted';
    case SalonInvitationStatus.declined:
      return 'declined';
    case SalonInvitationStatus.tentative:
      return 'tentative';
    case SalonInvitationStatus.pending:
    case SalonInvitationStatus.waitlist:
    case SalonInvitationStatus.attended:
    case SalonInvitationStatus.absent:
    case SalonInvitationStatus.cancelled:
      // 弹层选不中这些状态; 兜底给 tentative (最温和)
      return 'tentative';
  }
}

/// 弹出 RSVP 弹层 (圆角顶部 + 防键盘遮挡)
Future<void> showSalonRsvpSheet(
  BuildContext context,
  WidgetRef ref,
  Salon salon,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
    ),
    builder: (_) => _SalonRsvpSheet(ref: ref, salon: salon),
  );
}

class _SalonRsvpSheet extends StatefulWidget {
  final WidgetRef ref;
  final Salon salon;

  const _SalonRsvpSheet({required this.ref, required this.salon});

  @override
  State<_SalonRsvpSheet> createState() => _SalonRsvpSheetState();
}

class _SalonRsvpSheetState extends State<_SalonRsvpSheet> {
  SalonInvitationStatus? _status;
  int _guestCount = 0;
  bool _saving = false;
  final TextEditingController _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 初始值: 我上次的回复 (pending / null → 不预选, 必须明确选一个)
    final my = widget.salon.viewer.myStatus;
    _status = (my == SalonInvitationStatus.accepted ||
            my == SalonInvitationStatus.tentative ||
            my == SalonInvitationStatus.declined)
        ? my
        : null;
    _guestCount = widget.salon.viewer.myExpectedGuestCount ?? 0;
    if (_guestCount > 20) _guestCount = 20;
    if (_guestCount < 0) _guestCount = 0;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _showGuestCount =>
      _status == SalonInvitationStatus.accepted ||
      _status == SalonInvitationStatus.tentative;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘顶起来时把内容整体上推
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.s20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部把手
              Center(
                child: Container(
                  width: AppSpace.s48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadius.r3),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              const Text(
                '回复邀请',
                style: TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.s4),
              Text(
                widget.salon.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.s20),
              const Text(
                '您能来吗?',
                style: TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              Row(
                children: [
                  Expanded(
                    child: _RsvpChoice(
                      label: '接受邀请',
                      icon: Icons.check_circle_outline,
                      color: AppTheme.primary,
                      selected: _status == SalonInvitationStatus.accepted,
                      onTap: () => setState(
                          () => _status = SalonInvitationStatus.accepted),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Expanded(
                    child: _RsvpChoice(
                      label: '待定',
                      icon: Icons.help_outline,
                      color: AppTheme.accent,
                      selected: _status == SalonInvitationStatus.tentative,
                      onTap: () => setState(
                          () => _status = SalonInvitationStatus.tentative),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Expanded(
                    child: _RsvpChoice(
                      label: '婉拒',
                      icon: Icons.cancel_outlined,
                      color: AppTheme.danger,
                      selected: _status == SalonInvitationStatus.declined,
                      onTap: () => setState(
                          () => _status = SalonInvitationStatus.declined),
                    ),
                  ),
                ],
              ),
              if (_showGuestCount) ...[
                const SizedBox(height: AppSpace.s24),
                const Text(
                  '预计带约人数',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.s4),
                const Text(
                  '您打算邀请几位客户/朋友一起来?',
                  style: TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpace.s12),
                _buildGuestStepper(),
              ],
              const SizedBox(height: AppSpace.s24),
              const Text(
                '留言给主理人',
                style: TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.s8),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                maxLength: 500,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  hintText: '有什么想说的 (可不填)',
                ),
              ),
              const SizedBox(height: AppSpace.s8),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: AppSize.iconLg,
                        height: AppSize.iconLg,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: AppSize.iconLg),
                label: const Text('提交'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, AppSize.buttonLgHeight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 数字 stepper (- / + 大按钮, 0~20)
  Widget _buildGuestStepper() {
    return Row(
      children: [
        _stepButton(
          icon: Icons.remove,
          onTap: _guestCount > 0
              ? () => setState(() => _guestCount--)
              : null,
        ),
        Expanded(
          child: Center(
            child: Text(
              '$_guestCount 人',
              style: const TextStyle(
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryDark,
              ),
            ),
          ),
        ),
        _stepButton(
          icon: Icons.add,
          onTap: _guestCount < 20
              ? () => setState(() => _guestCount++)
              : null,
        ),
      ],
    );
  }

  Widget _stepButton({required IconData icon, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return Material(
      color: enabled
          ? AppTheme.primaryLight.withOpacity(0.5)
          : AppColors.divider,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: AppSpace.s64,
          height: AppSpace.s64,
          child: Icon(
            icon,
            size: AppSize.iconXl,
            color: enabled ? AppTheme.primaryDark : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final status = _status;
    if (status == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择是否接受邀请')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    try {
      final notes = _notesCtrl.text.trim();
      await widget.ref.read(salonServiceProvider).rsvp(
            widget.salon.id,
            status: _apiValueOf(status),
            expectedGuestCount: _showGuestCount ? _guestCount : 0,
            notes: notes.isEmpty ? null : notes,
          );
      invalidateSalon(widget.ref, widget.salon.id);
      widget.ref.read(usageServiceProvider).track('salon_rsvp',
          props: {'status': _apiValueOf(status)});
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('已回复主理人')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('提交失败, 请检查网络')),
      );
    }
  }
}

/// 单个选择按钮 (选中 = 实色底白字)
class _RsvpChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _RsvpChoice({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Container(
        height: AppSpace.s88,
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: AppSpace.s2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: AppSize.iconXl, color: selected ? Colors.white : color),
            const SizedBox(height: AppSpace.s6),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
