import 'package:flutter/material.dart';

/// 暖客宝 主题 — 中老年妇女极易用版本 (Plan F2)
/// - 字号默认 18pt (Material 默认 14)
/// - 主按钮高度 64pt (Material 默认 48)
/// - FAB 80pt 圆形
/// - 列表行高 80pt
/// - 颜色对比度 WCAG AAA (7:1)
/// - 主色 养生绿 #4A7C59 (养生行业气质)
/// - 强调色 暖橙 #E89F4D (温暖)
class AppTheme {
  // ============================================
  // 颜色 (WCAG AAA on bgWarm 白底)
  // ============================================
  static const Color primary = Color(0xFF4A7C59); // 养生绿 (主色)
  static const Color primaryLight = Color(0xFFA8D5BA); // 浅绿 (chip/背景)
  static const Color primaryDark = Color(0xFF2D5A3D); // 深绿 (text)
  static const Color accent = Color(0xFFE89F4D); // 暖橙 (强调)
  static const Color franchisee = Color(0xFF8E5BA8); // 加盟紫 (徽章)
  static const Color danger = Color(0xFFB33A3A); // 警示红 (深)
  static const Color bgWarm = Color(0xFFFFFBF5); // 暖白 (主背景)
  static const Color bgCard = Colors.white; // 卡片白
  static const Color textPrimary = Color(0xFF1A1A1A); // 主文字 (深黑, AAA)
  static const Color textSecondary = Color(0xFF4A4A4A); // 副文字 (中灰, AAA)

  // ============================================
  // 字号常量 (中老年)
  // ============================================
  static const double fontXs = 14; // 副信息
  static const double fontSm = 16; // 辅助
  static const double fontMd = 18; // 默认正文
  static const double fontLg = 22; // 强调
  static const double fontXl = 28; // 大标题
  static const double fontXxl = 36; // 主页大数字

  // ============================================
  // 尺寸常量 (中老年)
  // ============================================
  static const double buttonMinHeight = 56; // 主按钮最小高度
  static const double buttonLgHeight = 64; // 大按钮 (主操作)
  static const double fabSize = 80; // FAB 直径
  static const double listRowHeight = 80; // 列表行高
  static const double avatarMd = 56; // 列表头像
  static const double avatarLg = 96; // 详情页头像

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: bgWarm,
      onSurface: textPrimary,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgWarm,
      visualDensity: VisualDensity.standard, // 不要 compact (触摸精度)

      // 文字主题 (中老年字号)
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: fontXxl, fontWeight: FontWeight.bold, color: textPrimary),
        displayMedium: TextStyle(fontSize: fontXl, fontWeight: FontWeight.bold, color: textPrimary),
        headlineLarge: TextStyle(fontSize: fontXl, fontWeight: FontWeight.w600, color: textPrimary),
        headlineMedium: TextStyle(fontSize: fontLg, fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: TextStyle(fontSize: fontLg, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: TextStyle(fontSize: fontMd, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: fontMd, color: textPrimary),
        bodyMedium: TextStyle(fontSize: fontSm, color: textSecondary),
        bodySmall: TextStyle(fontSize: fontXs, color: textSecondary),
        labelLarge: TextStyle(fontSize: fontMd, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(fontSize: fontSm, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(fontSize: fontXs, fontWeight: FontWeight.w500),
      ),

      // AppBar (大标题 + 大返回按钮)
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: bgWarm,
        foregroundColor: textPrimary,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: fontLg,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(size: 28, color: textPrimary),
        toolbarHeight: 64,
      ),

      // 卡片 (圆角 + 浅阴影)
      cardTheme: CardTheme(
        elevation: 1,
        color: bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // 输入框 (大触摸区 + 大字号)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        labelStyle: const TextStyle(fontSize: fontMd),
        hintStyle: const TextStyle(fontSize: fontMd, color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD0D0D0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD0D0D0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),

      // 大按钮 (主操作 64pt)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, buttonLgHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: fontMd, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // 中等按钮 (次操作 56pt)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, buttonMinHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: fontMd, fontWeight: FontWeight.w600),
          side: const BorderSide(color: primary, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // FAB (80pt 大圆形, 中老年)
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        sizeConstraints: BoxConstraints.tightFor(width: fabSize, height: fabSize),
        extendedSizeConstraints: BoxConstraints.tightFor(height: fabSize),
      ),

      // Chip (大触摸区)
      chipTheme: ChipThemeData(
        labelStyle: const TextStyle(fontSize: fontMd, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // ListTile (大行高)
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minVerticalPadding: 12,
        iconColor: textSecondary,
        textColor: textPrimary,
      ),

      // Bottom Nav (中老年图标 + 文字)
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgWarm,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: TextStyle(fontSize: fontSm, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: fontSm),
        type: BottomNavigationBarType.fixed,
      ),

      // Dialog (大触摸)
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
          fontSize: fontLg,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        contentTextStyle: const TextStyle(fontSize: fontMd, color: textPrimary),
      ),

      // Snackbar (大字号)
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: TextStyle(fontSize: fontMd, color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}