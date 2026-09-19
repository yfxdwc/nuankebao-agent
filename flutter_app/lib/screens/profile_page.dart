// ============================================
// 我的 (Profile) 页 —— 个人资料 + 加盟身份 + 数据概览 + 系统设置
// ============================================
// 目标用户: 大健康销售/客服 (中年女性为主, 移动端)
//   → 一屏内看全「我是谁 / 我下面有谁 / 我干了多少 / 我手机上的设置」
//   → 每条设置都**真的有效果** (不摆假开关): 字号立即变、版本真能查、
//     网络自检真连服务器、缓存真清、退出真退
//
// 数据源 (一次拉完): GET /api/me → 账号 + 加盟身份 + 门店 + 数据概览
//   见 src/app/api/me/route.ts; 模型见 core/models/me.dart
// 本地设置: core/providers/settings_provider.dart (shared_preferences)
//
// 历史 (2026-09-18 主人: "丰富个人和系统设置信息"):
//   旧版 = 头像('我' 占位) + 3 个数字 + 加盟网络入口 + 退出登录。
//   现在: 真实姓名/角色/手机号 (可显示可复制可改) + 加盟身份明细 (编号/位置/上级/加入时间/下线数)
//   + 数据概览 5 项 + 字号设置 + 账号与安全 (缓存/退出) + 关于与帮助 (版本/更新/自检/说明)

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../core/http/api_client.dart';
import '../core/models/me.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/service_providers.dart';
import '../core/providers/settings_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/franchise_chip.dart';
import '../core/widgets/user_avatar.dart';
import 'profile_sheets.dart';
import 'profile_widgets.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(meProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 28),
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
            padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: const [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(20),
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
    return ListView(
      // AlwaysScrollable: 内容不满一屏也要能下拉刷新 (RefreshIndicator 需要可滚动)
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _HeaderCard(profile: profile),
        profileSectionGap,
        if (profile.franchisee != null)
          _FranchiseCard(franchisee: profile.franchisee!)
        else
          const _NotFranchiseeCard(),
        profileSectionGap,
        _MembershipCard(profile: profile),
        profileSectionGap,
        _StatsCard(profile: profile),
        profileSectionGap,
        const _DisplaySettingsCard(),
        profileSectionGap,
        _AccountCard(profile: profile),
        profileSectionGap,
        const _AboutCard(),
        const SizedBox(height: 20),
        const _LogoutButton(),
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

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 头像可点: 换头像 (上传照片 / 挑候选) —— 角标用相机小圆点提示"这个能点"
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
                    UserAvatar(
                      avatarUrl: p.user?.avatarUrl,
                      name: name,
                      size: AppTheme.avatarLg,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => showAvatarPickerSheet(
                context,
                ref,
                currentAvatarUrl: p.user?.avatarUrl,
                name: name,
              ),
              icon: const Icon(Icons.face_retouching_natural, size: 20),
              label: const Text('换头像',
                  style: TextStyle(fontSize: AppTheme.fontSm)),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryDark,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(height: 6),
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
              const SizedBox(height: 4),
              Text(
                '账号: ${p.accountAlias}',
                style: const TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 10),
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
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.bgWarm,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone_iphone,
                        size: 22, color: AppTheme.primaryDark),
                    const SizedBox(width: 8),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 14),
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
                  icon: const Icon(Icons.edit_outlined, size: 24),
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
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 24, color: AppTheme.primaryDark),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
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
                  size: 28, color: AppTheme.textSecondary),
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
  const _NotFranchiseeCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.info_outline, size: 24, color: AppTheme.accent),
                SizedBox(width: 8),
                Text(
                  '还没绑定加盟关系',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
        if (s == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
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
          const SizedBox(height: 4),
          const Divider(height: 1),
          InfoRow(label: '累计互动', value: '${s.totalInteractions} 次'),
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
// 4. 显示与存储 (字号 / 清缓存)
// ============================================

class _DisplaySettingsCard extends ConsumerStatefulWidget {
  const _DisplaySettingsCard();

  @override
  ConsumerState<_DisplaySettingsCard> createState() =>
      _DisplaySettingsCardState();
}

class _DisplaySettingsCardState extends ConsumerState<_DisplaySettingsCard> {
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    final fontSize = ref.watch(settingsProvider).fontSize;

    return ProfileSection(
      title: '显示与存储',
      icon: Icons.text_fields,
      hint: '本机设置',
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            '字大看不全 / 字小看不清? 选一档 (选完立即生效, 全 App 都变)',
            style: TextStyle(
                fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: AppFontSize.values.map((v) {
            return ChoiceChip(
              label: Text(
                v.label,
                style: TextStyle(
                  // 档位名自己就体现大小 (小 < 标准 < 大 < 特大), 不让用户看倍率数字
                  fontSize: AppTheme.fontMd +
                      switch (v) {
                        AppFontSize.small => -2,
                        AppFontSize.standard => 0,
                        AppFontSize.large => 2,
                        AppFontSize.xlarge => 4,
                      },
                  fontWeight: FontWeight.w600,
                ),
              ),
              selected: fontSize == v,
              onSelected: (_) =>
                  ref.read(settingsProvider.notifier).setFontSize(v),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        ProfileTile(
          icon: Icons.photo_library_outlined,
          title: _clearing ? '正在清理...' : '清理图片缓存',
          subtitle: '养生记录里的照片会临时存在手机上, 清理不影响数据',
          color: AppTheme.accent,
          onTap: _clearing
              ? null
              : () async {
                  setState(() => _clearing = true);
                  try {
                    await DefaultCacheManager().emptyCache();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('图片缓存已清理',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                    );
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('清理失败, 稍后再试',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                    );
                  } finally {
                    if (mounted) setState(() => _clearing = false);
                  }
                },
        ),
      ],
    );
  }
}

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
                  icon: const Icon(Icons.copy, size: 22),
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
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            '登录账号由管理员开通; 换号 / 停用账号请联系管理员',
            style: TextStyle(
                fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ============================================
// 6. 关于与帮助 (版本 / 更新 / 自检)
// ============================================

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProfileSection(
      title: '关于与帮助',
      icon: Icons.info_outline,
      children: [
        const _VersionTile(),
        ProfileTile(
          icon: Icons.system_update_alt,
          title: '检查更新',
          subtitle: '看服务器上有没有新版本',
          onTap: () => showUpdateSheet(context, ref),
        ),
        ProfileTile(
          icon: Icons.menu_book_outlined,
          title: '使用帮助 / 数据安全',
          subtitle: '怎么录客户、数据存在哪',
          onTap: () => context.push('/profile/about'),
        ),
        ProfileTile(
          icon: Icons.wifi_find,
          title: '网络自检',
          subtitle: '连不上时先点这里',
          color: AppTheme.accent,
          onTap: () => showDiagnosticsSheet(context, ref),
        ),
        // 服务地址: 开发/排障可见 (生产用户看到 IP 只会困惑)
        if (kDebugMode)
          ProfileTile(
            icon: Icons.dns_outlined,
            title: '服务地址 (调试)',
            subtitle: ApiClient.baseUrl,
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 22),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: ApiClient.baseUrl),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制',
                          style: TextStyle(fontSize: AppTheme.fontMd)),
                    ),
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

/// 版本行 (本机版本, 点一下 = 检查更新)
class _VersionTile extends ConsumerWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final label = snap.hasData
            ? 'v${snap.data!.version} (${snap.data!.buildNumber})'
            : (snap.hasError ? '读取失败' : '读取中...');
        return ProfileTile(
          icon: Icons.verified_outlined,
          title: '当前版本',
          subtitle: '暖客宝 · 数据自托管',
          trailing: Text(
            label,
            style: const TextStyle(
              fontSize: AppTheme.fontSm,
              color: AppTheme.textSecondary,
            ),
          ),
          onTap: () => showUpdateSheet(context, ref),
        );
      },
    );
  }
}

