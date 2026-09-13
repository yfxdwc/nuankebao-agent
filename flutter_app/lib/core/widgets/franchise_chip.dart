// 加盟徽章 (紫色色块, 中老年清晰)
import 'package:flutter/material.dart';
import ''../theme/app_theme.dart'';

class FranchiseChip extends StatelessWidget {
  /// 'franchisee' = 紫色"加盟"
  /// 'normal' = 绿色"普通"
  final String type;
  final double fontSize;

  const FranchiseChip({
    super.key,
    required this.type,
    this.fontSize = AppTheme.fontXs,
  });

  @override
  Widget build(BuildContext context) {
    final isFranchisee = type == 'franchisee';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isFranchisee ? AppTheme.franchisee : AppTheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        isFranchisee ? '🟣 加盟' : '🟢 普通',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 健康标签小 chip (灰底)
class HealthTagChip extends StatelessWidget {
  final String label;
  const HealthTagChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary, width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primaryDark,
          fontSize: AppTheme.fontSm,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}