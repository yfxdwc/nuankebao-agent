// GENERATED FILE — 请勿手改。
//
// 源:      design/tokens/design-tokens.json
// 重新生成: pnpm tokens:build
// 校验:     pnpm tokens:check (CI / pre-commit)
//
// 分层:
//   AppPalette   L0 原始调色板 —— 全项目唯一允许出现字面 hex 的地方(的镜像)
//   AppSpace/…   L1 尺度       —— 间距 / 圆角 / 字号 / 尺寸 / 层次 / 时长 / 透明度
//   AppTokens    L2 语义令牌   —— 每个主题一份实例 (运行时可变)
//   AppThemes    主题目录      —— 运行时换肤的入口
//
// ⚠ 运行时换肤: 业务代码要读 `context.tokens.primary`, **不要**读 AppThemes.sage.primary ——
//   后者写死了默认主题, 换肤不会生效。

import 'package:flutter/material.dart';

/// L0 原始调色板 (不等于语义 —— 业务代码不该直接用, 用 AppTokens)
abstract final class AppPalette {
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFFFFBF5);
  static const Color neutral100 = Color(0xFFF7F2EA);
  static const Color neutral200 = Color(0xFFEDE6DA);
  static const Color neutral300 = Color(0xFFE0E0E0);
  static const Color neutral400 = Color(0xFFD0D0D0);
  static const Color neutral500 = Color(0xFF8A8A8A);
  static const Color neutral600 = Color(0xFF6B6B6B);
  static const Color neutral700 = Color(0xFF4A4A4A);
  static const Color neutral800 = Color(0xFF2E2E2E);
  static const Color neutral900 = Color(0xFF1A1A1A);
  static const Color neutral950 = Color(0xFF0F0F0F);
  static const Color green50 = Color(0xFFF0F7F2);
  static const Color green100 = Color(0xFFE9F4EE);
  static const Color green200 = Color(0xFFA8D5BA);
  static const Color green300 = Color(0xFF7CBF97);
  static const Color green400 = Color(0xFF5E9E78);
  static const Color green500 = Color(0xFF4A7C59);
  static const Color green600 = Color(0xFF3D6849);
  static const Color green700 = Color(0xFF2D5A3D);
  static const Color green800 = Color(0xFF234631);
  static const Color green900 = Color(0xFF17301F);
  static const Color amber50 = Color(0xFFFDF6EC);
  static const Color amber100 = Color(0xFFFAE9D0);
  static const Color amber200 = Color(0xFFF5D5A8);
  static const Color amber300 = Color(0xFFEFBF80);
  static const Color amber400 = Color(0xFFECAF65);
  static const Color amber500 = Color(0xFFE89F4D);
  static const Color amber600 = Color(0xFFD08A38);
  static const Color amber700 = Color(0xFFA86E2B);
  static const Color amber800 = Color(0xFF8A5A1F);
  static const Color amber900 = Color(0xFF6B4415);
  static const Color yellow100 = Color(0xFFFFF3CD);
  static const Color yellow200 = Color(0xFFFFE8A3);
  static const Color yellow500 = Color(0xFFD9B23D);
  static const Color yellow600 = Color(0xFFC89A2B);
  static const Color yellow700 = Color(0xFF8A6D1F);
  static const Color yellow900 = Color(0xFF5C4712);
  static const Color red50 = Color(0xFFFFF5F5);
  static const Color red100 = Color(0xFFFBDDDD);
  static const Color red300 = Color(0xFFE08A8A);
  static const Color red500 = Color(0xFFD3545C);
  static const Color red600 = Color(0xFFB33A3A);
  static const Color red700 = Color(0xFF8F2E2E);
  static const Color blue50 = Color(0xFFEDF4FB);
  static const Color blue100 = Color(0xFFE3EDF8);
  static const Color blue500 = Color(0xFF2B6CB0);
  static const Color blue700 = Color(0xFF1F4E80);
  static const Color purple50 = Color(0xFFF5F0F8);
  static const Color purple100 = Color(0xFFEFE7F4);
  static const Color purple500 = Color(0xFF8E5BA8);
  static const Color purple700 = Color(0xFF6D4282);
  static const Color pink500 = Color(0xFFC2185B);
  static const Color spring500 = Color(0xFF5A7D3C);
  static const Color spring200 = Color(0xFFC3DFA6);
  static const Color spring700 = Color(0xFF3D5A28);
  static const Color spring50 = Color(0xFFF2F8EB);
  static const Color springAccent500 = Color(0xFFB3536C);
  static const Color springAccent100 = Color(0xFFF0D2DB);
  static const Color springAccent50 = Color(0xFFFDF1F5);
  static const Color summer500 = Color(0xFF2F7A72);
  static const Color summer200 = Color(0xFFA6D6CE);
  static const Color summer700 = Color(0xFF1F574F);
  static const Color summer50 = Color(0xFFEEF7F5);
  static const Color summerAccent500 = Color(0xFFB07E1E);
  static const Color summerAccent100 = Color(0xFFF0E0B8);
  static const Color summerAccent50 = Color(0xFFFBF6E9);
  static const Color autumn500 = Color(0xFFA65E24);
  static const Color autumn200 = Color(0xFFE8C79E);
  static const Color autumn700 = Color(0xFF7A421A);
  static const Color autumn50 = Color(0xFFFBF2E7);
  static const Color autumnAccent500 = Color(0xFFA9791F);
  static const Color autumnAccent100 = Color(0xFFEFDDAE);
  static const Color autumnAccent50 = Color(0xFFFAF4E4);
  static const Color winter500 = Color(0xFF8C4A4A);
  static const Color winter200 = Color(0xFFDFB9B9);
  static const Color winter700 = Color(0xFF632F2F);
  static const Color winter50 = Color(0xFFFAF1F1);
  static const Color winterAccent500 = Color(0xFF4A6E8C);
  static const Color winterAccent100 = Color(0xFFCBDCE9);
  static const Color winterAccent50 = Color(0xFFF0F5F9);
  static const Color amber25 = Color(0xFFFFF8E8);
  static const Color brown400 = Color(0xFF8D6E63);
  static const Color green450 = Color(0xFF6B9E7A);
  static const Color teal500 = Color(0xFF2F7D6F);
  static const Color indigo500 = Color(0xFF5C6BC0);
  static const Color neutralCool500 = Color(0xFF9AA5A0);
  static const Color spring800 = Color(0xFF2F4620);
  static const Color summer800 = Color(0xFF16403B);
  static const Color autumn800 = Color(0xFF5C3113);
  static const Color winter800 = Color(0xFF4A2222);
}

