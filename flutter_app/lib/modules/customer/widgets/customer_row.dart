// 客户列表行 (中老年版, 80pt 行高 + 大头像 + 待办点)
import 'package:flutter/material.dart';
import '../../../core/models/customer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/birthday.dart';
import '../../../core/widgets/typed_user_avatar.dart';
import '../../../core/models/follow_up_info.dart';

import '../../../core/theme/tokens.g.dart';
class CustomerRow extends StatelessWidget {
  final Customer customer;
  /// @deprecated 改用 [customerType] (保留兼容旧调用点; 两者不一致时以 customerType 为准)
  final bool isFranchisee;
  /// 客户类型徽章: franchisee 加盟 / seed 种子 / normal 普通
  /// null = 回退到 [isFranchisee] 推导 (老调用点)
  final String? customerType;
  final String? referrerName;
  final String? lastVisitDate;
  final int pendingCount;
  /// 跟进信息块 (后端算好; 老后端/详情页不传 → null)
  /// 主人 2026-09-20 拍: 左色条(仅会员) + 名字右侧推荐标签 + 第二行「21 天没联系 · 上次电话」
  final FollowUpInfo? followUp;

  /// 会员标识 (主人 2026-09-21 拍): 金环 + 右上角 👑, 画在头像上
  ///   后端每条客户现算 (同手机号账号的会员状态); 老后端不返回 → false
  final bool isMember;
  final VoidCallback onTap;

  const CustomerRow({
    super.key,
    required this.customer,
    required this.onTap,
    this.isFranchisee = false,
    this.customerType,
    this.referrerName,
    this.lastVisitDate,
    this.pendingCount = 0,
    this.followUp,
    this.isMember = false,
  });

  /// 距离生日还有几天 (只在「她设的提醒窗口内」返回, 否则 null → 不显示徽章)
  int? get _birthdayDays {
    final c = customer;
    if (c.birthMonth == null || c.birthDay == null) return null;
    if (c.birthdayRemindDays == null) return null;
    final d = daysUntilBirthday(
      month: c.birthMonth,
      day: c.birthDay,
      calendar: c.birthCalendar,
    );
    if (d == null || d > c.birthdayRemindDays!) return null;
    return d;
  }

  /// 实际展示的类型: 显式 customerType > customer 模型里的 customerType 字段 > isFranchisee 推导
  String get _type {
    final t = customerType ?? customer.customerType;
    if (t.isNotEmpty) return t;
    return isFranchisee ? 'franchisee' : 'normal';
  }

  static const Color _levelP2 = AppColors.memberGoldLight;
  static const Color _levelP4 = AppColors.avatarSlotNeutral;

  /// 分档颜色 (与方案 §3.2 一致; 色 + 文字双编码, 色弱也能分)
  static Color levelColor(String? level) {
    switch (level) {
      case 'p0':
        return AppTheme.danger;
      case 'p1':
        return AppTheme.accent;
      case 'p2':
        return _levelP2;
      case 'p3':
        return AppTheme.primary;
      default:
        return _levelP4;
    }
  }

