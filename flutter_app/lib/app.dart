import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/settings_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class NuankeBaoApp extends ConsumerWidget {
  const NuankeBaoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: '暖客宝',
      debugShowCheckedModeBanner: false,
      // 养生行业偏温暖, 不做 dark mode (AGENTS §1)
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      localizationsDelegates: const [],
      // 全局字号缩放 (「我的」→ 显示设置)
      //
      // 为什么放 builder 而不是 ThemeData.textTheme:
      //   - 页面里写死的 TextStyle(fontSize: AppTheme.fontMd) 不会跟着 theme 变;
      //     textScaler 是渲染层的缩放, 对**所有**文字生效 (含写死的)
      //   - builder 包住整个 app (含 Navigator / Overlay) → 弹层和页面字号一致
      //
      // 跟系统字号的叠加: 用户手机本身也设了"超大字体"(Android 无障碍),
      //   两处都放大 = 界面炸。策略: 倍率相乘后再夹到 [0.7, 1.6] ——
      //   尊重系统设置, 但不允许叠出不可用的界面 (AppTheme 字号本来就偏大)
      //   下限 0.7 是为了保住「小」档 (0.85): 夹到 0.9 的话系统字号 < 1 时「小」就没效果了
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final systemScale = mq.textScaler.scale(1.0);
        final combined =
            (settings.fontScale * systemScale).clamp(0.7, 1.6).toDouble();
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(combined)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
