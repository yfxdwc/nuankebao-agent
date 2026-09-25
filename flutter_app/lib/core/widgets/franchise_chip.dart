// 加盟徽章 (紫色色块)
//
// ⚠ B2 迁移: 本组件内部颜色块与 [AppBadge] (app_badge.dart) 的实现思路重复
//   (色 + 文字双编码, 圆角 4-16 范围). B2 批次会把现有调用点统一迁到
//   AppBadge (tone=brand/success/info), 这里**暂时保留**避免影响存量页面.
//   B0a 不动本组件 —— 只在本注释里留迁移提示.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../theme/tokens.g.dart';
class FranchiseChip extends StatelessWidget {
  /// 'franchisee' = 紫色"加盟"
  /// 'normal' = 绿色"普通"
  ///
  /// Phase C D3 (§5.4 种子退场): 客户类型三态 → 二态; 灰度期老 APK 仍可能下发
  /// customerType='seed', 本组件**不**新增第三种文案, 兜底渲染为「未加盟」普通。
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
      //   🤝 加盟 = 正式加入合作网络 / 👤 普通 = 普通客户
      //   (旧版 🟣/🟢 只是"一个颜色圆", 不贴合类别名)
      //   'seed' / 未知值 一律按「未加盟」兜底 —— 设计 §4.2 L1 二态
      'franchisee' => ('🤝 加盟', AppTheme.franchisee),
      _ => ('👤 普通', AppTheme.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.r16),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s6),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.4),
        borderRadius: BorderRadius.circular(AppRadius.r14),
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