  static Color tagColor(String key) {
    switch (key) {
      case 'danger':
        return AppTheme.danger;
      case 'accent':
        return AppTheme.accent;
      case 'franchisee':
        return AppTheme.franchisee;
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFranchisee = _type == 'franchisee';
    final f = followUp;
    final barColor = f?.levelKey == null ? null : levelColor(f!.levelKey);
    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
      Container(
        constraints: const BoxConstraints(minHeight: AppTheme.listRowHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 大头像 (56pt) —— 客户类型直接标在头像上 (主人 2026-09-19 拍:
            //   列表不再显示「加盟/种子/普通」标签, 改由 头像环 + 角标 区分)
            TypedUserAvatar(
              avatarUrl: customer.avatar,
              name: customer.name,
              customerType: _type,
              size: AppTheme.avatarMd,
              showLoadingIndicator: false,
              // 会员 = 金环 + 右上角 👑 (客户类型角标仍在右下角, 互不遮挡)
              isMember: isMember,
            ),
            const SizedBox(width: AppSpace.s12),

            // 中间信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行: 姓名 + 推荐标签 + 🎂 生日徽章
                  //   ⚠ 布局 (2026-09-21 修 bug): 标签/徽章以前是**不可压缩**的, 长名字 +
                  //   多个标签时名字会被挤成 0 宽 —— 截图实测「王女士」整行只剩标签, 名字
                  //   直接消失。现在名字保底占 5/9, 标签尾巴占 4/9 且可横向滑动
                  //   (放不下就滑动, 不裁字、不报 overflow)。
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // 名字最多占 55%: 短名字 (「王女士」) 按真实宽度拿空间, 富余宽度
                      // 让给标签; 长名字到 55% 就省略号, 不把标签挤到看不见
                      final nameMax = constraints.maxWidth * 0.55;
                      return Row(
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: nameMax),
                            child: Text(
                              customer.name,
                              style: const TextStyle(
                                fontSize: AppTheme.fontMd,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_rowTail.isNotEmpty) ...<Widget>[
                            const SizedBox(width: AppSpace.s6),
                            // 尾巴吃满剩余宽度; 实在放不下时可横向滑动 (不裁字/不报 overflow)
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: _rowTail,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpace.s4),
                  // 第二行: 跟进信息优先 (主人 2026-09-20 拍 Q3: 动作在标签, 数据在这一行)
                  if (f?.contactLine != null)
                    Text(
                      f!.contactLine!,
                      style: TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: barColor ?? AppTheme.textSecondary,
                        fontWeight: (f.levelKey == 'p0' || f.levelKey == 'p1')
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    )
                  else if (isFranchisee && referrerName != null)
                    Text(
                      '上级: $referrerName',
                      style: const TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: AppTheme.franchisee,
                      ),
                    )
                  else if (lastVisitDate != null)
                    Text(
                      '上次到店 $lastVisitDate',
                      style: const TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),

            // 右侧: 待办红点
            if (pendingCount > 0) ...[
              const SizedBox(width: AppSpace.s8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: Text(
                  '•$pendingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTheme.fontXs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            const SizedBox(width: AppSpace.s4),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary,
              size: 28,
            ),
          ],
        ),
      ),
          // 左侧紧急度色条 (主人 2026-09-20 拍 Q1: 色条属于紧急度体系 → **仅会员**)
          //   4pt 竖条 + 第二行文字也是同色 (色 + 文字双编码)
          if (barColor != null)
            Positioned(
              left: AppSpace.s0,
              top: AppSpace.s0,
              bottom: AppSpace.s0,
              width: AppSpace.s4,
              child: Container(color: barColor),
            ),
        ],
      ),
    );
  }

  /// 第一行右侧的尾巴: 推荐标签 (主人 2026-09-20 拍: 最多 2 个, 动作文案)
  /// + 🎂 生日提醒 (落在她设的提醒窗口内才显示; 主人 2026-09-18 拍)。
  /// 抽出来是因为它现在是**一个可滑动整体**, 不再是 Row 里散开的子节点。
  List<Widget> get _rowTail {
    final tags = followUp?.tags ?? const <FollowUpTagInfo>[];
    return <Widget>[
      for (final t in tags) ...[
        _FollowUpTagChip(tag: t),
        const SizedBox(width: AppSpace.s6),
      ],
      if (_birthdayDays != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(AppRadius.r14),
          ),
          child: Text(
            _birthdayDays == 0 ? '🎂 今天' : '🎂 ${_birthdayDays}天',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppTheme.fontXs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.s6),
      ],
      // ★ 已注册用户标记 (ADR-0016 D8, 主人 2026-09-22 拍「UI 上要有区别」)
      //   true = 她是 app 用户 (有账号) / 不显示 = 凭空建档的客户
      if (customer.hasAccount) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: AppSpace.s4),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
          child: const Text(
            '已注册',
            style: TextStyle(
              // ⚠ 主题里必须显式给 color (AGENTS §5: 不给 = 真机白字)
              color: AppTheme.primaryDark,
              fontSize: AppTheme.fontXs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.s6),
      ],
    ];
  }
}

/// 推荐标签胶囊 (动作文案; 主人 2026-09-20 拍 Q3)
class _FollowUpTagChip extends StatelessWidget {
  final FollowUpTagInfo tag;
  const _FollowUpTagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final color = CustomerRow.tagColor(tag.color);
    return Tooltip(
      message: tag.hint.isEmpty ? tag.label : tag.hint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(AppRadius.r12),
        ),
        child: Text(
          '${tag.emoji}${tag.label}',
          style: TextStyle(
            fontSize: AppTheme.fontXs,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}