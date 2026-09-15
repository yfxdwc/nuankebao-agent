// Web 实现: 用 dart:html.console.log (绕过 dart:io 的 print tree-shake)
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void logR12(String msg) {
  // ignore: avoid_print
  // ignore: invalid_use_of_protected_member
  (html.window.console as dynamic).log(msg);
}
