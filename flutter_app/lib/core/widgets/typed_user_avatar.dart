// ============================================
// 带「客户类型」的头像 (主人 2026-09-19 拍)
// ============================================
// 主人原话: 「客户类型（加盟、普通、种子）在客户列表中不显示类型标签，类型在头像上区分」
//
// 方案 (颜色 + 汉字双编码, 不依赖单一颜色 → 色弱/老花也能分):
//   加盟 franchisee → 紫色头像环 (2.5pt) + 右下角紫色圆徽章「盟」
//   种子 seed       → 暖橙头像环 (2pt)   + 右下角暖橙圆徽章「种」
//   普通 normal     → 无环无徽章 (最安静, 让加盟/种子跳出来)
//
// 为什么用汉字不用 emoji:
//   - 中老年用户读「盟 / 种」比读 🌱/🟣 稳, 且 20pt 内汉字笔画清楚
//   - 颜色只是辅助 (色弱用户看字也能分)
// 尺寸: 徽章只在 size >= 40 时画 (小头像如 32pt 只留环, 否则字糊成一团)

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'user_avatar.dart';

class TypedUserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double size;

  /// franchisee / seed / normal (未知值按 normal 处理)
  final String customerType;

  /// 上传图加载中/失败是否显示小菊花 (列表里建议关掉)
  final bool showLoadingIndicator;

  const TypedUserAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.customerType,
    this.size = AppTheme.avatarMd,
    this.showLoadingIndicator = false,
  });

  /// 类型 → (环/徽章颜色, 徽章字, 无障碍文案)
  static (Color?, String?, String) styleOf(String type) {
    switch (type) {
      case 'franchisee':
        return (AppTheme.franchisee, '盟', '加盟商');
      case 'seed':
        return (AppTheme.accent, '种', '种子客户');
      default:
        return (null, null, '普通客户');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, badge, typeLabel) = styleOf(customerType);
    final ringWidth = size >= 48 ? 2.5 : 2.0;
    final showBadge = badge != null && size >= 40;
    final badgeSize = size * 0.42;

    return Semantics(
      label: '$name, $typeLabel',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 环 + 头像本体 (环在头像外面一圈, 不压缩头像视觉大小)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: color == null
                    ? null
                    : Border.all(color: color, width: ringWidth),
              ),
              padding: EdgeInsets.all(color == null ? 0 : 1.5),
              child: UserAvatar(
                avatarUrl: avatarUrl,
                name: name,
                size: size - (color == null ? 0 : 3),
                showLoadingIndicator: showLoadingIndicator,
              ),
            ),
            // 右下角类型徽章 (白描边 → 压住照片也看得清)
            if (showBadge)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: badgeSize * 0.56,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
