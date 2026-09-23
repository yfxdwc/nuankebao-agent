// ============================================
// 用户头像 (默认首字 / 内置候选 / 自己上传)
// ============================================
// 头像值只有三种形态 (跟后端 src/lib/avatar.ts 同一套约定):
//   null              → 默认: 主题色圆 + 姓名首字
//   'preset:<id>'     → 内置候选: 本地画 (图标 + 配色), **不联网不占存储**
//   '/uploads/x.jpg'  → 自己上传的照片: CachedNetworkImage 拉 (走 API origin)
//
// 为什么内置候选用「图标 + 配色」而不是画一堆 PNG:
//   - 矢量图标任意尺寸不糊 (头像在设置页/头部/将来列表里大小不同)
//   - 不增包体 (Material 图标已随包), 不改 assets (子目录声明踩过坑, 见 pubspec 注释)
//   - 中老年用户看到的"换个头像"= 选一个颜色好看的花草, 比一堆卡通人脸更好挑
//
// 边界: 未知/脏值一律退回"首字"分支, 绝不渲染白框

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../http/api_client.dart';
import '../theme/app_theme.dart';

import '../theme/tokens.g.dart';
/// 内置候选头像 (id 必须与后端 AVATAR_PRESETS 一致, 顺序 = 展示顺序)
class AvatarPreset {
  final String id;
  final IconData icon;
  final Color color;
  final String label;

  const AvatarPreset(this.id, this.icon, this.color, this.label);
}

/// 8 个候选: 花草茶禅 + 心阳水 (全养生语义, 无真人脸, 男女通用)
const List<AvatarPreset> kAvatarPresets = [
  AvatarPreset('leaf', Icons.eco, AppColors.avatarSlot1, '绿叶'),
  AvatarPreset('blossom', Icons.local_florist, AppColors.avatarSlot2, '花朵'),
  AvatarPreset('tea', Icons.emoji_food_beverage, AppColors.avatarSlot3, '喝茶'),
  AvatarPreset('zen', Icons.self_improvement, AppColors.avatarSlot4, '静心'),
  AvatarPreset('heart', Icons.favorite, AppColors.dangerBright, '爱心'),
  AvatarPreset('sun', Icons.wb_sunny, AppColors.avatarSlot6, '暖阳'),
  AvatarPreset('sprout', Icons.spa, AppColors.avatarSlot7, '养生'),
  AvatarPreset('water', Icons.water_drop, AppColors.avatarSlot8, '清泉'),
];

AvatarPreset? presetOf(String? avatarUrl) {
  if (avatarUrl == null || !avatarUrl.startsWith('preset:')) return null;
  final id = avatarUrl.substring('preset:'.length);
  for (final p in kAvatarPresets) {
    if (p.id == id) return p;
  }
  return null;
}

bool isUploadedAvatar(String? avatarUrl) =>
    avatarUrl != null && avatarUrl.startsWith('/uploads/');

/// 相对路径 → 绝对 URL (cached_network_image 必须吃绝对地址)
String? absoluteAvatarUrl(String? avatarUrl) {
  if (!isUploadedAvatar(avatarUrl)) return null;
  return '${ApiClient.baseOrigin}${avatarUrl!}';
}

/// 头像 (任何取值都能渲染)
class UserAvatar extends StatelessWidget {
  /// 后端来的原始值 (null / preset:x / /uploads/x.jpg)
  final String? avatarUrl;

  /// 兜底首字取的姓名
  final String name;

  /// 直径 (pt)
  final double size;

  /// 上传图加载中/失败时是否显示小菊花 (列表里的小头像关掉更安静)
  final bool showLoadingIndicator;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.size = 96,
    this.showLoadingIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    final preset = presetOf(avatarUrl);
    if (preset != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: preset.color.withOpacity(0.16),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(preset.icon, size: size * 0.5, color: preset.color),
      );
    }

    final url = absoluteAvatarUrl(avatarUrl);
    if (url != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // 上传图加载中/失败: 退回首字 (不出现白框 / 破图图标)
          placeholder: (_, __) =>
              showLoadingIndicator ? _initial() : _initial(),
          errorWidget: (_, __, ___) => _initial(),
        ),
      );
    }

    return _initial();
  }

  /// 默认头像: 主题浅绿圆 + 姓名首字 (老用户已经习惯的样子)
  Widget _initial() {
    final ch = name.trim().isNotEmpty ? name.trim().characters.first : '我';
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppTheme.primaryLight,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryDark,
        ),
      ),
    );
  }
}
