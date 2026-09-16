import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'debug_print_stub.dart'
    if (dart.library.html) 'debug_print_web.dart' as debug_print;

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // R12 debug: 启动后用 web 平台 console.log 打印 document.cookie
  // (条件 import 让 native APK 也能 build, 不会 dart:html 报错)
  debug_print.logR12('R12 debug main boot');

  // dev 模式 web 平台: 强制 enable semantics.
  // 原因: Flutter web 默认 lazy enable (用户 tap 屏幕才 enable),
  // dev 工具 (Playwright / 手摸调试 / 屏读) 不方便主动 tap.
  // 生产 build 默认已 enable, dev 模式手动 enable 跟生产对齐.
  // Native APK 不受影响 (SemanticsBinding 在 native 默认就 enable).
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }

  runApp(
    const ProviderScope(
      child: NuankeBaoApp(),
    ),
  );
}
