// ============================================
// 客户列表行 (B 档换装, B1 客户域 2026-09-24)
//
// 拆完 customers_page.dart → 5 文件后, 本组件改用 B0a 的 [AppListRow]
//   · 行高 80 → 60 (AppListRow 默认), 一屏可看 9+ 客户
//   · 行高 60 由 AppListRow 的 ConstrainedBox(minHeight: AppSize.listRowHeight) 撑
//   · 主文 = 姓名 (AppType.md/medium/textPrimary) + 标签尾巴 (横向滑动整体)
//   · 副文 = 跟进信息 / 上级加盟人 / 上次到店 (sm/secondary)
//   · meta  = 待办数 (右侧红点) + 箭头
//   · 左侧紧急度色条 (仅会员) 用 Stack 套在外面, 不影响 AppListRow 的标准结构
// ============================================

import 'package:flutter/material.dart';

import '../../../core/models/customer.dart';
import '../../../core/models/follow_up_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/utils/birthday.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/typed_user_avatar.dart';

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
  /// Phase C D3 (§5.4 种子退场): 后端 legacy 'seed' 仍可能在灰度期返回, UI 兜底为 'normal'
  ///   → 'franchisee' / 'normal' 二态 (设计 §4.2 L1, 头像环按此渲染)
  String get _type {
    final t = customerType ?? customer.customerType;
    if (t == 'franchisee') return 'franchisee';
    return 'normal'; // seed/normal/未知 一律按未加盟走
  }

  /// 归属五态 (Phase C §3.4): 默认 mine 静默, 异常态显形 (设计 §4.2 L2)
  ///   'mine'         → null (静默, 不出 badge)
  ///   'subordinate'  → 「下级的客户」(ownerName 待 Phase D 后端带, 现仅前缀)
  ///   'upline'       → 「上级推送」 (Phase D 落地后才有数据)
  ///   'none'         → 「无归属」
  ///   'other'        → 「他人客户」(scope 漏检告警兜底)
  /// 老后端不返回 ownership → 默认 'none' (异常态显形, 与设计文档一致)
  (String, AppBadgeTone)? get _ownershipBadge {
    final o = customer.ownership;
    switch (o) {
      case 'mine':
      case '':
        return null; // 默认静默
      case 'subordinate':
        return ('下级的客户', AppBadgeTone.info);
      case 'upline':
        return ('上级推送', AppBadgeTone.brand);
      case 'none':
        return ('无归属', AppBadgeTone.neutral);
      case 'other':
        return ('他人客户', AppBadgeTone.warning);
      default:
        return null; // 未知值 → 静默 (避免乱出)
    }
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

  // ============================================
  // 构建函数
  // ============================================

  /// 主文 (第一行): 姓名 + 归属 badge (L2) + 推荐标签 + 🎂 生日徽章 + 已注册标
  ///
  /// 名字保底 50% 宽 + L2 归属 badge + 标签尾巴占剩余 (放不下横向滑动, 不裁字/不报 overflow)
  /// Phase C §4.2 L2: 归属 5 态 — mine 静默 (不出), 其余显形, 走 AppBadge tone (不新增 Card)
  Widget _buildTitle() {
    final tail = _rowTail;
    final own = _ownershipBadge;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 名字最多占 50%: 留空间给 L2 归属 badge (异常态) + 标签尾巴; 短名字按真实宽度,
        // 长名字到 50% 就省略号, 不把标签挤到看不见
        final nameMax = constraints.maxWidth * 0.50;
        return Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: nameMax),
              child: Text(
                customer.name,
                style: const TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppWeight.semibold,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            // L2 归属 badge (Phase C §4.2 五态): mine 静默, 其余显形, 不撑行高 (AppBadge dense)
            if (own != null) ...<Widget>[
              const SizedBox(width: AppSpace.s6),
              AppBadge(label: own.$1, tone: own.$2, dense: true),
            ],
            if (tail.isNotEmpty || own != null) ...<Widget>[
              const SizedBox(width: AppSpace.s6),
              // 尾巴吃满剩余宽度; 实在放不下时可横向滑动 (不裁字/不报 overflow)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: tail,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 副文 (第二行): 跟进信息 / 上级加盟人 / 上次到店
  Widget? _buildSubtitle(FollowUpInfo? f, bool isFranchiseeType, Color? barColor) {
    if (f?.contactLine != null) {
      return Text(
        f!.contactLine!,
        style: TextStyle(
          fontSize: AppType.xs,
          color: barColor ?? AppColors.textSecondary,
          fontWeight: (f.levelKey == 'p0' || f.levelKey == 'p1')
              ? AppWeight.semibold
              : AppWeight.regular,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (isFranchiseeType && referrerName != null) {
      return Text(
        '上级: $referrerName',
        style: const TextStyle(
          fontSize: AppType.xs,
          color: AppTheme.franchisee,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (lastVisitDate != null) {
      return Text(
        '上次到店 $lastVisitDate',
        style: const TextStyle(
          fontSize: AppType.xs,
          color: AppColors.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return null;
  }

  /// 右侧 meta 区: 待办红点 + 箭头
  Widget? _buildMeta() {
    if (pendingCount <= 0) return null;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s10, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: AppTheme.danger,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Text(
        '•$pendingCount',
        style: const TextStyle(
          color: Colors.white,
          fontSize: AppType.xs,
          fontWeight: AppWeight.semibold,
        ),
      ),
    );
  }

  /// 最右 trailing: 箭头图标
  Widget? _buildTrailing() {
    return const Icon(
      Icons.chevron_right,
      color: AppColors.textSecondary,
      size: AppSize.iconXl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFranchisee = _type == 'franchisee';
    final f = followUp;
    final barColor = f?.levelKey == null ? null : levelColor(f!.levelKey);

    final row = AppListRow(
      // leading = 头像 (B 档 44, 视觉 44 但 hit box ≥48)
      // 客户类型直接标在头像上 (主人 2026-09-19 拍:
      //   列表不再显示「加盟/种子/普通」标签, 改由 头像环 + 角标 区分)
      leading: TypedUserAvatar(
        avatarUrl: customer.avatar,
        name: customer.name,
        customerType: _type,
        size: AppTheme.avatarMd,
        showLoadingIndicator: false,
        // 会员 = 金环 + 右上角 👑 (客户类型角标仍在右下角, 互不遮挡)
        isMember: isMember,
      ),
      title: _buildTitle(),
      subtitle: _buildSubtitle(f, isFranchisee, barColor),
      meta: _buildMeta(),
      trailing: _buildTrailing(),
      onTap: onTap,
    );

    // 左侧紧急度色条 (主人 2026-09-20 拍 Q1: 色条属于紧急度体系 → **仅会员**)
    //   4pt 竖条 + 第二行文字也是同色 (色 + 文字双编码)
    if (barColor == null) return row;
    return Stack(
      children: [
        row,
        Positioned(
          left: AppSpace.s0,
          top: AppSpace.s0,
          bottom: AppSpace.s0,
          width: AppSpace.s4,
          child: Container(color: barColor),
        ),
      ],
    );
  }

  /// 第一行右侧的尾巴: 推荐标签 (主人 2026-09-20 拍 Q3: 最多 2 个, 动作文案)
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
              fontSize: AppType.xs,
              fontWeight: AppWeight.semibold,
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
              fontSize: AppType.xs,
              fontWeight: AppWeight.semibold,
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
            fontSize: AppType.xs,
            color: color,
            fontWeight: AppWeight.semibold,
          ),
        ),
      ),
    );
  }
}