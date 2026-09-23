import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/http/api_client.dart';
import 'core/providers/service_providers.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/telemetry/usage_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.g.dart';

/// 全局 SnackBar 通道 (402 会员提示用; 不依赖任何页面 context)
final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

class NuankeBaoApp extends ConsumerStatefulWidget {
  const NuankeBaoApp({super.key});

  @override
  ConsumerState<NuankeBaoApp> createState() => _NuankeBaoAppState();
}

class _NuankeBaoAppState extends ConsumerState<NuankeBaoApp> {
  @override
  void initState() {
    super.initState();
    // 用量采集 (主人 2026-09-22 拍: 内部工具强制开启; 实际只在 release native 生效)
    //   首帧后启动: 不阻塞冷启动; dev / web 由 usageTelemetryEnabled() 自动关闭
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(usageServiceProvider).start(ref.read(dioProvider)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsProvider);
    final tokens = ref.watch(activeTokensProvider);

    // 会员功能被拒 (402) 时全局提示一次 (ADR-0012)
    //   注册在 build 里是幂等的: 回调只覆盖, 不叠加; 用 messengerKey 保证不依赖某个页面 context
    ApiClient.onMembershipRequired = (message) {
      final messenger = _messengerKey.currentState;
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: AppTheme.fontMd)),
          duration: AppDuration.slow,
          action: SnackBarAction(
            label: '去开通',
            onPressed: () => router.go('/profile'),
          ),
        ),
      );
    };

    // 点跟进提醒 → 待办页 (§5 L3: 通知直达 L2)
    //   跟上面 402 提示一个套路: 回调只覆盖不叠加, 不依赖某个页面 context
    ref.read(followUpReminderProvider).onTap = () => router.go('/follow-ups');

    return MaterialApp.router(
      title: '暖客宝',
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      // 养生行业偏温暖, 不做 dark mode (AGENTS §1); 品牌色/季节主题可运行时切换 (换肤)
      theme: AppTheme.light(tokens),
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