/// L1 尺度 —— 间距 (中老年友好: 主档 8/12/16, 触控留白充足)
abstract final class AppSpace {
  static const double s0 = 0.0;
  static const double s2 = 2.0;
  static const double s4 = 4.0;
  static const double s6 = 6.0;
  static const double s8 = 8.0;
  static const double s10 = 10.0;
  static const double s12 = 12.0;
  static const double s14 = 14.0;
  static const double s16 = 16.0;
  static const double s18 = 18.0;
  static const double s20 = 20.0;
  static const double s21 = 21.0;
  static const double s22 = 22.0;
  static const double s24 = 24.0;
  static const double s26 = 26.0;
  static const double s28 = 28.0;
  static const double s32 = 32.0;
  static const double s34 = 34.0;
  static const double s40 = 40.0;
  static const double s44 = 44.0;
  static const double s48 = 48.0;
  static const double s52 = 52.0;
  static const double s56 = 56.0;
  static const double s60 = 60.0;
  static const double s64 = 64.0;
  static const double s72 = 72.0;
  static const double s76 = 76.0;
  static const double s80 = 80.0;
  static const double s84 = 84.0;
  static const double s88 = 88.0;
  static const double s90 = 90.0;
  static const double s96 = 96.0;
  static const double s100 = 100.0;
  static const double s120 = 120.0;
  static const double s200 = 200.0;
  static const double s220 = 220.0;
  // 语义别名
  static const double pagePadding = s16;
  static const double cardPadding = s14;
  static const double cardGap = s10;
  static const double sectionGap = s20;
  static const double inlineGap = s8;
  static const double tightGap = s4;
  static const double listRowPadding = s14;
  static const double formFieldGap = s10;
  static const double bottomSafeGap = s64;
}

/// L1 尺度 —— 圆角
abstract final class AppRadius {
  static const double r0 = 0.0;
  static const double r3 = 3.0;
  static const double r4 = 4.0;
  static const double r6 = 6.0;
  static const double r8 = 8.0;
  static const double r10 = 10.0;
  static const double r12 = 12.0;
  static const double r14 = 14.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r22 = 22.0;
  static const double r24 = 24.0;
  static const double r28 = 28.0;
  static const double r32 = 32.0;
  static const double r40 = 40.0;
  static const double full = 999.0;
  static const double r2 = 2.0;
  // 语义别名
  static const double card = r10;
  static const double button = r8;
  static const double input = r8;
  static const double chip = full;
  static const double badge = r4;
  static const double sheet = r16;
  static const double dialog = r14;
  static const double pill = full;
}

/// L1 尺度 —— 字号 (中老年: 正文 18 起步, Material 默认是 14)
abstract final class AppType {
  static const double micro = 11.0;
  static const double xs = 12.0;
  static const double sm = 13.0;
  static const double md = 15.0;
  static const double lg = 17.0;
  static const double xl = 20.0;
  static const double xxl = 28.0;
}

/// L1 尺度 —— 字重
abstract final class AppWeight {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}