// ============================================
// 7. 退出登录 (页面最底部, 危险操作)
// ============================================

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      height: AppTheme.buttonLgHeight,
      child: OutlinedButton.icon(
        onPressed: () => _confirmLogout(context, ref),
        icon: const Icon(Icons.logout, size: 26),
        label: const Text('退出登录', style: TextStyle(fontSize: AppTheme.fontMd)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.danger,
          side: const BorderSide(color: AppTheme.danger, width: 2),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定退出?'),
        content: const Text('退出后需要重新用手机号登录 (数据不受影响)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child:
                const Text('退出', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok != true) return;
      await ref.read(authProvider.notifier).logout();
      if (!context.mounted) return;
      context.go('/login');
    });
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

    return ProfileSection(
      title: '会员',
      icon: isMember ? Icons.workspace_premium : Icons.card_giftcard,
      hint: isMember ? '会员中' : '免费版',
      children: [
        if (isMember) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.verified, size: 26, color: AppTheme.primary),
                const SizedBox(width: 8),
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
            padding: EdgeInsets.only(top: 4, bottom: 8),
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
        ProfileTile(
          icon: Icons.shopping_cart_checkout,
          title: isMember ? '续费会员' : '开通会员',
          subtitle: '¥69 / 月 · 自动续费 ¥49 / 月',
          color: AppTheme.accent,
          onTap: () => _showPurchaseSheet(context, ref, isMember: isMember),
        ),
        if (m?.hasCode == true)
          _ReferralCodeRow(
            code: m!.referralCode!,
            onRefresh: () => ref.invalidate(meProfileProvider),
          ),
        // 还没被推荐过 → 给"填别人的码"的入口 (主人要: 注册时可选填; S0 先放在这里,
        // 等 W3 真实注册流程再把入口搬到注册页)
        ProfileTile(
          icon: Icons.redeem,
          title: '我有推荐码',
          subtitle: '填朋友的码, 你也能得 15 天会员',
          color: AppTheme.primaryDark,
          onTap: () => _showClaimCodeDialog(context, ref),
        ),
      ],
    );
  }

  /// S0 (还没接在线支付): 用大白话告诉用户怎么付钱
  /// S1 接微信/支付宝后, 这里换成"去支付"拉起收银台
  void _showPurchaseSheet(BuildContext context, WidgetRef ref,
      {required bool isMember}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMember ? '续费会员' : '开通会员',
              style: const TextStyle(
                fontSize: AppTheme.fontLg,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '¥69 / 月\n自动续费 ¥49 / 月 (连续包月更划算)',
              style: TextStyle(fontSize: AppTheme.fontMd, height: 1.6),
            ),
            const SizedBox(height: 12),
            const Text(
              '现在开通请把费用转给管理员 (支持收款码), 管理员会立刻给你开通;\n'
              '在线支付 (微信 / 支付宝) 马上上线, 上线后在这里一键续费。',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: AppTheme.buttonLgHeight,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('知道了', style: TextStyle(fontSize: AppTheme.fontMd)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 填推荐码弹层 (S0: 放在「我的」→ 会员卡里)
Future<void> _showClaimCodeDialog(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  var busy = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) {
        Future<void> submit() async {
          final code = ctrl.text.trim();
          if (code.isEmpty) return;
          setDlgState(() => busy = true);
          final r = await ref.read(billingServiceProvider).claimReferralCode(code);
          if (!ctx.mounted) return;
          setDlgState(() => busy = false);
          Navigator.of(ctx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(r.message, style: const TextStyle(fontSize: AppTheme.fontMd)),
            ),
          );
          if (r.ok) ref.invalidate(meProfileProvider);
        }

        return AlertDialog(
          title: const Text('填推荐码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '填朋友的 6 位推荐码, 你和朋友各得 15 天会员',
                style: TextStyle(fontSize: AppTheme.fontSm, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: AppTheme.fontXl,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: '6 位字母数字',
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
            ElevatedButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? '提交中...' : '确定',
                  style: const TextStyle(fontSize: AppTheme.fontMd)),
            ),
          ],
        );
      },
    ),
  );
  ctrl.dispose();
}

/// 我的推荐码 + 复制 (双向各得 15 天)
class _ReferralCodeRow extends StatelessWidget {
  final String code;
  final VoidCallback onRefresh;

  const _ReferralCodeRow({required this.code, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.group_add, size: 24, color: AppTheme.primaryDark),
              const SizedBox(width: 8),
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
                icon: const Icon(Icons.copy, size: 22),
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
            '朋友注册时填这个码, 双方各得 15 天会员',
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
