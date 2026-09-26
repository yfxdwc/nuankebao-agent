// ============================================
// 我的 (Profile) 页 —— 个人资料 + 加盟身份 + 数据概览 + 账户安全 + 设置入口
// ============================================
// 目标用户: 大健康销售/客服 (中年女性为主, 移动端)
//   → 一屏内看全「我是谁 / 我下面有谁 / 我干了多少 / 我账户安全」
//   → 每条设置都**真的有效果** (不摆假开关): 字号立即变、退出真退
//
// 数据源 (一次拉完): GET /api/me → 账号 + 加盟身份 + 门店 + 数据概览
//   见 src/app/api/me/route.ts; 模型见 core/models/me.dart
// 本地设置: core/providers/settings_provider.dart (shared_preferences)
//
// 历史 (2026-09-18 主人: "丰富个人和系统设置信息"):
//   旧版 = 头像('我' 占位) + 3 个数字 + 加盟网络入口 + 退出登录。
//   现在: 真实姓名/角色/手机号 (可显示可复制可改) + 加盟身份明细 (编号/位置/上级/加入时间/下线数)
//   + 数据概览 5 项 + 字号快捷入口 + 账号与安全 + 关于与帮助 (详见 settings_page.dart)
//
// 2026-09-25 「我的」页过杂 (原 3~3.5 屏), 主人拍:
//   - 低频设置区块下沉到 /profile/settings (新二级「设置」页)
//   - 字号 (中年刚需) 在「我的」保留 FontSizePicker 快捷入口 + 设置页也放
//   - 沉走: 主题配色 / 提醒 / 关于与帮助
//   - 保留: 显示与存储里的字号 chips + 清理图片缓存入口 (在设置页; 「我的」只剩字号 chips)

import '../modules/follow_up/screens/follow_ups_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/models/me.dart';
import '../core/providers/service_providers.dart';
import '../core/providers/settings_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_empty.dart';
import '../core/widgets/font_size_picker.dart';
import '../core/widgets/franchise_chip.dart';
import '../core/widgets/member_avatar.dart';
import 'profile_sheets.dart';
import 'profile_widgets.dart';

import '../core/theme/tokens.g.dart';
import '../core/widgets/b2_no_chrome.dart';
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(meProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        toolbarHeight: AppSize.appBarHeight,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: AppSize.iconXl),
            tooltip: '刷新',
            onPressed: () => ref.invalidate(meProfileProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(meProfileProvider);
          await ref.read(meProfileProvider.future);
        },
        child: profileAsync.when(
          loading: () => const _ProfileSkeleton(),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(AppSpace.s16),
            children: [
              ErrorState(
                error: e,
                onRetry: () => ref.invalidate(meProfileProvider),
              ),
            ],
          ),
          data: (profile) => _ProfileBody(profile: profile),
        ),
      ),
    );
  }
}

