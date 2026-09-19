// ============================================
// 带「客户类型」的头像 (主人 2026-09-19 拍)
// ============================================
// 主人原话: 「客户类型（加盟、普通、种子）在客户列表中不显示类型标签，类型在头像上区分」
//
// 方案 (主人 2026-09-19 第二版: 纯 emoji 角标, 三类都显示):
//   🤝 加盟 franchisee → 紫色头像环 (2.5pt) + 右下角紫色圆徽章 🤝
//   🌱 种子 seed       → 暖橙头像环 (2pt)   + 右下角暖橙圆徽章 🌱
//   👤 普通 normal     → 无环                  + 右下角浅灰圆徽章 👤
//
// 类别图标语汇 (全 App 统一: 角标 + 胶囊 chip 用同一套):
//   🤝 = 正式加入合作网络 (加盟)  |  🌱 = 还在萌芽的潜在客户 (种子)  |  👤 = 普通客户
//   (旧版 🟣/🟢 只是"一个颜色圆", 不贴合类别名 → 主人 2026-09-19 拍: 重新设计)
//
// 视觉重量刻意分层: 加盟 (环+彩徽章) > 种子 (环+彩徽章) > 普通 (浅灰徽章, 无环)
//   —— 普通占大多数, 让它安静, 加盟/种子才跳得出来
// 尺寸: 徽章只在 size >= 40 时画 (更小的头像只留环, 否则 emoji 糊成一团)

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

  /// 类型 → (环/徽章颜色, 角标 emoji, 无障碍文案)
  ///   普通 的徽章色是「浅灰」: 有角标但视觉最轻
  static (Color?, String?, String) styleOf(String type) {
    switch (type) {
      case 'franchisee':
        return (AppTheme.franchisee, '🤝', '加盟商');
      case 'seed':
        return (AppTheme.accent, '🌱', '种子客户');
      default:
        return (const Color(0xFF9AA5A0), '👤', '普通客户');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (badgeColor, badge, typeLabel) = styleOf(customerType);
    // 普通不加环 (只有彩徽章), 加盟/种子加环 → 视觉重量分层
    final ringColor = customerType == 'normal' ? null : badgeColor;
    final ringWidth = size >= 48 ? 2.5 : 2.0;
    final showBadge = size >= 40;
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
                border: ringColor == null
                    ? null
                    : Border.all(color: ringColor, width: ringWidth),
              ),
              padding: EdgeInsets.all(ringColor == null ? 0 : 1.5),
              child: UserAvatar(
                avatarUrl: avatarUrl,
                name: name,
                size: size - (ringColor == null ? 0 : 3),
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
                    color: badgeColor,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  // emoji 角标: 字号比汉字大一点才看得清 (emoji 自带留白)
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: badgeSize * 0.62,
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
