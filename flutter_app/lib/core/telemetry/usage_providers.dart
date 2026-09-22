// ============================================
// 用量采集 providers
//
// 内部工具强制开启 (主人 2026-09-22 拍), 无开关;
// 是否真的采集由 usageTelemetryEnabled() 决定 (release native 才开)
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import 'usage_service.dart';

/// 全局单例 (存活整个 app; app.dart 启动时 start(dio))
final usageServiceProvider = Provider<UsageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return UsageService(prefs: prefs);
});
