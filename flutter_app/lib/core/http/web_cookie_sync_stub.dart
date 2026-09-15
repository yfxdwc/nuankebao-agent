// Native 平台 stub: 不读 document.cookie (那会编译失败)
class WebCookieSync {
  static Map<String, String> readAll() => <String, String>{};
}
