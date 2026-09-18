// ============================================
// 沙龙列表卡片 (v0.1.5 Phase 7)
// ============================================
// 一屏看清: 标题 + 状态 + 我的身份 + 时间地点 + 人数统计 + 我的带约任务
// 已结束/已取消整体淡化 (0.6), 但仍可点进详情回看.
// ============================================

import 'package:flutter/material.dart';

import '../../../core/models/salon.dart';
import '../../../core/theme/app_theme.dart';
import 'salon_section.dart';
import 'salon_status_chip.dart';

class SalonCard extends StatelessWidget {
  final Salon salon;
  final VoidCallback onTap;

  const SalonCard({super.key, required this.salon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dim = salon.status == SalonStatus.finished ||
        salon.status == SalonStatus.cancelled;
    final viewer = salon.viewer;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: dim ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题 + 状态
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        salon.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppTheme.fontLg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SalonStatusChip(status: salon.status),
                  ],
                ),
                if (salon.subtitle != null && salon.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    salon.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),

                // 我的身份 / 我的回复 / 带约任务
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SalonRoleChip(label: viewer.roleLabel),
                    if (viewer.myInvitationId != null &&
                        viewer.myStatus != null)
                      SalonInviteStatusChip(status: viewer.myStatus!),
                    if (viewer.myQuotaValue != null)
                      _QuotaBadge(value: viewer.myQuotaValue!),
                  ],
                ),
                const SizedBox(height: 10),

                // 时间
                _IconLine(
                  icon: Icons.schedule,
                  text: _timeText,
                ),
                // 地点 (空则不显示)
                if (salon.addressLine.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _IconLine(
                    icon: Icons.place_outlined,
                    text: salon.addressLine,
                  ),
                ],
                const SizedBox(height: 10),

                // 人数统计小字
                Text(
                  _statsText,
                  style: const TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// '9月20日 周六 14:00' / 同一天带结束时间 '14:00-16:00'
  String get _timeText {
    final start = salon.startAt;
    if (start == null) return '时间待定';
    final end = salon.endAt;
    if (end != null && salonSameDay(start, end)) {
      return '${formatSalonShortDateTime(start)}-${formatSalonHm(end)}';
    }
    return formatSalonShortDateTime(start);
  }

  /// '受邀 12 人 · 预计带约 8 人 · 名额 6/30'
  String get _statsText {
    final counts = salon.counts;
    final buffer = StringBuffer('受邀 ${counts.invitedTotal} 人');
    buffer.write(' · 预计带约 ${counts.expectedGuests} 人');
    if (counts.capacityTotal != null) {
      buffer.write(' · 名额 ${counts.accepted + counts.attended}/${counts.capacityTotal}');
    }
    return buffer.toString();
  }
}

/// 图标 + 一行文字 (时间 / 地点)
class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
        ),
      ],
    );
  }
}

/// 我的带约任务角标
class _QuotaBadge extends StatelessWidget {
  final int value;

  const _QuotaBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_outlined, size: 16, color: Color(0xFF8A5A1F)),
          const SizedBox(width: 4),
          Text(
            '带约 $value 人',
            style: const TextStyle(
              fontSize: AppTheme.fontXs,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A5A1F),
            ),
          ),
        ],
      ),
    );
  }
}
