// ============================================
// 主题配色选择 (换肤) —— 「我的」→ 显示设置
// ============================================
//
// 为什么单独一个文件而不是塞进 profile_page.dart:
//   profile_page 已经 1400+ 行; 这个卡是令牌系统的第一个"官方消费方",
//   放一起能让「改 token → 换主题 → 看效果」这条链路自成一个可读单元。
//
// 只改**颜色**: 间距/字号/圆角是尺度, 不随主题变 (见 core/providers/theme_provider.dart 头注)。
//
// 预览: 每个主题给一个「真色块」(不是写死的示例色) —— 色块颜色取自 AppThemes.all 里的
//   该主题实例, 所以以后往 design-tokens.json 加主题, 这里零改动自动出现。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/theme_provider.dart';
import '../core/theme/tokens.g.dart';
import 'profile_widgets.dart';

class ThemePickerCard extends ConsumerWidget {
  const ThemePickerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeIdProvider);
    final tokens = ref.watch(activeTokensProvider);
    final groups = AppThemes.grouped;

    return ProfileSection(
      title: '主题配色',
      icon: Icons.palette_outlined,
      hint: '本机设置',
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s8),
          child: Text(
            '换个颜色看着舒服些 (选完立即生效, 全 App 都变)',
            style: TextStyle(
              fontSize: AppType.sm,
              color: tokens.textSecondary,
            ),
          ),
        ),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpace.s8,
              bottom: AppSpace.s4,
            ),
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: AppType.xs,
                fontWeight: AppWeight.medium,
                color: tokens.textTertiary,
              ),
            ),
          ),
          Wrap(
            spacing: AppSpace.s10,
            runSpacing: AppSpace.s10,
            children: [
              for (final t in entry.value)
                _ThemeChip(
                  theme: t,
                  selected: t.id == current,
                  onTap: () =>
                      ref.read(themeIdProvider.notifier).setTheme(t.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 单个主题选项 —— 色块用的是该主题自己的 primary/primaryLight/accent
/// ⚠ label 的 color 必须显式给 (见 app_theme.dart chipTheme 处的教训)
class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppTokens theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Semantics(
        button: true,
        selected: selected,
        label: '主题 ${theme.label}${selected ? ' (当前)' : ''}',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s12,
            vertical: AppSpace.s8,
          ),
          decoration: BoxDecoration(
            color: selected ? theme.primarySurface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? theme.primary : theme.border,
              width: selected ? AppSize.borderThick : AppSize.borderHairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(theme: theme),
              const SizedBox(width: AppSpace.s8),
              Text(
                theme.label,
                style: TextStyle(
                  fontSize: AppType.sm,
                  fontWeight:
                      selected ? AppWeight.semibold : AppWeight.regular,
                  // 选中态用 primaryDark (对 primarySurface 是 AAA), 未选用正文色
                  color: selected ? theme.primaryDark : theme.textPrimary,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: AppSpace.s4),
                Icon(Icons.check_circle,
                    size: AppSize.iconSm, color: theme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 三色预览块 (主色 / 浅色 / 强调色)
class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme});

  final AppTokens theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpace.s34,
      height: AppSpace.s22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.r6),
        border: Border.all(color: theme.border, width: AppSize.borderHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(flex: 5, child: ColoredBox(color: theme.primary)),
          Expanded(flex: 3, child: ColoredBox(color: theme.primaryLight)),
          Expanded(flex: 4, child: ColoredBox(color: theme.accent)),
        ],
      ),
    );
  }
}
