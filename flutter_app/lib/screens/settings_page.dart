// ============================================
// 设置页 —— 「我的」→ 设置 (`/profile/settings`)
// ============================================
// 为什么下沉: 「我的」页 11 个区块过多 (3~3.5 屏, 中老年用户滚到下面就焦躁);
//   把**低频 / 配置型**区块从「我的」分出来, 主页面只留"我在做什么 / 我下面有谁 / 我手机上的状态"
//   这条主线。字号 (中年刚需) 在「我的」保留快捷入口 + 这里也放 = 两处都能改。
//
// 区块顺序 (用 profileSectionGap 分隔):
//   1. 显示与存储 (字号 chips + 清理图片缓存) —— 共享 FontSizePicker
//   2. 主题配色 (换肤) —— ThemePickerCard
//   3. 提醒 (本地通知跟进) —— _ReminderCard
//   4. 关于与帮助 (版本/帮助/自检/admin/调试服务地址) —— _AboutCard + _VersionTile
//
// 视觉与「我的」页一致 (ProfileSection / ProfileTile / B2NoChrome),
// 行为完全沿用迁出前的实现, 不重写逻辑 —— 见 profile_page.dart 历史注释。

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/http/api_client.dart';
import '../core/providers/service_providers.dart';
import '../core/providers/settings_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/font_size_picker.dart';
import '../modules/follow_up/screens/follow_ups_page.dart';
import 'profile_sheets.dart';
import 'profile_widgets.dart';
import 'theme_picker_card.dart';

import '../core/theme/tokens.g.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        toolbarHeight: AppSize.appBarHeight,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 32),
        children: const [
          _DisplaySettingsSection(),
          profileSectionGap,
          ThemePickerCard(),
          _ReminderCard(),
          profileSectionGap,
          _AboutSection(),
          profileSectionGap,
        ],
      ),
    );
  }
}

// ============================================
// 1. 显示与存储 (字号 + 清理图片缓存)
// ============================================
// 字号 chip 复用 profile_widgets.dart 的 FontSizePicker (共享实现, 显式 color
// 防止 AGENTS §5 真机白字事故复发)。清理图片缓存 = 调用 flutter_cache_manager。

class _DisplaySettingsSection extends ConsumerStatefulWidget {
  const _DisplaySettingsSection();

  @override
  ConsumerState<_DisplaySettingsSection> createState() =>
      _DisplaySettingsSectionState();
}

class _DisplaySettingsSectionState
    extends ConsumerState<_DisplaySettingsSection> {
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
          padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s8),
          child: Text(
            '字大看不全 / 字小看不清? 选一档 (选完立即生效, 全 App 都变)',
            style: TextStyle(
                fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
          ),
        ),
        // 共享字号 chips (与「我的」页显示一致; 改一处即两处生效)
        FontSizePicker(
          selected: fontSize,
          onChanged: (v) =>
              ref.read(settingsProvider.notifier).setFontSize(v),
        ),
        const SizedBox(height: AppSpace.s8),
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
// 2. 提醒 (本地通知; 行为完全沿用 profile_page._ReminderCard)
// ============================================
// 开关语义: 开了就真排程, 关了真取消 —— 不做"假开关"。
//   开: 先要系统权限 (被拒 → 开关弹回 + 提示去系统设置, 不假装成功)
//   数字: 用当前待办数 (pendingFollowUpsProvider)
//   保活: 待办数变了就重排。

class _ReminderCard extends ConsumerStatefulWidget {
  const _ReminderCard();

  @override
  ConsumerState<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends ConsumerState<_ReminderCard> {
  bool _busy = false;

  int get _dueCount =>
      ref.read(pendingFollowUpsProvider).valueOrNull?.length ?? 0;

  Future<void> _toggle(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    final settings = ref.read(settingsProvider.notifier);
    final reminder = ref.read(followUpReminderProvider);
    try {
      if (enabled) {
        final granted = await reminder.requestPermission();
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '没有通知权限, 请在手机「设置 → 应用 → 暖客宝 → 通知」里打开',
                  style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
          );
          return; // 权限没给 → 开关保持关闭 (不假装打开)
        }
        await reminder.scheduleDaily(dueCount: _dueCount);
      } else {
        await reminder.cancel();
      }
      await settings.setFollowUpReminder(enabled);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('设置失败: $e',
              style: const TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(settingsProvider).followUpReminder;

    // 待办数变了 (比如刚完成一条) → 重排, 让通知正文跟上
    ref.listen(pendingFollowUpsProvider, (prev, next) {
      final n = next.valueOrNull?.length;
      if (n == null || !ref.read(settingsProvider).followUpReminder) return;
      ref.read(followUpReminderProvider).scheduleDaily(dueCount: n);
    });

    return ProfileSection(
      title: '提醒',
      icon: Icons.notifications_active_outlined,
      hint: '本机设置',
      children: [
        SwitchListTile(
          value: on,
          onChanged: _busy ? null : _toggle,
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            on ? Icons.notifications_active : Icons.notifications_off_outlined,
            color: on ? AppTheme.primary : AppTheme.textSecondary,
          ),
          title: const Text(
            '每天 08:30 提醒跟进',
            style: TextStyle(
                fontSize: AppTheme.fontMd, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            on
                ? '到点提醒「今天要跟进谁」, 点开直达待办页'
                : '打开后每天早上提醒一次, 不漏跟进',
            style: const TextStyle(
                fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ============================================
// 3. 关于与帮助 (行为完全沿用 profile_page._AboutCard + _VersionTile)
// ============================================

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProfileSection(
      title: '关于与帮助',
      icon: Icons.info_outline,
      children: [
        const _VersionTile(),
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
        // 管理员工具: 只有 admin 角色能看见 (内测人工收款核销 + 设置收款码)
        // 客户端只是隐藏入口; 服务端每次写操作重新查 role
        if (ref.watch(meProfileProvider).valueOrNull?.user?.role == 'admin')
          ProfileTile(
            icon: Icons.admin_panel_settings_outlined,
            title: '管理员工具',
            subtitle: '用户管理 · 收款码设置 · 付款申请核销',
            color: AppTheme.danger,
            onTap: () => context.push('/profile/admin'),
          ),
        // debug-only: 生产用户看到 IP 只会困惑
        if (kDebugMode)
          ProfileTile(
            icon: Icons.dns_outlined,
            title: '服务地址 (调试)',
            subtitle: ApiClient.baseUrl,
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: AppSize.iconMd),
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
