import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 规整 暖客宝 API base URL → 恒以 /api 结尾。
///
/// dio 拼 URL 是字符串拼接 (baseUrl + path), 而各 service 的 path 都以 '/' 开头且不含
/// /api (如 '/customers')。所以如果 --dart-define NUANKEBAO_API_BASE 只给了 origin
/// (如 https://nuankebao.tooyang.top) 而漏了 /api, 所有请求都会打到 /customers 这种路径 → 404。
String normalizeApiBaseUrl(String raw) {
  var b = raw.trim();
  while (b.endsWith('/')) {
    b = b.substring(0, b.length - 1);
  }
  if (!b.endsWith('/api')) {
    b = '$b/api';
  }
  return b;
}

/// Auth.js v5 的 cookie 名: https 下 session/csrf 带 __Secure- / __Host- 前缀,
/// http 下不带前缀。两种都要认, 登录/会话才能跨协议不踩坑。
const Set<String> _authCookieNames = {
  'authjs.session-token',
  '__Secure-authjs.session-token',
  'authjs.csrf-token',
  '__Host-authjs.csrf-token',
  'authjs.callback-url',
  '__Secure-authjs.callback-url',
};

/// 解析一条 Set-Cookie 头, 若是 Auth.js 的 cookie 返回记录, 否则返回 null。
/// isSession=true 的 (session-token) 需要持久化, 其余 (csrf/callback-url) 进内存 jar 即可。
({String name, String value, bool isSession})? parseAuthSetCookie(String line) {
  final semi = line.indexOf(';');
  final pair = semi >= 0 ? line.substring(0, semi) : line;
  final eq = pair.indexOf('=');
  if (eq <= 0) return null;
  final name = pair.substring(0, eq).trim();
  if (!_authCookieNames.contains(name)) return null;
  final value = pair.substring(eq + 1).trim();
  return (name: name, value: value, isSession: name.contains('session-token'));
}

/// API 客户端 (dio + Auth.js cookie 管理)
///
/// 手机端没有浏览器 cookie jar, Auth.js v5 的登录/会话全靠 cookie, 之前登录不上的
/// 两个根因都在这:
///   1. GET /api/auth/csrf 会 Set-Cookie csrf token, 但客户端从不把它带回
///      → POST /api/auth/callback/credentials 永远 302 MissingCSRF;
///   2. 登录成功后 session cookie 被硬编码成 authjs.session-token 发送, 而 https 下
///      服务端发的是 __Secure-authjs.session-token → 后续 API 全部 401。
///
/// 方案: 极简 cookie jar —— 响应里收到 Auth.js 的 Set-Cookie 就收下:
///   - session-token → 持久化 (名 + 值, 跨重启保持登录态)
///   - csrf / callback-url → 内存 jar
/// 请求时把 持久化 session + jar 里的 cookie 拼成 Cookie 头发出去。
///
/// v0.1.x (2026-09-12): web 模式从 Uri.base.origin 自动检测, IP 变不用 rebuild
///   - native (APK): --dart-define=NUANKEBAO_API_BASE=http://x.x.x.x:port/api (显式)
///   - web (iframe / 顶层): 不传 dart-define, runtime 从 window.location.origin 推导
///     → dev 机 IP 变 (192.168.1.99 / .200 / ...) 不需重新 flutter build web
class ApiClient {
  /// dart-define 入口. 空字符串 = web 模式自动从 Uri.base 推导.
  /// Native APK 必须在 build 时设: --dart-define=NUANKEBAO_API_BASE=http://x.x.x.x:port/api
  static const String _rawBaseUrl = String.fromEnvironment(
    'NUANKEBAO_API_BASE',
    defaultValue: '',
  );

  /// 是否 dart-define 显式传入 (vs web 默认空 → 自动检测)
  static bool get hasExplicitBaseUrl => _rawBaseUrl.isNotEmpty;

  static const FlutterSecureStorage storage = FlutterSecureStorage();

  /// 持久化 key (session cookie 名 + 值)
  static const sessionCookieNameKey = 'session_cookie_name';
  static const sessionTokenKey = 'session_token';