/// 加载中: 保留卡片骨架 (比转圈更不"跳", 老花眼看也不闪)
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 32),
      children: const [
        B2NoChrome(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(AppSpace.s20),
            child: SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final MeProfile profile;
  const _ProfileBody({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = ref.watch(settingsProvider).fontSize;
    return ListView(
      // AlwaysScrollable: 内容不满一屏也要能下拉刷新 (RefreshIndicator 需要可滚动)
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 32),
      children: [
        _HeaderCard(profile: profile),
        profileSectionGap,
        if (profile.franchisee != null)
          _FranchiseCard(franchisee: profile.franchisee!)
        else
          _NotFranchiseeCard(isAdmin: profile.user?.role == 'admin'),
        profileSectionGap,
        _MembershipCard(profile: profile),
        profileSectionGap,
        const _InviteCard(),
        profileSectionGap,
        _StatsCard(profile: profile),
        profileSectionGap,
        // 「设置」区: 字号快捷入口 (中年用户刚需, 不再下沉一层) + 更多设置
        // (主题配色 / 跟进提醒 / 关于与帮助 已迁到 /profile/settings, 详见 settings_page.dart)
        ProfileSection(
          title: '设置',
          icon: Icons.settings_outlined,
          hint: '本机',
          children: [
            const Padding(
              padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s8),
              child: Text(
                '字大看不全 / 字小看不清? 选一档 (选完立即生效, 全 App 都变)',
                style: TextStyle(
                    fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
              ),
            ),
            FontSizePicker(
              selected: fontSize,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setFontSize(v),
            ),
            const SizedBox(height: AppSpace.s8),
            ProfileTile(
              icon: Icons.tune,
              title: '更多设置',
              subtitle: '主题配色 / 跟进提醒 / 关于与帮助',
              onTap: () => context.push('/profile/settings'),
            ),
          ],
        ),
        profileSectionGap,
        _AccountCard(profile: profile),
        profileSectionGap,
        const SizedBox(height: AppSpace.s20),
        // 版本升级入口 (2026-09-25 主人: 「我的」页底部只留轻量版本入口;
        //   大红「退出登录」已下沉到 /profile/settings 底部)
        const _VersionEntry(),
      ],
    );
  }
}

// ============================================
// 1. 头部: 头像 + 姓名 + 角色/加盟身份 + 手机号 + 编辑
// ============================================

class _HeaderCard extends ConsumerStatefulWidget {
  final MeProfile profile;
  const _HeaderCard({required this.profile});

  @override
  ConsumerState<_HeaderCard> createState() => _HeaderCardState();
}

class _HeaderCardState extends ConsumerState<_HeaderCard> {
  /// 手机号明/暗: 默认打码 (页面经常被同事/客户瞄一眼), 点了才显示全号
  bool _showFullPhone = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final name = p.displayName;
    final phone = p.phone;
    final franchisee = p.franchisee;

    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s20),
        child: Column(
          children: [
            // 头像可点: 换头像 (上传照片 / 挑候选) —— 角标用相机小圆点提示"这个能点"
            // 2026-09-25 主人: 删掉了下方重复的「换头像」TextButton (点头像已能换)
            Semantics(
              label: '我的头像, 点击可更换',
              button: true,
              child: InkWell(
                // 换头像的提示/刷新都在弹层里做完 (弹层自己 toast + invalidate provider)
                onTap: () => showAvatarPickerSheet(
                  context,
                  ref,
                  currentAvatarUrl: p.user?.avatarUrl,
                  name: name,
                ),
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 会员标识 (主人 2026-09-21 拍): 「会员在自己 app 的头像上也看得到」
                    //   isMember 来自 GET /api/me → membership (非会员原样, 不加灰框)
                    MemberAvatar(
                      avatarUrl: p.user?.avatarUrl,
                      name: name,
                      size: AppTheme.avatarLg,
                      isMember: p.isMember,
                    ),
                    Positioned(
                      right: AppSpace.s0,
                      bottom: AppSpace.s0,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpace.s6),
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera,
                          size: AppSize.iconSm,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s10),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            if (p.accountAlias != null) ...[
              const SizedBox(height: AppSpace.s4),
              Text(
                '账号: ${p.accountAlias}',
                style: const TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpace.s10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (franchisee != null)
                  const FranchiseChip(type: 'franchisee')
                else
                  const _Tag(text: '未加盟', color: AppTheme.badgeNeutral),
                _Tag(
                  text: p.user?.roleLabel ?? '销售员',
                  color: AppTheme.primary,
                ),
                if (p.store != null)
                  _Tag(text: p.store!.name, color: AppTheme.accent),
              ],
            ),
            if (phone != null && !phone.isEmpty) ...[
              const SizedBox(height: AppSpace.s14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s6),
                decoration: BoxDecoration(
                  color: AppTheme.bgWarm,
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone_iphone,
                        size: AppSize.iconMd, color: AppTheme.primaryDark),
                    const SizedBox(width: AppSpace.s8),
                    // Flexible + ellipsis: 号码在窄屏/特大字号下能缩, 不把这一行顶爆
                    // (号码本身很短, 正常手机永不会真的省略)
                    Flexible(
                      child: Text(
                        _showFullPhone ? phone.full : phone.display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    _PhoneAction(
                      icon: _showFullPhone
                          ? Icons.visibility_off
                          : Icons.visibility,
                      tooltip: _showFullPhone ? '隐藏' : '显示完整手机号',
                      onPressed: () =>
                          setState(() => _showFullPhone = !_showFullPhone),
                    ),
                    _PhoneAction(
                      icon: Icons.copy,
                      tooltip: '复制手机号',
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: phone.full));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('手机号已复制',
                                  style: TextStyle(fontSize: AppTheme.fontMd)),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
            // 账号资料不全 (dev mock 登录没落 user 行) → 明确告诉用户, 别装作正常
            if (p.user != null && !p.user!.hasUserRecord) ...[
              const SizedBox(height: AppSpace.s12),
              const Text(
                '账号资料还没建全 (开发模式登录), 加盟信息可能显示不全',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.danger,
                ),
              ),
            ],
            if (franchisee != null) ...[
              const SizedBox(height: AppSpace.s14),
              SizedBox(
                width: double.infinity,
                height: AppTheme.buttonMinHeight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await showEditMyProfileSheet(
                      context,
                      ref,
                      franchisee: franchisee,
                    );
                    if (saved && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('资料已更新',
                              style: TextStyle(fontSize: AppTheme.fontMd)),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.edit_outlined, size: AppSize.iconLg),
                  label: const Text('编辑我的资料',
                      style: TextStyle(fontSize: AppTheme.fontMd)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 手机号旁边的小按钮 (44pt 触摸区, 不是 IconButton 默认 48+
/// —— 默认尺寸在 320 窄屏 + 特大字号下会把这一行顶溢)
class _PhoneAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PhoneAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.r22),
        child: SizedBox(
          width: AppSpace.s44,
          height: AppSpace.s44,
          child: Icon(icon, size: AppSize.iconLg, color: AppTheme.primaryDark),
        ),
      ),
    );
  }
}

/// 小标签 (角色 / 门店) —— 加盟身份用项目统一的 FranchiseChip
class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTheme.fontSm,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

// ============================================
// 2. 我的加盟身份 (编号 / 位置 / 上级 / 加入时间 / 下线)
// ============================================

class _FranchiseCard extends StatelessWidget {
  final MeFranchisee franchisee;
  const _FranchiseCard({required this.franchisee});

  @override
  Widget build(BuildContext context) {
    final f = franchisee;
    final placement = f.placement;
    final referrer = f.referrer;

    return ProfileSection(
      title: '我的加盟身份',
      icon: Icons.account_tree_outlined,
      hint: '编号 #${f.id}',
      children: [
        InfoRow(label: '位置', value: placement?.sideLabel ?? '顶级'),
        if (placement != null)
          InfoRow(label: '层级', value: placement.depthLabel),
        if (placement != null && placement.path.isNotEmpty)
          InfoRow(label: '路径', value: placement.pathLabel),
        InfoRow(
          label: '我的上级',
          value: referrer == null
              ? '无 (您是顶级加盟商)'
              : '${referrer.name}${referrer.phone == null ? '' : ' · ${referrer.phone!.display}'}',
          trailing: referrer == null
              ? null
              : const Icon(Icons.chevron_right,
                  size: AppSize.iconXl, color: AppTheme.textSecondary),
          onTap: referrer == null
              ? null
              : () => context.push('/franchisees/${referrer.id}'),
        ),
        InfoRow(
          label: '加入时间',
          value: f.joinedAt == null ? '-' : _formatDate(f.joinedAt!),
        ),
        InfoRow(
          label: '状态',
          value: f.isActive ? '正常' : '已停用',
        ),
        InfoRow(
          label: '我的下线',
          value: f.downline.total == 0
              ? '还没有下线'
              : '${f.downline.total} 人 (A线 ${f.downline.left} · B线 ${f.downline.right})',
        ),
        if (f.notes != null && f.notes!.isNotEmpty)
          InfoRow(label: '备注', value: f.notes!),
      ],
    );
  }
}

/// 没绑加盟关系 (合法状态): 说明清楚 + 给管理员的提示, 不是错误页
class _NotFranchiseeCard extends StatelessWidget {
  /// 系统管理员不参与加盟网络 (§6.5: 管理员身份与加盟商身份建议分离) ——
  /// 对他来说"找管理员把您加进去"是句废话, 所以要换成"你能做什么"。
  final bool isAdmin;
  const _NotFranchiseeCard({this.isAdmin = false});

  @override
  Widget build(BuildContext context) {
    if (isAdmin) return const _AdminNoFranchiseeCard();
    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.info_outline, size: AppSize.iconLg, color: AppTheme.accent),
                SizedBox(width: AppSpace.s8),
                Text(
                  '还没绑定加盟关系',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            const Text(
              '账号还没挂到加盟网络上 (不影响录客户/记养生)。'
              '需要挂靠的话找管理员, 在加盟网络里把您加进去。',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 系统管理员专属: 没有加盟关系, 但要能进**整个系统**的用户页 (不是自己的客户页)
class _AdminNoFranchiseeCard extends StatelessWidget {
  const _AdminNoFranchiseeCard();

  @override
  Widget build(BuildContext context) {
    // ⚠ 用 elevation:0 + 不透明底色: Card 默认 elevation 1 + 半透明 color 会叠出一层
    //   灰罩 (2026-09-21 截图实测, 见 /tmp/pa1_top.png), 不是想要的浅绿
    return B2NoChrome(
      margin: EdgeInsets.zero,
      color: AppColors.successLight, // 很浅的绿 (primaryLight #A8D5BA 当整卡底色太扎眼)
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.shield_outlined, size: AppSize.iconLg, color: AppTheme.primaryDark),
                SizedBox(width: AppSpace.s8),
                Text(
                  '系统管理员',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            const Text(
              '管理员不挂在加盟网络上 (不参与分佣/上下级), 但能看整个系统的注册用户与加盟商。'
              '要新开一棵加盟树: 先让本人注册, 再到「管理员工具 → 用户管理」把他设为根节点。',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                height: 1.5,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// 3. 数据概览 (5 个数字 + 加盟网络入口)
// ============================================

class _StatsCard extends StatelessWidget {
  final MeProfile profile;
  const _StatsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final s = profile.stats;

    return ProfileSection(
      title: '数据概览',
      icon: Icons.insights_outlined,
      hint: '全部数据',
      children: [
        // 跟进待办入口 (主人 2026-09-20 拍 P1): 今天要打给谁, 一屏看完
        Consumer(builder: (context, ref, _) {
          final n = ref.watch(pendingFollowUpsProvider).valueOrNull?.length ?? 0;
          return ProfileTile(
            icon: Icons.checklist_rtl,
            title: '跟进待办',
            subtitle: n > 0 ? '$n 条待办：今天该联系谁' : '今天没有待办',
            color: n > 0 ? AppTheme.danger : AppTheme.primary,
            onTap: () => context.push('/follow-ups'),
          );
        }),
        if (s == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.s12),
            child: Text(
              '这次没拿到统计数据, 下拉页面刷新试试',
              style: TextStyle(
                  fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
            ),
          )
        else ...[
          Row(
            children: [
              StatBox(label: '客户', value: '${s.customerCount}'),
              StatBox(
                label: '待办跟进',
                value: '${s.pendingFollowUps}',
                color:
                    s.pendingFollowUps > 0 ? AppTheme.danger : AppTheme.primary,
              ),
            ],
          ),
          Row(
            children: [
              StatBox(label: '本月拜访', value: '${s.thisMonthVisits}'),
              StatBox(
                label: '本月新增客户',
                value: '${s.newCustomersThisMonth}',
                color: AppTheme.accent,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s4),
          const Divider(height: 1),
          InfoRow(label: '累计互动', value: '${s.totalInteractions} 次'),
          // 加盟网络入口只给**非管理员**: 管理员不挂加盟网络 (看自己的上下级没意义),
          //   系统级的用户管理/建根收在「管理员工具」里 (主人 2026-09-21 拍:
          //   「用户管理属于管理员才有的, 应该把入口收到管理员工具页中」)
          if (profile.user?.role != 'admin')
            ProfileTile(
              icon: Icons.account_tree,
              title: '我的加盟网络',
              subtitle: '查看上下级 (A线 / B线 图谱)',
              color: AppTheme.franchisee,
              onTap: () => context.go('/customers?view=graph'),
            ),
        ],
      ],
    );
  }
}

// ============================================
// 4. 设置 (字号快捷入口 + 更多设置)
// ============================================
// 「我的」页只保留字号 chips (中年刚需) + 「更多设置」入口行。低频的:
//   - 清理图片缓存
//   - 主题配色 (换肤)
//   - 跟进提醒
//   - 关于与帮助 (版本/帮助/自检/admin 工具/调试)
//   均迁到 settings_page.dart (路由 /profile/settings)。

// ============================================
// 5. 账号与安全
// ============================================

class _AccountCard extends ConsumerWidget {
  final MeProfile profile;
  const _AccountCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    return ProfileSection(
      title: '账号与安全',
      icon: Icons.lock_outline,
      children: [
        InfoRow(
          label: '登录手机号',
          value: p.phone?.display ?? '未知',
          trailing: p.phone == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.copy, size: AppSize.iconMd),
                  tooltip: '复制',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.phone!.full));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('手机号已复制',
                              style: TextStyle(fontSize: AppTheme.fontMd)),
                        ),
                      );
                    }
                  },
                ),
        ),
        const InfoRow(label: '登录有效', value: '30 天 (期间不用重复登录)'),
        if (p.user != null)
          InfoRow(
            label: '账号编号',
            value: '#${p.user!.id} · ${p.user!.roleLabel}',
          ),
        ProfileTile(
          icon: Icons.password_outlined,
          title: '修改密码',
          subtitle: '首次登录后建议改掉初始密码',
          onTap: () => showChangePasswordSheet(context, ref),
        ),
        // 自助改手机号 (替换原"换号找管理员"提示 — 验证用当前密码)
        ProfileTile(
          icon: Icons.phone_iphone,
          title: '修改手机号',
          subtitle: '需要当前密码验证; 同号客户档案会一起改',
          onTap: () => showChangePhoneSheet(context, ref),
        ),
        const Padding(
          padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s8),
          child: Text(
            '登录账号由管理员开通; 停用账号请联系管理员',
            style: TextStyle(
                fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ============================================
// 7.5 邀请被推荐人 (主人 2026-09-21 拍: "app 不准备上应用商店,
//    需要让被推荐人方便下载 apk")
// ============================================
// 设计:
//   - 二维码链接 = /api/apk-download (公开, 见 src/app/api/apk-download/route.ts 注释)
//   - 位置: 紧挨「会员」区块 —— 推荐码 + APK 二维码同源 ("被推荐人接入")
//   - 所有账号可见 (admin / sales / 客服 / 加盟 / 免费), 无关会员状态
//   - 二维码组件复用 profile_sheets.QrImage (公开化的 _QrImage), size=180 更紧凑
//   - 备用「复制链接」按钮: 二维码看不清 / 文字渠道 (短信/微信) 直接发链接

class _InviteCard extends ConsumerWidget {
  const _InviteCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final releaseAsync = ref.watch(appReleaseProvider);

    return ProfileSection(
      title: '邀请被推荐人',
      icon: Icons.qr_code_2,
      hint: '扫码下载暖客宝',
      children: [
        const Padding(
          padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s12),
          child: Text(
            '把下面的二维码发给被推荐人；他们扫码下载 App 后, 用你的推荐码注册 (双方各得 15 天会员)',
            style: TextStyle(
              fontSize: AppTheme.fontSm,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ),
        releaseAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.s32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s16),
            child: Text(
              '获取 APK 信息失败, 请下拉刷新页面重试 ($e)',
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.danger,
              ),
            ),
          ),
          data: (release) {
            final apk = release.apk;
            if (apk == null || apk.downloadUrl.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpace.s16),
                child: Text(
                  '服务器上还没发布 APK, 请联系管理员',
                  style: TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.textSecondary,
                  ),
                ),
              );
            }
            return Column(
              children: [
                // 二维码白底卡 (中老年看起来边界清晰, 微信扫码稳)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(
                      color: AppTheme.primaryLight,
                      width: AppSpace.s2,
                    ),
                  ),
                  padding: const EdgeInsets.all(AppSpace.s16),
                  child: QrImage(url: apk.downloadUrl, size: 180),
                ),
                const SizedBox(height: AppSpace.s12),
                // 版本 + 大小 (用户问"这是最新版本吗?" 不必再翻)
                Text(
                  '${release.label} · ${_formatSize(apk.sizeBytes)}',
                  style: const TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpace.s12),
                // 备用: 复制链接 (二维码看不清 / 短信/微信直接发)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: apk.downloadUrl),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '下载链接已复制',
                              style: TextStyle(fontSize: AppTheme.fontMd),
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.link, size: AppSize.iconMd),
                    label: const Text(
                      '复制下载链接',
                      style: TextStyle(fontSize: AppTheme.fontSm),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 字节数 → "22.2 MB" / "512 KB" (跟 settings_page 当前版本行的检查更新提示同口径)
String _formatSize(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

// ============================================
// 7. 版本升级入口 (页面最底部, 轻量)
// ============================================
// 2026-09-25 主人: 退出登录太重 (大红按钮) → 下沉 /profile/settings 底部;
//   本页底部改为「本机版本 + 检查更新」轻入口 (与旧「当前版本」行同一弹层)。

class _VersionEntry extends ConsumerWidget {
  const _VersionEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final version = snap.hasData
            ? 'v${snap.data!.version} (${snap.data!.buildNumber})'
            : null;
        return TextButton.icon(
          onPressed: () => showUpdateSheet(context, ref),
          icon: const Icon(Icons.system_update_alt, size: AppSize.iconSm),
          label: Text(
            version == null ? '检查更新' : '暖客宝 $version · 检查更新',
            style: const TextStyle(fontSize: AppTheme.fontSm),
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        );
      },
    );
  }
}

// ============================================
// 会员卡 (ADR-0012 S0: 状态 + 开通入口 + 我的推荐码)
// ============================================

class _MembershipCard extends ConsumerWidget {
  final MeProfile profile;
  const _MembershipCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = profile.membership;
    final isMember = m?.isMember ?? false;
    final until = m?.untilLabel ?? '';
    final daysLeft = m?.daysLeft;

    // 后台账号 (role=admin): 永久会员, 不参与计费 —— 不显示开通/续费入口
    final isAdminMember = m?.isAdminMember ?? false;

    return ProfileSection(
      title: '会员',
      icon: isMember ? Icons.workspace_premium : Icons.card_giftcard,
      hint: isAdminMember ? '管理员 · 永久会员' : (isMember ? '会员中' : '免费版'),
      children: [
        if (isAdminMember) ...[
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s8),
            child: Row(
              children: [
                Icon(Icons.verified_user, size: AppSize.iconLg, color: AppTheme.primary),
                SizedBox(width: AppSpace.s8),
                Expanded(
                  child: Text(
                    '管理员账号 · 永久会员 (无需付费, 不会到期)',
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Text(
            '9 项会员功能全部可用; 员工/管理员账号不参与计费',
            style: TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
          ),
        ] else if (isMember) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s8),
            child: Row(
              children: [
                const Icon(Icons.verified, size: AppSize.iconLg, color: AppTheme.primary),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: Text(
                    daysLeft != null && daysLeft >= 0
                        ? '会员有效期至 $until (还有 $daysLeft 天)'
                        : '会员有效期至 $until',
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'AI 助手 / 互动记录 / 生日提醒 / 图片上传 等会员功能都能用',
            style: TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
          ),
        ] else ...[
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s8),
            child: Text(
              '免费版能用: 客户档案 / 养生记录 / 跟进任务 / 图谱 / 加盟网络\n'
              '会员功能 (9 项): AI 助手 · 跟进建议 · 客户画像 · 效果分析 · 跟进推荐 · '
              '互动记录 · 生日提醒 · 图片上传 · 沙龙发起',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
        if (!isAdminMember)
          ProfileTile(
            icon: Icons.shopping_cart_checkout,
            title: isMember ? '续费会员' : '开通会员',
            subtitle: '¥69 / 月 · 自动续费 ¥49 / 月',
            color: AppTheme.accent,
            onTap: () => _showPurchaseSheet(context, ref, isMember: isMember),
          ),
        // 有人用我的推荐码注册了 → 待我确认 (B1)
        if (m?.hasCode == true) const _PendingReferralsTile(),
        if (m?.hasCode == true)
          _ReferralCodeRow(
            code: m!.referralCode!,
            onRefresh: () => ref.invalidate(meProfileProvider),
          ),
      ],
    );
  }

  /// 开通/续费 → 人工收款弹层 (内测: 个人微信收款码 + 管理员核对)
  /// S1 接微信/支付宝后, 这里换成"拉起收银台" (权益层零改动)
  void _showPurchaseSheet(BuildContext context, WidgetRef ref,
      {required bool isMember}) {
    showMembershipPurchaseSheet(context, ref, isMember: isMember);
  }
}

/// 待我确认的好友 (有人用我的推荐码注册了) —— 没有就不占地方
class _PendingReferralsTile extends ConsumerWidget {
  const _PendingReferralsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myReferralsProvider);
    final pending = async.maybeWhen(
      data: (rows) => rows.where((r) => r.needsMyConfirmation).length,
      orElse: () => 0,
    );

    return ProfileTile(
      icon: Icons.how_to_reg,
      title: pending > 0 ? '好友待确认 ($pending 人)' : '我推荐的人',
      subtitle: pending > 0
          ? '有人用你的推荐码注册了, 点进去确认'
          : '看谁用了你的推荐码',
      color: pending > 0 ? AppTheme.accent : AppTheme.primaryDark,
      onTap: () => context.push('/profile/referrals'),
    );
  }
}

/// 我的推荐码 + 复制 (双向各得 15 天)
class _ReferralCodeRow extends StatelessWidget {
  final String code;
  final VoidCallback onRefresh;

  const _ReferralCodeRow({required this.code, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.s4),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s10),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.18),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.group_add, size: AppSize.iconLg, color: AppTheme.primaryDark),
              const SizedBox(width: AppSpace.s8),
              // Expanded: 窄屏/特大字号下让标题列先缩, 保住推荐码本身完整可读
              const Expanded(
                child: Text(
                  '我的推荐码',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                code,
                style: const TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: AppTheme.primaryDark,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: AppSize.iconMd),
                tooltip: '复制推荐码',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('推荐码已复制',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const Text(
            '把码告诉朋友, 由管理员给朋友建号时填入 (只在建号时有效); 双方各得 15 天会员',
            style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ============================================
// 小工具
// ============================================

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
