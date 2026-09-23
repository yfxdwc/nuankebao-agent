// ============================================
// 「我的」页共用小部件 (个人 / 系统设置 两块都用)
// ============================================
// 提取原因: 「我的」页改造后会有 6 个分区 × 多个条目,
//   如果每处都手写 Card + ListTile, 行高/字号/间距一定漂移
//
// 尺寸约定 (跟 AppTheme 一致, 中老年触摸友好):
//   - 条目最小高度 64 (Material 默认 48 太矮), 触摸区整行可点
//   - 图标 28, 标题 18 (fontMd), 副标题 16 (fontSm)
//   - 卡片 margin 由外层 ListView 控制 (这里统一 margin: zero)

import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

import '../core/theme/tokens.g.dart';
/// 分区卡 (标题 + 条目列表)
class ProfileSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  /// 标题右侧的小字 (如「全店口径」「本机设置」)
  final String? hint;
  final Widget? trailing;

  const ProfileSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.hint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: AppTheme.primaryDark),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: const TextStyle(
                      fontSize: AppTheme.fontXs,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 分区里的一个条目 (圆图标 + 标题 + 副标题 + 右侧)
class ProfileTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  const ProfileTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color = AppTheme.primary,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppTheme.danger : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s10),
        child: Row(
          children: [
            Container(
              width: AppSpace.s44,
              height: AppSpace.s44,
              decoration: BoxDecoration(
                color: tint.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.r22),
              ),
              child: Icon(icon, size: 26, color: tint),
            ),
            const SizedBox(width: AppSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w500,
                      color: danger ? AppTheme.danger : AppTheme.textPrimary,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.s2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpace.s8),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right,
                  size: 28, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// 条目里的「标签 : 值」行 (加盟信息 / 账号信息用)
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppSpace.s84,
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
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// 数据概览里的单个数字 (大数字 + 标签)
class StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  const StatBox({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: AppTheme.fontXl,
                  fontWeight: FontWeight.bold,
                  color: color ?? AppTheme.primary,
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
        ),
      ),
    );
  }
}

/// 分区之间的间距 (统一 16, 别每个页面各写一个数)
const SizedBox profileSectionGap = SizedBox(height: AppSpace.s16);