/// L1 尺度 —— 组件尺寸
abstract final class AppSize {
  static const double iconXs = 16.0;
  static const double iconSm = 16.0;
  static const double iconMd = 20.0;
  static const double iconLg = 24.0;
  static const double iconXl = 28.0;
  static const double controlSm = 32.0;
  static const double controlMd = 34.0;
  static const double controlLg = 44.0;
  static const double tapCompact = 44.0;
  static const double tapMin = 48.0;
  static const double buttonMinHeight = 40.0;
  static const double buttonLgHeight = 48.0;
  static const double fieldLg = 52.0;
  static const double fabSize = 56.0;
  static const double listRowHeight = 60.0;
  static const double avatarSm = 32.0;
  static const double avatarMd = 44.0;
  static const double avatarLg = 64.0;
  static const double appBarHeight = 52.0;
  static const double borderHairline = 1.0;
  static const double borderThick = 2.0;
  static const double badgeMinWidth = 16.0;
  static const double badgeMinWidthLg = 18.0;
  static const double textareaMinHeight = 72.0;
  static const double tableMinWidth = 720.0;
  static const double contentMaxWidth = 720.0;
}

/// L1 尺度 —— 阴影层次 (Material elevation)
abstract final class AppElevation {
  static const double e0 = 0.0;
  static const double e1 = 1.0;
  static const double e2 = 2.0;
  static const double e3 = 4.0;
  static const double e4 = 8.0;
}

/// L1 尺度 —— 动效时长 (毫秒)
abstract final class AppDuration {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration slower = Duration(milliseconds: 480);
}

/// L1 尺度 —— 透明度
abstract final class AppOpacity {
  static const double disabled = 0.38;
  static const double muted = 0.62;
  static const double hover = 0.08;
  static const double overlay = 0.48;
  static const double scrim = 0.32;
}

/// L2 语义令牌 —— **跨主题不变**的那部分 (中性色 / 文字色 / 状态色 / 图谱色)
///
/// 为什么这层是 const 而不是 context.tokens:
///   design-tokens.json 的规则是「themes 只覆盖品牌槽, 中性/文字/状态色在 shared 里共用」——
///   也就是说这些颜色**本来就不随换肤变**。做成常量后, 存量代码里大量
///   `const TextStyle(color: Color(0xFF8A8A8A))` 能直接换成 `AppColors.textTertiary`,
///   既不用拿 context, 也不会因为少写 const 而丢编译期优化。
///
/// 判定是自动的 (见生成器): 把某个槽从 shared 挪进 themes, 它就自动降级成运行时令牌。
abstract final class AppColors {
  static const Color surface = Color(0xFFFFFBF5);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF7F2EA);
  static const Color surfaceSunken = Color(0xFFEDE6DA);
  static const Color surfaceInverse = Color(0xFF1A1A1A);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF4A4A4A);
  static const Color textTertiary = Color(0xFF6B6B6B);
  static const Color textDisabled = Color(0xFF8A8A8A);
  static const Color textOnInverse = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFD0D0D0);
  static const Color borderStrong = Color(0xFF8A8A8A);
  static const Color borderInput = Color(0xFFD0D0D0);
  static const Color divider = Color(0xFFEDE6DA);
  static const Color success = Color(0xFF2D5A3D);
  static const Color successLight = Color(0xFFA8D5BA);
  static const Color successSurface = Color(0xFFF0F7F2);
  static const Color warning = Color(0xFF8A6D1F);
  static const Color warningLight = Color(0xFFFFE8A3);
  static const Color warningSurface = Color(0xFFFFF3CD);
  static const Color danger = Color(0xFFB33A3A);
  static const Color dangerLight = Color(0xFFE08A8A);
  static const Color dangerSurface = Color(0xFFFFF5F5);
  static const Color info = Color(0xFF1F4E80);
  static const Color infoLight = Color(0xFFE3EDF8);
  static const Color infoSurface = Color(0xFFEDF4FB);
  static const Color memberGold = Color(0xFFC89A2B);
  static const Color memberGoldSurface = Color(0xFFFFF3CD);
  static const Color badgeNeutral = Color(0xFF6B6B6B);
  static const Color badgeNeutralSurface = Color(0xFFEDE6DA);
  static const Color graphFranchiseeB = Color(0xFF8E5BA8);
  static const Color graphFranchiseeBSurface = Color(0xFFF5F0F8);
  static const Color graphFranchiseeA = Color(0xFF2B6CB0);
  static const Color graphFranchiseeASurface = Color(0xFFEDF4FB);
  static const Color graphLine = Color(0xFFD0D0D0);
  static const Color graphLineSoft = Color(0xFFEDE6DA);
  static const Color shadowColor = Color(0xFF000000);
  static const Color scrim = Color(0xFF0F0F0F);
  static const Color accentSurfaceWarm = Color(0xFFFFF8E8);
  static const Color salonWaitlist = Color(0xFF5C6BC0);
  static const Color salonNeutral = Color(0xFF8A8A8A);
  static const Color warningDark = Color(0xFF8A5A1F);
  static const Color memberGoldLight = Color(0xFFD9B23D);
  static const Color dangerBright = Color(0xFFD3545C);
  static const Color avatarSlot1 = Color(0xFF4A7C59);
  static const Color avatarSlot2 = Color(0xFFC2185B);
  static const Color avatarSlot3 = Color(0xFF8D6E63);
  static const Color avatarSlot4 = Color(0xFF2F7D6F);
  static const Color avatarSlot5 = Color(0xFFD3545C);
  static const Color avatarSlot6 = Color(0xFFE89F4D);
  static const Color avatarSlot7 = Color(0xFF6B9E7A);
  static const Color avatarSlot8 = Color(0xFF2B6CB0);
  static const Color avatarSlotNeutral = Color(0xFF9AA5A0);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color onWarning = Color(0xFFFFFFFF);
  static const Color onDanger = Color(0xFFFFFFFF);
  static const Color onInfo = Color(0xFFFFFFFF);
}

