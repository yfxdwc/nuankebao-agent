import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

class NuankeBaoApp extends ConsumerWidget {
  const NuankeBaoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: '暖客宝',
      debugShowCheckedModeBanner: false,
      // 养生行业偏温暖, 不做 dark mode (AGENTS §1)
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      localizationsDelegates: const [],
    );
  }
}
