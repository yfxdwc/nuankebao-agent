// Web 平台实现: 从 document.cookie 读 Auth.js cookie
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class WebCookieSync {
  /// 读 document.cookie 所有 cookie → name/value map
  /// 返回的 cookie 是浏览器实际生效的 (同源已写入 + HttpOnly 除外)
  ///
  /// 注: HttpOnly cookie (Auth.js session-token) **不会**出现在 document.cookie
  /// —— 这是 R12 治本方案 B 的核心限制. 我们需要走其他路拿 token.
  static Map<String, String> readAll() {
    final result = <String, String>{};
    final cookieStr = html.document.cookie;
    if (cookieStr == null || cookieStr.isEmpty) return result;
    for (final part in cookieStr.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final name = part.substring(0, i).trim();
      final value = part.substring(i + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      result[name] = value;
    }
    return result;
  }
}
