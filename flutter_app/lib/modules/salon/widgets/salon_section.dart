// ============================================
// 沙龙详情区块 / 信息行 + 时间格式化 (v0.1.5 Phase 7)
// ============================================
// 手写时间格式 (不用 DateFormat 的 locale 参数):
//   缩短版 "9月20日 周六 14:00" (列表卡片)
//   完整版 "2026年9月20日 周六 14:00" (详情)
// ============================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/theme/tokens.g.dart';
/// 白色卡片区块: 标题行 (图标 + 标题) + 内容, 可带右侧 trailing
class SalonSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const SalonSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppSize.iconLg, color: AppTheme.primary),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpace.s10),
            child,
          ],
        ),
      ),
    );
  }
}

/// 信息行: 左 label (灰) + 右 value (深); value 为空 → 整行不渲染
class SalonInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  const SalonInfoRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = value;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSize.iconMd, color: AppTheme.textSecondary),
          const SizedBox(width: AppSpace.s8),
          Text(
            label,
            style: const TextStyle(
              fontSize: AppTheme.fontSm,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpace.s12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpace.s4),
            const Icon(Icons.chevron_right, size: AppSize.iconLg, color: AppTheme.textSecondary),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: row,
      ),
    );
  }
}

// ============================================
// 时间格式化 (手拼, 不依赖 locale)
// ============================================

const List<String> _salonWeekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String _two(int n) => n.toString().padLeft(2, '0');

/// '14:00'
String formatSalonHm(DateTime dt) => '${_two(dt.hour)}:${_two(dt.minute)}';

String _weekdayOf(DateTime dt) => _salonWeekdays[dt.weekday - 1];

/// '9月20日 周六 14:00' (列表卡片用; null → '时间待定')
String formatSalonShortDateTime(DateTime? dt) {
  if (dt == null) return '时间待定';
  return '${dt.month}月${dt.day}日 ${_weekdayOf(dt)} ${formatSalonHm(dt)}';
}

/// '2026年9月20日 周六 14:00' (详情用; null → '待定')
String formatSalonFullDateTime(DateTime? dt) {
  if (dt == null) return '待定';
  return '${dt.year}年${dt.month}月${dt.day}日 ${_weekdayOf(dt)} ${formatSalonHm(dt)}';
}

/// '9月20日 14:00' (动态时间用; null → '')
String formatSalonMonthDayTime(DateTime? dt) {
  if (dt == null) return '';
  return '${dt.month}月${dt.day}日 ${formatSalonHm(dt)}';
}

/// 是否同一天 (时间行显示 "14:00-16:00" 用)
bool salonSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
