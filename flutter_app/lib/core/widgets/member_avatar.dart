// ============================================
// 带头像的会员标识 (管理员用户管理页用)
// ============================================
// 主人 2026-09-21 拍: 「付费会员要在头像上有会员标识以作区分」
//   标识 = 金色描边 + 右上角 👑 角标 (颜色 + 形状双编码, 老花眼也看得出)
//   非会员 = 原样 (不画灰框: 大多数人是非会员, 人人带框 = 没有区分度)
//
// 为什么不改 TypedUserAvatar: 那个是客户列表按"客户类型"上环/角标的组件,
//   塞会员语义会串味 (客户类型 vs 账号会员是两回事), 且改动会波及客户列表
// ============================================

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'user_avatar.dart';

/// 会员金 (与 AppTheme.accent 区分开: 这是"付费"的信号色, 不是强调色)
const Color kMemberGold = Color(0xFFC89A2B);

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

    final badge = size * 0.42;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kMemberGold, width: 2),
          ),
          child: avatar,
        ),
        Positioned(
          right: -1,
          top: -1,
          child: Container(
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
          ),
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
        color: const Color(0xFFF0F1EF),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFBFC6C1), width: 1.5),
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
