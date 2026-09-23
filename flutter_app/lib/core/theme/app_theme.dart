import 'package:flutter/material.dart';

import 'theme_ext.dart';
import 'tokens.g.dart';

/// ============================================
/// 暖客宝 主题工厂 (中老年极易用版本 / Plan F2)
/// ============================================
///
/// **真源**: `design/tokens/design-tokens.json` → `pnpm tokens:build` → `tokens.g.dart`
/// 本文件只做「令牌 → ThemeData」的装配, **不含任何字面色值/数值**。
///
/// 三层结构:
///   AppPalette / AppSpace / AppType …  L0+L1 尺度常量 (编译期, 不随主题变)
///   AppTokens                          L2 语义色令牌 (运行时, 一主题一份)
///   AppTheme.light(tokens)             装配成 ThemeData
///
/// 改颜色的正确姿势:
///   ❌ 改这个文件
///   ✅ 改 design/tokens/design-tokens.json → pnpm tokens:build
///
/// 运行时换肤:
///   `app.dart` 里 `AppTheme.light(ref.watch(activeTokensProvider))`;
///   业务代码用 `context.tokens.xxx` 取色。
class AppTheme {
  const AppTheme._();

  // ============================================
  // 兼容层 —— 存量代码用的常量别名
  // ============================================
  //
  // ⚠ 这些是**编译期常量**, 值固定 = 默认主题的槽位。
  //   它们存在的唯一目的是让 54 个既有文件不一次性炸掉; 新代码一律不要用。
  //   需要跟随换肤 → `context.tokens.xxx`。
  //
  // 迁移进度看 `tools/check-ui-tokens.sh` 的输出。

  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.primary`
  static const Color primary = Color(0xFF4A7C59);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.primaryLight`
  static const Color primaryLight = Color(0xFFA8D5BA);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.primaryDark`
  static const Color primaryDark = Color(0xFF2D5A3D);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.accent`
  static const Color accent = Color(0xFFE89F4D);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.graphFranchiseeB`
  static const Color franchisee = Color(0xFF8E5BA8);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.graphFranchiseeA`
  static const Color franchiseeA = Color(0xFF2B6CB0);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.graphFranchiseeB`
  static const Color franchiseeB = Color(0xFF8E5BA8);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.badgeNeutral`
  static const Color badgeNeutral = Color(0xFF5A5A5A);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.danger`
  static const Color danger = Color(0xFFB33A3A);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.surface`
  static const Color bgWarm = Color(0xFFFFFBF5);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.surfaceCard`
  static const Color bgCard = Color(0xFFFFFFFF);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.textPrimary`
  static const Color textPrimary = Color(0xFF1A1A1A);
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.textSecondary`
  static const Color textSecondary = Color(0xFF4A4A4A);

  /// 边框 / 分隔线 (原先是散落各处的 `Color(0xFFD0D0D0)`)
  /// 兼容别名 —— 换肤不生效, 新代码用 `context.tokens.borderInput`
  static const Color border = Color(0xFFD0D0D0);

  // ---- 字号 (尺度, 不随主题变; 保留旧名字) ----
  static const double fontXs = AppType.xs; // 14 副信息
  static const double fontSm = AppType.sm; // 16 辅助
  static const double fontMd = AppType.md; // 18 默认正文
  static const double fontLg = AppType.lg; // 22 强调
  static const double fontXl = AppType.xl; // 28 大标题
  static const double fontXxl = AppType.xxl; // 36 主页大数字

  // ---- 组件尺寸 (尺度) ----
  static const double buttonMinHeight = AppSize.buttonMinHeight; // 56
  static const double buttonLgHeight = AppSize.buttonLgHeight; // 64
  static const double fabSize = AppSize.fabSize; // 80
  static const double listRowHeight = AppSize.listRowHeight; // 80
  static const double avatarMd = AppSize.avatarMd; // 56
  static const double avatarLg = AppSize.avatarLg; // 96

  // ============================================
  // ColorScheme (M3 全角色, 让 Material 内置控件自动跟随换肤)
  // ============================================

  static ColorScheme colorSchemeOf(AppTokens t) => ColorScheme(
        brightness: Brightness.light,
        // 主
        primary: t.primary,
        onPrimary: t.onPrimary,
        primaryContainer: t.primaryLight,
        onPrimaryContainer: t.primaryDark,
        // 次 (暖橙强调)
        secondary: t.accent,
        onSecondary: t.onAccent,
        secondaryContainer: t.accentLight,
        onSecondaryContainer: t.textPrimary,
        // 三 (图谱 B 线 / 加盟紫)
        tertiary: t.graphFranchiseeB,
        onTertiary: Colors.white,
        tertiaryContainer: t.graphFranchiseeBSurface,
        onTertiaryContainer: t.textPrimary,
        // 错
        error: t.danger,
        onError: t.onDanger,
        errorContainer: t.dangerSurface,
        onErrorContainer: t.danger,
        // 面
        surface: t.surface,
        onSurface: t.textPrimary,
        surfaceContainerLowest: t.surfaceCard,
        surfaceContainerLow: t.surfaceCard,
        surfaceContainer: t.surfaceSubtle,
        surfaceContainerHigh: t.surfaceSunken,
        surfaceContainerHighest: t.surfaceSunken,
        onSurfaceVariant: t.textSecondary,
        // 线
        outline: t.borderStrong,
        outlineVariant: t.border,
        // 反
        inverseSurface: t.surfaceInverse,
        onInverseSurface: t.textOnInverse,
        shadow: t.shadowColor,
        scrim: t.scrim,
      );

  // ============================================
  // 文字主题
  // ============================================

  static TextTheme textThemeOf(AppTokens t) => TextTheme(
        displayLarge: TextStyle(
          fontSize: AppType.xxl,
          fontWeight: AppWeight.bold,
          color: t.textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: AppType.xl,
          fontWeight: AppWeight.bold,
          color: t.textPrimary,
        ),
        displaySmall: TextStyle(
          fontSize: AppType.xl,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: AppType.xl,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: AppType.lg,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: AppType.md,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: AppType.lg,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: AppType.md,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: AppType.sm,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: AppType.md, color: t.textPrimary),
        bodyMedium: TextStyle(fontSize: AppType.sm, color: t.textSecondary),
        bodySmall: TextStyle(fontSize: AppType.xs, color: t.textSecondary),
        labelLarge: TextStyle(
          fontSize: AppType.md,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: AppType.sm,
          fontWeight: AppWeight.medium,
          color: t.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: AppType.xs,
          fontWeight: AppWeight.medium,
          color: t.textTertiary,
        ),
      );

  // ============================================
  // ThemeData 装配
  // ============================================

  static ThemeData light([AppTokens? tokens]) {
    final t = tokens ?? AppThemes.resolve(null);
    final scheme = colorSchemeOf(t);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.surface,
      visualDensity: VisualDensity.standard, // 不要 compact (触摸精度)
      textTheme: textThemeOf(t),
      extensions: <ThemeExtension<dynamic>>[AppTokensTheme(t)],

      // ---- AppBar (大标题 + 大返回按钮) ----
      appBarTheme: AppBarTheme(
        elevation: AppElevation.e0,
        scrolledUnderElevation: AppElevation.e0,
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: t.textPrimary,
          fontSize: AppType.lg,
          fontWeight: AppWeight.semibold,
        ),
        iconTheme: IconThemeData(size: AppSize.iconLg, color: t.textPrimary),
        actionsIconTheme:
            IconThemeData(size: AppSize.iconLg, color: t.textPrimary),
        toolbarHeight: AppSize.appBarHeight,
      ),

      iconTheme: IconThemeData(
        size: AppSize.iconMd,
        color: t.textSecondary,
      ),

      // ---- 卡片 ----
      cardTheme: CardTheme(
        elevation: AppElevation.e1,
        color: t.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: t.shadowColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.symmetric(
          horizontal: AppSpace.cardPadding,
          vertical: AppSpace.s6,
        ),
      ),

      // ---- 输入框 (大触摸区 + 大字号) ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s16,
          vertical: AppSpace.s16,
        ),
        labelStyle: TextStyle(fontSize: AppType.md, color: t.textSecondary),
        floatingLabelStyle: TextStyle(fontSize: AppType.sm, color: t.primary),
        hintStyle: TextStyle(fontSize: AppType.md, color: t.textTertiary),
        helperStyle: TextStyle(fontSize: AppType.xs, color: t.textSecondary),
        errorStyle: TextStyle(fontSize: AppType.xs, color: t.danger),
        prefixIconColor: t.textTertiary,
        suffixIconColor: t.textTertiary,
        border: _inputBorder(t.borderInput, AppRadius.input, 1),
        enabledBorder: _inputBorder(t.borderInput, AppRadius.input, 1),
        disabledBorder: _inputBorder(t.divider, AppRadius.input, 1),
        focusedBorder: _inputBorder(t.primary, AppRadius.input, AppSize.borderThick),
        errorBorder: _inputBorder(t.danger, AppRadius.input, 1),
        focusedErrorBorder:
            _inputBorder(t.danger, AppRadius.input, AppSize.borderThick),
      ),

      // ---- 大按钮 (主操作 64pt) ----
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: t.onPrimary,
          disabledBackgroundColor: t.surfaceSunken,
          disabledForegroundColor: t.textDisabled,
          elevation: AppElevation.e0,
          minimumSize: const Size(0, AppSize.buttonLgHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s24,
            vertical: AppSpace.s16,
          ),
          textStyle: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppWeight.semibold,
            color: t.onPrimary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),

      // ---- 中等按钮 (次操作 56pt) ----
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.primary,
          disabledForegroundColor: t.textDisabled,
          minimumSize: const Size(0, AppSize.buttonMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s20,
            vertical: AppSpace.s14,
          ),
          textStyle: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppWeight.semibold,
            color: t.primary,
          ),
          side: BorderSide(color: t.primary, width: AppSize.borderThick),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primary,
          disabledForegroundColor: t.textDisabled,
          minimumSize: const Size(0, AppSize.tapMin),
          textStyle: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppWeight.medium,
            color: t.primary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),

      // ---- FAB (80pt 大圆形, 中老年) ----
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        elevation: AppElevation.e3,
        focusElevation: AppElevation.e3,
        hoverElevation: AppElevation.e4,
        highlightElevation: AppElevation.e2,
        sizeConstraints: const BoxConstraints.tightFor(
          width: AppSize.fabSize,
          height: AppSize.fabSize,
        ),
        extendedSizeConstraints:
            const BoxConstraints.tightFor(height: AppSize.fabSize),
        shape: const CircleBorder(),
      ),

      // ---- Chip (大触摸区) ----
      //
      // ⚠ labelStyle / secondaryLabelStyle **必须显式写 color** (主人 2026-09-22 报 bug):
      //   RawChip 取样式是 `chipTheme.labelStyle ?? chipDefaults.labelStyle` —— 只要我们的
      //   labelStyle 非 null (哪怕只是设了字号), 就整个顶掉 M3 默认色
      //   (未选 onSurfaceVariant / 选中 onSecondaryContainer) → 文字 color = null
      //   → 引擎兜底色 = **白** (Android/Skia 实测 #FFFFFF) → 白卡片上根本看不见.
      //   ⚠ Flutter web (CanvasKit) 兜底色是**黑** → /app-preview 看着"正常", 会骗过验收:
      //     这类"样式没写颜色"的问题只能在真机 APK 上看出来.
      //   选中态: M3 的 ChoiceChip 会把 secondaryLabelStyle 当成 "已选中" 的 label 样式
      //          (choice_chip.dart: `labelStyle ?? (selected ? chipTheme.secondaryLabelStyle : null)`),
      //          所以两栏都要给色.
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(
          fontSize: AppType.md,
          fontWeight: AppWeight.medium,
          color: t.textPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: AppType.md,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        backgroundColor: t.surfaceSunken,
        deleteIconColor: t.textSecondary,
        selectedColor: t.primaryLight,
        secondarySelectedColor: t.primaryLight,
        checkmarkColor: t.primaryDark,
        disabledColor: t.surfaceSubtle,
        iconTheme: IconThemeData(size: AppSize.iconSm, color: t.textPrimary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s16,
          vertical: AppSpace.s10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        side: BorderSide.none,
      ),

      // ---- ListTile (大行高) ----
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s16,
          vertical: AppSpace.s8,
        ),
        minVerticalPadding: AppSpace.s12,
        iconColor: t.textSecondary,
        textColor: t.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: AppType.md,
          fontWeight: AppWeight.medium,
          color: t.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: AppType.sm,
          color: t.textSecondary,
        ),
      ),

      // ---- Bottom Nav (中老年图标 + 文字) ----
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: t.surface,
        selectedItemColor: t.primary,
        unselectedItemColor: t.textSecondary,
        selectedLabelStyle: TextStyle(
            fontSize: AppType.sm,
            fontWeight: AppWeight.semibold,
            color: t.primary),
        unselectedLabelStyle:
            TextStyle(fontSize: AppType.sm, color: t.textSecondary),
        type: BottomNavigationBarType.fixed,
        elevation: AppElevation.e0,
        showUnselectedLabels: true,
      ),

      // ---- Dialog ----
      dialogTheme: DialogTheme(
        backgroundColor: t.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.e4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
        titleTextStyle: TextStyle(
          fontSize: AppType.lg,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
        contentTextStyle: TextStyle(fontSize: AppType.md, color: t.textPrimary),
      ),

      // ---- Bottom Sheet ----
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surfaceCard,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.surfaceCard,
        elevation: AppElevation.e4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        dragHandleColor: t.borderStrong,
        showDragHandle: true,
      ),

      // ---- Snackbar ----
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.textPrimary,
        contentTextStyle: TextStyle(
          fontSize: AppType.md,
          color: t.surfaceCard,
        ),
        actionTextColor: t.primaryLight,
        behavior: SnackBarBehavior.floating,
        elevation: AppElevation.e3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),

      // ---- 分隔线 (原先散落 20+ 处 Divider defaultColor) ----
      dividerTheme: DividerThemeData(
        color: t.divider,
        thickness: AppSize.borderHairline,
        space: AppSize.borderHairline,
      ),

      // ---- 弹层菜单 ----
      popupMenuTheme: PopupMenuThemeData(
        color: t.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.e3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        textStyle: TextStyle(fontSize: AppType.md, color: t.textPrimary),
      ),

      // ---- 开关 / 勾选 (原先完全靠 M3 默认种子色) ----
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? t.onPrimary
              : t.surfaceCard,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? t.primary
              : t.surfaceSunken,
        ),
        trackOutlineColor: WidgetStatePropertyAll(t.borderStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? t.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(t.onPrimary),
        side: BorderSide(color: t.borderStrong, width: AppSize.borderThick),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r4),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? t.primary : t.borderStrong,
        ),
      ),

      // ---- 进度指示 ----
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primary,
        linearTrackColor: t.surfaceSunken,
        circularTrackColor: t.surfaceSunken,
      ),

      // ---- 分段控件 / Tab ----
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? t.onPrimary
                : t.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? t.primary
                : t.surfaceCard,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: t.border)),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: AppType.sm, fontWeight: AppWeight.medium),
          ),
        ),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: t.primary,
        unselectedLabelColor: t.textSecondary,
        indicatorColor: t.primary,
        dividerColor: t.divider,
        labelStyle: TextStyle(
            fontSize: AppType.md,
            fontWeight: AppWeight.semibold,
            color: t.primary),
        unselectedLabelStyle:
            TextStyle(fontSize: AppType.md, color: t.textSecondary),
      ),

      // ---- 日期 / 时间选择器 ----
      datePickerTheme: DatePickerThemeData(
        backgroundColor: t.surfaceCard,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: t.primarySurface,
        headerForegroundColor: t.primaryDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: t.surfaceCard,
        dialBackgroundColor: t.surfaceSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
      ),

      // ---- 提示 / 滚动条 ----
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.surfaceInverse,
          borderRadius: BorderRadius.circular(AppRadius.r6),
        ),
        textStyle: TextStyle(fontSize: AppType.xs, color: t.textOnInverse),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(t.borderStrong),
        radius: const Radius.circular(AppRadius.pill),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color c, double r, double w) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: c, width: w),
      );
}
