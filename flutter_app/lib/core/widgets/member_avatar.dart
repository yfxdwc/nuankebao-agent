// ============================================
// 会员标识 (角标 / 金环 / 带头像的完整版) —— 全 App 唯一实现
// ============================================
// 主人 2026-09-21 拍: 「付费会员要在头像上有会员标识以作区分」+「会员在别人的
//   图谱 / 列表里也要有明显标识, 实时同步」
//   标识 = 金色描边 + 右上角 👑 角标 (颜色 + 形状双编码, 老花眼也看得出)
//   非会员 = 原样 (不画灰框: 大多数人是非会员, 人人带框 = 没有区分度)
//
// 三件套 (按"你手上有什么"选):
//   MemberCrown    只加 👑 角标   (头像自己已经有环, 如客户类型环)
//   MemberRing     只加金环       (角标位置被别的东西占了)
//   MemberAvatar   角标 + 金环 + 头像三合一 (账号类头像: 管理员页 / 「我的」页)
//
// 为什么不把 isMember 塞进 TypedUserAvatar 的默认行为: 客户类型环 (加盟紫 / 种子橙)
//   和会员金环是两个语义, 各有各的环色 → TypedUserAvatar 只在显式传 isMember 时才叠
// ============================================

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'user_avatar.dart';

import '../theme/tokens.g.dart';
/// 会员金 (与 AppTheme.accent 区分开: 这是"付费"的信号色, 不是强调色)
const Color kMemberGold = AppColors.memberGold;

/// 👑 会员角标 (右上角) —— 会员标识的**形状**编码, 全 App 一套
///
/// 主人 2026-09-21 拍: 「会员在别人的图谱 / 列表里也要有明显标识」
///   颜色 (金) + 形状 (👑) 双编码: 老花眼 / 色弱都能认出来。
///   位置固定右上角 → 和「客户类型」角标 (右下角 🤝/🌱/👤, 见 TypedUserAvatar)
///   不抢占: 一个头像最多两个角标, 各占一角, 不叠在一起。
///
/// [avatarSize] = 头像直径, 角标按比例 (0.42) → 头像大小变角标跟着变。
class MemberCrown extends StatelessWidget {
  final double avatarSize;

  const MemberCrown({super.key, required this.avatarSize});

  @override
  Widget build(BuildContext context) {
    final badge = avatarSize * 0.42;
    return Container(
      width: badge,
      height: badge,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kMemberGold,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        '👑',
        style: TextStyle(fontSize: badge * 0.62, height: 1.1),
      ),
    );
  }
}

/// 会员金环 (套在头像外面; [avatarSize] = 头像直径)
///   环宽固定 2pt (比客户类型环 2.5pt 细): 会员环是"附加层", 不压过类型信息
class MemberRing extends StatelessWidget {
  final Widget child;
  final double avatarSize;

  const MemberRing({super.key, required this.child, required this.avatarSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.s2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kMemberGold, width: AppSpace.s2),
      ),
      child: child,
    );
  }
}

class MemberAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double size;
  final bool isMember;

  /// 节点没有账号 (历史/脚本造的节点): 画灰圈, 不给"点击看他主页"的错觉
  final bool noAccount;

  const MemberAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.size = 48,
    this.isMember = false,
    this.noAccount = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = noAccount
        ? _NoAccountAvatar(name: name, size: size)
        : UserAvatar(
            avatarUrl: avatarUrl,
            name: name,
            size: size,
            showLoadingIndicator: false,
          );
    // 无账号的灰节点不叠会员金边 (没有账号 = 没有会员/免费之分)
    if (!isMember || noAccount) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        MemberRing(avatarSize: size, child: avatar),
        Positioned(
          right: -1,
          top: -1,
          child: MemberCrown(avatarSize: size),
        ),
      ],
    );
  }
}

/// 没有账号的加盟节点: 灰圈 + 姓首字 (跟 UserAvatar 视觉区分开)
class _NoAccountAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _NoAccountAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.38,
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