/// 随主题变化的品牌槽 —— 只能用 `context.tokens.<名>` (取到当前主题的值)
///
/// 共 9 个: focusRing, primary, primaryLight, primaryDark, primarySurface, accent, accentLight, accentSurface, onAccent
const List<String> kThemeVariantTokenKeys = <String>[
  'focusRing',
  'primary',
  'primaryLight',
  'primaryDark',
  'primarySurface',
  'accent',
  'accentLight',
  'accentSurface',
  'onAccent',
  'id', 'label', 'group',
];

/// L2 语义令牌 —— 一个主题一份 (运行时可变, 用于换肤)
///
/// 取用方式 (业务代码唯一正确姿势):
///   `context.tokens.primary`   ← 见 core/theme/theme_ext.dart
@immutable
class AppTokens {
  final String id;
  final String label;
  final String group;
  final Color surface;
  final Color surfaceCard;
  final Color surfaceSubtle;
  final Color surfaceSunken;
  final Color surfaceInverse;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color textOnInverse;
  final Color border;
  final Color borderStrong;
  final Color borderInput;
  final Color divider;
  final Color focusRing;
  final Color success;
  final Color successLight;
  final Color successSurface;
  final Color warning;
  final Color warningLight;
  final Color warningSurface;
  final Color danger;
  final Color dangerLight;
  final Color dangerSurface;
  final Color info;
  final Color infoLight;
  final Color infoSurface;
  final Color memberGold;
  final Color memberGoldSurface;
  final Color badgeNeutral;
  final Color badgeNeutralSurface;
  final Color graphFranchiseeB;
  final Color graphFranchiseeBSurface;
  final Color graphFranchiseeA;
  final Color graphFranchiseeASurface;
  final Color graphLine;
  final Color graphLineSoft;
  final Color shadowColor;
  final Color scrim;
  final Color accentSurfaceWarm;
  final Color salonWaitlist;
  final Color salonNeutral;
  final Color warningDark;
  final Color memberGoldLight;
  final Color dangerBright;
  final Color avatarSlot1;
  final Color avatarSlot2;
  final Color avatarSlot3;
  final Color avatarSlot4;
  final Color avatarSlot5;
  final Color avatarSlot6;
  final Color avatarSlot7;
  final Color avatarSlot8;
  final Color avatarSlotNeutral;
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color primarySurface;
  final Color accent;
  final Color accentLight;
  final Color accentSurface;
  final Color onPrimary;
  final Color onAccent;
  final Color onSuccess;
  final Color onWarning;
  final Color onDanger;
  final Color onInfo;

  const AppTokens({
    required this.id,
    required this.label,
    required this.group,
    required this.surface,
    required this.surfaceCard,
    required this.surfaceSubtle,
    required this.surfaceSunken,
    required this.surfaceInverse,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnInverse,
    required this.border,
    required this.borderStrong,
    required this.borderInput,
    required this.divider,
    required this.focusRing,
    required this.success,
    required this.successLight,
    required this.successSurface,
    required this.warning,
    required this.warningLight,
    required this.warningSurface,
    required this.danger,
    required this.dangerLight,
    required this.dangerSurface,
    required this.info,
    required this.infoLight,
    required this.infoSurface,
    required this.memberGold,
    required this.memberGoldSurface,
    required this.badgeNeutral,
    required this.badgeNeutralSurface,
    required this.graphFranchiseeB,
    required this.graphFranchiseeBSurface,
    required this.graphFranchiseeA,
    required this.graphFranchiseeASurface,
    required this.graphLine,
    required this.graphLineSoft,
    required this.shadowColor,
    required this.scrim,
    required this.accentSurfaceWarm,
    required this.salonWaitlist,
    required this.salonNeutral,
    required this.warningDark,
    required this.memberGoldLight,
    required this.dangerBright,
    required this.avatarSlot1,
    required this.avatarSlot2,
    required this.avatarSlot3,
    required this.avatarSlot4,
    required this.avatarSlot5,
    required this.avatarSlot6,
    required this.avatarSlot7,
    required this.avatarSlot8,
    required this.avatarSlotNeutral,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primarySurface,
    required this.accent,
    required this.accentLight,
    required this.accentSurface,
    required this.onPrimary,
    required this.onAccent,
    required this.onSuccess,
    required this.onWarning,
    required this.onDanger,
    required this.onInfo,
  });

