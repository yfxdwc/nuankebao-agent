import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // R12 debug: 启动后看 dart:html 读 document.cookie 是什么
  // 用 addPostFrameCallback 保证不被 dart2js dead-code 优化掉
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ignore: avoid_print
    print('[R12 debug] main() document.cookie=${html.document.cookie}');
  });
  runApp(
    const ProviderScope(
      child: NuankeBaoApp(),
    ),
  );
}
