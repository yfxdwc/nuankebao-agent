// 加盟徽章 (紫色色块, 中老年清晰)
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FranchiseChip extends StatelessWidget {
  /// 'franchisee' = 紫色"加盟"
  /// 'normal' = 绿色"普通"
  /// 'seed' = 暖橙"种子" (潜在客户, 显式勾选; 主人 2026-09-18)
  final String type;
  final double fontSize;

  const FranchiseChip({
    super.key,
    required this.type,
    this.fontSize = AppTheme.fontXs,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      // 类别图标统一语汇 (主人 2026-09-19 拍: 重新设计, 要贴合类别名 + 高级简洁):
      //   🤝 加盟 = 正式加入合作网络 / 🌱 种子 = 还在萌芽的潜在客户 / 👤 普通 = 普通客户
      //   (旧版 🟣/🟢 只是"一个颜色圆", 不贴合类别名)
      'franchisee' => ('🤝 加盟', AppTheme.franchisee),
      'seed' => ('🌱 种子', AppTheme.accent),
      _ => ('👤 普通', AppTheme.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
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