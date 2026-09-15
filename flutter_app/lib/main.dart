import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // R12 debug: 启动后用 dart:html.console.log (不会 tree-shake) 打印 document.cookie
  // ignore: avoid_web_libraries_in_flutter
  // ignore: avoid_print
  // ignore: invalid_use_of_protected_member
  (html.window.console as dynamic).log('R12 debug main document.cookie=${html.document.cookie}');
  runApp(
    const ProviderScope(
      child: NuankeBaoApp(),
    ),
  );
}
