import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'debug_print_stub.dart'
    if (dart.library.html) 'debug_print_web.dart' as debug_print;

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // R12 debug: 启动后用 web 平台 console.log 打印 document.cookie
  // (条件 import 让 native APK 也能 build, 不会 dart:html 报错)
  debug_print.logR12('R12 debug main boot');
  runApp(
    const ProviderScope(
      child: NuankeBaoApp(),
    ),
  );
}