  /// 这个主题的对比度体检 (供设置页 / 测试用)
  Map<String, double> contrastReport() => <String, double>{
    'primary/onPrimary': _ratio(primary, onPrimary),
    'accent/onAccent': _ratio(accent, onAccent),
    'textPrimary/surface': _ratio(textPrimary, surface),
    'textSecondary/surface': _ratio(textSecondary, surface),
    'textPrimary/surfaceCard': _ratio(textPrimary, surfaceCard),
    'border/surfaceCard': _ratio(border, surfaceCard),
  };

  static double _ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// 主题目录 —— 运行时换肤的入口
///
/// ⚠ 业务代码不要直接读 `AppThemes.sage.primary` (写死了默认主题, 换肤不生效);
///   要读 `context.tokens.primary`。AppThemes 只在【装配 ThemeData】和【设置页列选项】两处用。
abstract final class AppThemes {
  /// 养生绿 (品牌) — 默认主题
  static const AppTokens sage = AppTokens(
    id: 'sage',
    label: '养生绿',
    group: '品牌',
    surface: Color(0xFFFFFBF5),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF7F2EA),
    surfaceSunken: Color(0xFFEDE6DA),
    surfaceInverse: Color(0xFF1A1A1A),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF4A4A4A),
    textTertiary: Color(0xFF6B6B6B),
    textDisabled: Color(0xFF8A8A8A),
    textOnInverse: Color(0xFFFFFFFF),
    border: Color(0xFFD0D0D0),
    borderStrong: Color(0xFF8A8A8A),
    borderInput: Color(0xFFD0D0D0),
    divider: Color(0xFFEDE6DA),
    focusRing: Color(0xFF4A7C59),
    success: Color(0xFF2D5A3D),
    successLight: Color(0xFFA8D5BA),
    successSurface: Color(0xFFF0F7F2),
    warning: Color(0xFF8A6D1F),
    warningLight: Color(0xFFFFE8A3),
    warningSurface: Color(0xFFFFF3CD),
    danger: Color(0xFFB33A3A),
    dangerLight: Color(0xFFE08A8A),
    dangerSurface: Color(0xFFFFF5F5),
    info: Color(0xFF1F4E80),
    infoLight: Color(0xFFE3EDF8),
    infoSurface: Color(0xFFEDF4FB),
    memberGold: Color(0xFFC89A2B),
    memberGoldSurface: Color(0xFFFFF3CD),
    badgeNeutral: Color(0xFF6B6B6B),
    badgeNeutralSurface: Color(0xFFEDE6DA),
    graphFranchiseeB: Color(0xFF8E5BA8),
    graphFranchiseeBSurface: Color(0xFFF5F0F8),
    graphFranchiseeA: Color(0xFF2B6CB0),
    graphFranchiseeASurface: Color(0xFFEDF4FB),
    graphLine: Color(0xFFD0D0D0),
    graphLineSoft: Color(0xFFEDE6DA),
    shadowColor: Color(0xFF000000),
    scrim: Color(0xFF0F0F0F),
    accentSurfaceWarm: Color(0xFFFFF8E8),
    salonWaitlist: Color(0xFF5C6BC0),
    salonNeutral: Color(0xFF8A8A8A),
    warningDark: Color(0xFF8A5A1F),
    memberGoldLight: Color(0xFFD9B23D),
    dangerBright: Color(0xFFD3545C),
    avatarSlot1: Color(0xFF4A7C59),
    avatarSlot2: Color(0xFFC2185B),
    avatarSlot3: Color(0xFF8D6E63),
    avatarSlot4: Color(0xFF2F7D6F),
    avatarSlot5: Color(0xFFD3545C),
    avatarSlot6: Color(0xFFE89F4D),
    avatarSlot7: Color(0xFF6B9E7A),
    avatarSlot8: Color(0xFF2B6CB0),
    avatarSlotNeutral: Color(0xFF9AA5A0),
    primary: Color(0xFF4A7C59),
    primaryLight: Color(0xFFA8D5BA),
    primaryDark: Color(0xFF2D5A3D),
    primarySurface: Color(0xFFF0F7F2),
    accent: Color(0xFFE89F4D),
    accentLight: Color(0xFFFAE9D0),
    accentSurface: Color(0xFFFDF6EC),
    onPrimary: Color(0xFFFFFFFF),
    onAccent: Color(0xFF1A1A1A),
    onSuccess: Color(0xFFFFFFFF),
    onWarning: Color(0xFFFFFFFF),
    onDanger: Color(0xFFFFFFFF),
    onInfo: Color(0xFFFFFFFF),
  );

  /// 春 · 新芽 (季节)
  static const AppTokens spring = AppTokens(
    id: 'spring',
    label: '春 · 新芽',
    group: '季节',
    surface: Color(0xFFFFFBF5),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF7F2EA),
    surfaceSunken: Color(0xFFEDE6DA),
    surfaceInverse: Color(0xFF1A1A1A),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF4A4A4A),
    textTertiary: Color(0xFF6B6B6B),
    textDisabled: Color(0xFF8A8A8A),
    textOnInverse: Color(0xFFFFFFFF),
    border: Color(0xFFD0D0D0),
    borderStrong: Color(0xFF8A8A8A),
    borderInput: Color(0xFFD0D0D0),
    divider: Color(0xFFEDE6DA),
    focusRing: Color(0xFF5A7D3C),
    success: Color(0xFF2D5A3D),
    successLight: Color(0xFFA8D5BA),
    successSurface: Color(0xFFF0F7F2),
    warning: Color(0xFF8A6D1F),
    warningLight: Color(0xFFFFE8A3),
    warningSurface: Color(0xFFFFF3CD),
    danger: Color(0xFFB33A3A),
    dangerLight: Color(0xFFE08A8A),
    dangerSurface: Color(0xFFFFF5F5),
    info: Color(0xFF1F4E80),
    infoLight: Color(0xFFE3EDF8),
    infoSurface: Color(0xFFEDF4FB),
    memberGold: Color(0xFFC89A2B),
    memberGoldSurface: Color(0xFFFFF3CD),
    badgeNeutral: Color(0xFF6B6B6B),
    badgeNeutralSurface: Color(0xFFEDE6DA),
    graphFranchiseeB: Color(0xFF8E5BA8),
    graphFranchiseeBSurface: Color(0xFFF5F0F8),
    graphFranchiseeA: Color(0xFF2B6CB0),
    graphFranchiseeASurface: Color(0xFFEDF4FB),
    graphLine: Color(0xFFD0D0D0),
    graphLineSoft: Color(0xFFEDE6DA),
    shadowColor: Color(0xFF000000),
    scrim: Color(0xFF0F0F0F),
    accentSurfaceWarm: Color(0xFFFFF8E8),
    salonWaitlist: Color(0xFF5C6BC0),
    salonNeutral: Color(0xFF8A8A8A),
    warningDark: Color(0xFF8A5A1F),
    memberGoldLight: Color(0xFFD9B23D),
    dangerBright: Color(0xFFD3545C),
    avatarSlot1: Color(0xFF4A7C59),
    avatarSlot2: Color(0xFFC2185B),
    avatarSlot3: Color(0xFF8D6E63),
    avatarSlot4: Color(0xFF2F7D6F),
    avatarSlot5: Color(0xFFD3545C),
    avatarSlot6: Color(0xFFE89F4D),
    avatarSlot7: Color(0xFF6B9E7A),
    avatarSlot8: Color(0xFF2B6CB0),
    avatarSlotNeutral: Color(0xFF9AA5A0),
    primary: Color(0xFF5A7D3C),
    primaryLight: Color(0xFFC3DFA6),
    primaryDark: Color(0xFF3D5A28),
    primarySurface: Color(0xFFF2F8EB),
    accent: Color(0xFFB3536C),
    accentLight: Color(0xFFF0D2DB),
    accentSurface: Color(0xFFFDF1F5),
    onPrimary: Color(0xFFFFFFFF),
    onAccent: Color(0xFFFFFFFF),
    onSuccess: Color(0xFFFFFFFF),
    onWarning: Color(0xFFFFFFFF),
    onDanger: Color(0xFFFFFFFF),
    onInfo: Color(0xFFFFFFFF),
  );

  /// 夏 · 青荷 (季节)
  static const AppTokens summer = AppTokens(
    id: 'summer',
    label: '夏 · 青荷',
    group: '季节',
    surface: Color(0xFFFFFBF5),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF7F2EA),
    surfaceSunken: Color(0xFFEDE6DA),
    surfaceInverse: Color(0xFF1A1A1A),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF4A4A4A),
    textTertiary: Color(0xFF6B6B6B),
    textDisabled: Color(0xFF8A8A8A),
    textOnInverse: Color(0xFFFFFFFF),
    border: Color(0xFFD0D0D0),
    borderStrong: Color(0xFF8A8A8A),
    borderInput: Color(0xFFD0D0D0),
    divider: Color(0xFFEDE6DA),
    focusRing: Color(0xFF2F7A72),
    success: Color(0xFF2D5A3D),
    successLight: Color(0xFFA8D5BA),
    successSurface: Color(0xFFF0F7F2),
    warning: Color(0xFF8A6D1F),
    warningLight: Color(0xFFFFE8A3),
    warningSurface: Color(0xFFFFF3CD),
    danger: Color(0xFFB33A3A),
    dangerLight: Color(0xFFE08A8A),
    dangerSurface: Color(0xFFFFF5F5),
    info: Color(0xFF1F4E80),
    infoLight: Color(0xFFE3EDF8),
    infoSurface: Color(0xFFEDF4FB),
    memberGold: Color(0xFFC89A2B),
    memberGoldSurface: Color(0xFFFFF3CD),
    badgeNeutral: Color(0xFF6B6B6B),
    badgeNeutralSurface: Color(0xFFEDE6DA),
    graphFranchiseeB: Color(0xFF8E5BA8),
    graphFranchiseeBSurface: Color(0xFFF5F0F8),
    graphFranchiseeA: Color(0xFF2B6CB0),
    graphFranchiseeASurface: Color(0xFFEDF4FB),
    graphLine: Color(0xFFD0D0D0),
    graphLineSoft: Color(0xFFEDE6DA),
    shadowColor: Color(0xFF000000),
    scrim: Color(0xFF0F0F0F),
    accentSurfaceWarm: Color(0xFFFFF8E8),
    salonWaitlist: Color(0xFF5C6BC0),
    salonNeutral: Color(0xFF8A8A8A),
    warningDark: Color(0xFF8A5A1F),
    memberGoldLight: Color(0xFFD9B23D),
    dangerBright: Color(0xFFD3545C),
    avatarSlot1: Color(0xFF4A7C59),
    avatarSlot2: Color(0xFFC2185B),
    avatarSlot3: Color(0xFF8D6E63),
    avatarSlot4: Color(0xFF2F7D6F),
    avatarSlot5: Color(0xFFD3545C),
    avatarSlot6: Color(0xFFE89F4D),
    avatarSlot7: Color(0xFF6B9E7A),
    avatarSlot8: Color(0xFF2B6CB0),
    avatarSlotNeutral: Color(0xFF9AA5A0),
    primary: Color(0xFF2F7A72),
    primaryLight: Color(0xFFA6D6CE),
    primaryDark: Color(0xFF1F574F),
    primarySurface: Color(0xFFEEF7F5),
    accent: Color(0xFFB07E1E),
    accentLight: Color(0xFFF0E0B8),
    accentSurface: Color(0xFFFBF6E9),
    onPrimary: Color(0xFFFFFFFF),
    onAccent: Color(0xFF1A1A1A),
    onSuccess: Color(0xFFFFFFFF),
    onWarning: Color(0xFFFFFFFF),
    onDanger: Color(0xFFFFFFFF),
    onInfo: Color(0xFFFFFFFF),
  );

  /// 秋 · 琥珀 (季节)
  static const AppTokens autumn = AppTokens(
    id: 'autumn',
    label: '秋 · 琥珀',
    group: '季节',
    surface: Color(0xFFFFFBF5),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF7F2EA),
    surfaceSunken: Color(0xFFEDE6DA),
    surfaceInverse: Color(0xFF1A1A1A),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF4A4A4A),
    textTertiary: Color(0xFF6B6B6B),
    textDisabled: Color(0xFF8A8A8A),
    textOnInverse: Color(0xFFFFFFFF),
    border: Color(0xFFD0D0D0),
    borderStrong: Color(0xFF8A8A8A),
    borderInput: Color(0xFFD0D0D0),
    divider: Color(0xFFEDE6DA),
    focusRing: Color(0xFFA65E24),
    success: Color(0xFF2D5A3D),
    successLight: Color(0xFFA8D5BA),
    successSurface: Color(0xFFF0F7F2),
    warning: Color(0xFF8A6D1F),
    warningLight: Color(0xFFFFE8A3),
    warningSurface: Color(0xFFFFF3CD),
    danger: Color(0xFFB33A3A),
    dangerLight: Color(0xFFE08A8A),
    dangerSurface: Color(0xFFFFF5F5),
    info: Color(0xFF1F4E80),
    infoLight: Color(0xFFE3EDF8),
    infoSurface: Color(0xFFEDF4FB),
    memberGold: Color(0xFFC89A2B),
    memberGoldSurface: Color(0xFFFFF3CD),
    badgeNeutral: Color(0xFF6B6B6B),
    badgeNeutralSurface: Color(0xFFEDE6DA),
    graphFranchiseeB: Color(0xFF8E5BA8),
    graphFranchiseeBSurface: Color(0xFFF5F0F8),
    graphFranchiseeA: Color(0xFF2B6CB0),
    graphFranchiseeASurface: Color(0xFFEDF4FB),
    graphLine: Color(0xFFD0D0D0),
    graphLineSoft: Color(0xFFEDE6DA),
    shadowColor: Color(0xFF000000),
    scrim: Color(0xFF0F0F0F),
    accentSurfaceWarm: Color(0xFFFFF8E8),
    salonWaitlist: Color(0xFF5C6BC0),
    salonNeutral: Color(0xFF8A8A8A),
    warningDark: Color(0xFF8A5A1F),
    memberGoldLight: Color(0xFFD9B23D),
    dangerBright: Color(0xFFD3545C),
    avatarSlot1: Color(0xFF4A7C59),
    avatarSlot2: Color(0xFFC2185B),
    avatarSlot3: Color(0xFF8D6E63),
    avatarSlot4: Color(0xFF2F7D6F),
    avatarSlot5: Color(0xFFD3545C),
    avatarSlot6: Color(0xFFE89F4D),
    avatarSlot7: Color(0xFF6B9E7A),
    avatarSlot8: Color(0xFF2B6CB0),
    avatarSlotNeutral: Color(0xFF9AA5A0),
    primary: Color(0xFFA65E24),
    primaryLight: Color(0xFFE8C79E),
    primaryDark: Color(0xFF7A421A),
    primarySurface: Color(0xFFFBF2E7),
    accent: Color(0xFFA9791F),
    accentLight: Color(0xFFEFDDAE),
    accentSurface: Color(0xFFFAF4E4),
    onPrimary: Color(0xFFFFFFFF),
    onAccent: Color(0xFF1A1A1A),
    onSuccess: Color(0xFFFFFFFF),
    onWarning: Color(0xFFFFFFFF),
    onDanger: Color(0xFFFFFFFF),
    onInfo: Color(0xFFFFFFFF),
  );

  /// 冬 · 苏木 (季节)
  static const AppTokens winter = AppTokens(
    id: 'winter',
    label: '冬 · 苏木',
    group: '季节',
    surface: Color(0xFFFFFBF5),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF7F2EA),
    surfaceSunken: Color(0xFFEDE6DA),
    surfaceInverse: Color(0xFF1A1A1A),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF4A4A4A),
    textTertiary: Color(0xFF6B6B6B),
    textDisabled: Color(0xFF8A8A8A),
    textOnInverse: Color(0xFFFFFFFF),
    border: Color(0xFFD0D0D0),
    borderStrong: Color(0xFF8A8A8A),
    borderInput: Color(0xFFD0D0D0),
    divider: Color(0xFFEDE6DA),
    focusRing: Color(0xFF8C4A4A),
    success: Color(0xFF2D5A3D),
    successLight: Color(0xFFA8D5BA),
    successSurface: Color(0xFFF0F7F2),
    warning: Color(0xFF8A6D1F),
    warningLight: Color(0xFFFFE8A3),
    warningSurface: Color(0xFFFFF3CD),
    danger: Color(0xFFB33A3A),
    dangerLight: Color(0xFFE08A8A),
    dangerSurface: Color(0xFFFFF5F5),
    info: Color(0xFF1F4E80),
    infoLight: Color(0xFFE3EDF8),
    infoSurface: Color(0xFFEDF4FB),
    memberGold: Color(0xFFC89A2B),
    memberGoldSurface: Color(0xFFFFF3CD),
    badgeNeutral: Color(0xFF6B6B6B),
    badgeNeutralSurface: Color(0xFFEDE6DA),
    graphFranchiseeB: Color(0xFF8E5BA8),
    graphFranchiseeBSurface: Color(0xFFF5F0F8),
    graphFranchiseeA: Color(0xFF2B6CB0),
    graphFranchiseeASurface: Color(0xFFEDF4FB),
    graphLine: Color(0xFFD0D0D0),
    graphLineSoft: Color(0xFFEDE6DA),
    shadowColor: Color(0xFF000000),
    scrim: Color(0xFF0F0F0F),
    accentSurfaceWarm: Color(0xFFFFF8E8),
    salonWaitlist: Color(0xFF5C6BC0),
    salonNeutral: Color(0xFF8A8A8A),
    warningDark: Color(0xFF8A5A1F),
    memberGoldLight: Color(0xFFD9B23D),
    dangerBright: Color(0xFFD3545C),
    avatarSlot1: Color(0xFF4A7C59),
    avatarSlot2: Color(0xFFC2185B),
    avatarSlot3: Color(0xFF8D6E63),
    avatarSlot4: Color(0xFF2F7D6F),
    avatarSlot5: Color(0xFFD3545C),
    avatarSlot6: Color(0xFFE89F4D),
    avatarSlot7: Color(0xFF6B9E7A),
    avatarSlot8: Color(0xFF2B6CB0),
    avatarSlotNeutral: Color(0xFF9AA5A0),
    primary: Color(0xFF8C4A4A),
    primaryLight: Color(0xFFDFB9B9),
    primaryDark: Color(0xFF632F2F),
    primarySurface: Color(0xFFFAF1F1),
    accent: Color(0xFF4A6E8C),
    accentLight: Color(0xFFCBDCE9),
    accentSurface: Color(0xFFF0F5F9),
    onPrimary: Color(0xFFFFFFFF),
    onAccent: Color(0xFFFFFFFF),
    onSuccess: Color(0xFFFFFFFF),
    onWarning: Color(0xFFFFFFFF),
    onDanger: Color(0xFFFFFFFF),
    onInfo: Color(0xFFFFFFFF),
  );

  /// 全部主题 (设置页遍历 / 测试对比度)
  static const List<AppTokens> all = <AppTokens>[
    sage,
    spring,
    summer,
    autumn,
    winter,
  ];

  static const Map<String, AppTokens> byId = <String, AppTokens>{
    'sage': sage,
    'spring': spring,
    'summer': summer,
    'autumn': autumn,
    'winter': winter,
  };

  static const String defaultId = 'sage';

  /// 按 id 取主题; 未知 id 回落到默认 (存 shared_preferences 的值可能是旧版本遗留)
  static AppTokens resolve(String? id) => byId[id] ?? byId[defaultId]!;

  /// 按分组列主题 (设置页: 品牌 / 季节)
  static Map<String, List<AppTokens>> get grouped {
    final out = <String, List<AppTokens>>{};
    for (final t in all) {
      out.putIfAbsent(t.group, () => <AppTokens>[]).add(t);
    }
    return out;
  }
}

/// 生成器自检: 每个主题的【色值个数】必须一致 (防止加主题时漏槽位)
const int kTokenColorCount = 67;
