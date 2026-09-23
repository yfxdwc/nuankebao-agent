// ============================================
// 沙龙状态胶囊 (v0.1.5 Phase 7)
// ============================================
// 状态 / 角色 / 邀请 / 客人 四种小胶囊, 列表卡片和详情页共用.
// 文案全部走 model 的 label (中文, 不硬编码状态名).
// ============================================

import 'package:flutter/material.dart';

import '../../../core/models/salon.dart';
import '../../../core/theme/app_theme.dart';

import '../../../core/theme/tokens.g.dart';
/// 中性灰 (草稿 / 已结束 / 已截止等)
const Color _salonGray = AppColors.textTertiary;

/// 沙龙状态胶囊: 报名中=绿 草稿=灰 已取消=红 已结束/截止=灰 进行中=橙
class SalonStatusChip extends StatelessWidget {
  final SalonStatus status;

  const SalonStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return _MiniChip(label: status.label, color: _colorOf(status));
  }

  static Color _colorOf(SalonStatus status) {
    switch (status) {
      case SalonStatus.published:
        return AppTheme.primary;
      case SalonStatus.ongoing:
        return AppTheme.accent;
      case SalonStatus.cancelled:
        return AppTheme.danger;
      case SalonStatus.draft:
      case SalonStatus.registrationClosed:
      case SalonStatus.finished:
        return _salonGray;
    }
  }
}

/// 我的身份胶囊: 主理人=紫 会务=蓝 受邀者=绿
class SalonRoleChip extends StatelessWidget {
  final String label; // viewer.roleLabel

  const SalonRoleChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (label) {
      case '主理人':
        color = AppTheme.franchisee;
        break;
      case '会务':
        color = AppTheme.franchiseeA;
        break;
      default:
        color = AppTheme.primary;
        break;
    }
    return _MiniChip(label: label, color: color);
  }
}

/// 受邀回复状态胶囊 (待回复 / 已接受 / 待定 / 已婉拒 / 已到场 ...)
class SalonInviteStatusChip extends StatelessWidget {
  final SalonInvitationStatus status;

  const SalonInviteStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return _MiniChip(label: status.label, color: _colorOf(status));
  }

  static Color _colorOf(SalonInvitationStatus status) {
    switch (status) {
      case SalonInvitationStatus.accepted:
        return AppTheme.primary;
      case SalonInvitationStatus.attended:
        return AppTheme.primaryDark;
      case SalonInvitationStatus.tentative:
        return AppTheme.accent;
      case SalonInvitationStatus.declined:
        return AppTheme.danger;
      case SalonInvitationStatus.waitlist:
        return AppTheme.franchiseeA;
      case SalonInvitationStatus.pending:
      case SalonInvitationStatus.absent:
      case SalonInvitationStatus.cancelled:
        return _salonGray;
    }
  }
}

/// 二级客人状态胶囊 (待确认 / 会来 / 不来了 / 已到场 ...)
class SalonGuestStatusChip extends StatelessWidget {
  final SalonGuestStatus status;

  const SalonGuestStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return _MiniChip(label: status.label, color: _colorOf(status));
  }

  static Color _colorOf(SalonGuestStatus status) {
    switch (status) {
      case SalonGuestStatus.accepted:
        return AppTheme.primary;
      case SalonGuestStatus.attended:
        return AppTheme.primaryDark;
      case SalonGuestStatus.declined:
        return AppTheme.danger;
      case SalonGuestStatus.pending:
      case SalonGuestStatus.absent:
      case SalonGuestStatus.cancelled:
        return _salonGray;
    }
  }
}

/// 小胶囊底座 (实色底 + 白字, 中老年清晰)
class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.r14),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: AppTheme.fontXs,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