  /// 规整后的 base URL (恒以 /api 结尾, dio 字符串拼接用)
  ///
  /// dart-define 优先, 空则 web 模式从 Uri.base.origin 自动推导.
  static String get baseUrl {
    if (_rawBaseUrl.isNotEmpty) {
      return normalizeApiBaseUrl(_rawBaseUrl);
    }
    // web 模式: 从当前页面 origin 推导 (运行时检测, IP 变不用 rebuild)
    // ignore: do_not_use_environment
    return '${Uri.base.origin}/api';
  }

  /// origin (去 /api 后缀) — Auth.js callbackUrl / 登录跳转用
  static String get baseOrigin {
    if (_rawBaseUrl.isNotEmpty) {
      // dart-define 模式: 去掉 /api 后缀
      final normalized = normalizeApiBaseUrl(_rawBaseUrl);
      return normalized.substring(0, normalized.length - 4);
    }
    // web 模式: 用当前 origin
    // ignore: do_not_use_environment
    return Uri.base.origin;
  }

  final Dio _dio;

  /// 内存 cookie jar: csrf / callback-url 等非持久 cookie
  final Map<String, String> _jar = {};

  ApiClient._(this._dio);

  static Future<String?> sessionCookieName() =>
      storage.read(key: sessionCookieNameKey);
  static Future<String?> sessionToken() => storage.read(key: sessionTokenKey);

  /// 清空登录态 (logout / 换 session 前)
  static Future<void> clearSession() async {
    await storage.delete(key: sessionCookieNameKey);
    await storage.delete(key: sessionTokenKey);
  }

  static ApiClient create() {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      // 不在 base options 设 Content-Type: dio 默认会在 POST/PATCH/PUT 有 Map<String, dynamic>
      // data 时自动选 application/json (要 JSON), GET 不设 (简单请求不触发 preflight).
      // 之前在 base options 硬写 application/json 导致 GET 也带 Content-Type,
      // 浏览器判为非简单请求 → 发 OPTIONS preflight → Next.js server 没 ACAO → 阻断.
      // (commit 2026-09-11 第二次修, 跟 w14 错开: w14 是 cookie jar, 这次是 CORS preflight)
      headers: {},
    ));
    final client = ApiClient._(dio);

    dio.interceptors.add(InterceptorsWrapper(
      // 请求: 持久化 session cookie + jar 里其余 cookie → Cookie 头
      onRequest: (options, handler) async {
        // 兜底: 万一未来 caller 忘了, GET/HEAD 不要带 Content-Type (让 preflight 别触发)
        if (options.method.toUpperCase() == 'GET' ||
            options.method.toUpperCase() == 'HEAD') {
          options.headers.remove(Headers.contentTypeHeader);
        }
        final name = await sessionCookieName();
        final token = await sessionToken();
        final parts = <String>[];
        if (name != null && token != null) {
          parts.add('$name=$token');
        }
        for (final e in client._jar.entries) {
          parts.add('${e.key}=${e.value}');
        }
        if (parts.isNotEmpty) {
          options.headers['Cookie'] = parts.join('; ');
        }
        return handler.next(options);
      },
      // 响应: 收下 Auth.js 的 Set-Cookie (session 持久化, 其余进 jar)
      onResponse: (response, handler) async {
        for (final entry in response.headers.map.entries) {
          if (entry.key.toLowerCase() != 'set-cookie') continue;
          for (final line in entry.value) {
            final c = parseAuthSetCookie(line);
            if (c == null) continue;
            if (c.isSession) {
              // 换 session 时清掉旧的, 再写新的 (名 + 值 都要存)
              await clearSession();
              await storage.write(key: sessionCookieNameKey, value: c.name);
              await storage.write(key: sessionTokenKey, value: c.value);
            } else {
              client._jar[c.name] = c.value;
            }
          }
        }
        return handler.next(response);
      },
      onError: (e, handler) {
        return handler.next(e);
      },
    ));

    return client;
  }

  Dio get dio => _dio;
}

/// API 异常 (统一错误处理)
class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
