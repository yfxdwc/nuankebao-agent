import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'web_cookie_sync.dart' as web_cookie;

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

  /// 非 http(s) 宿主的兜底 origin
  ///
  /// 为什么不能用空串 / 相对路径: dio 在非 web 平台**不接受**相对 baseUrl
  /// (`ArgumentError: Must be a valid URL on platforms other than Web`),
  /// 而 ApiClient 在 app 启动 (router → apiClientProvider) 就创建了 → 相对路径会
  /// 把整个 app 在首帧打挂。用 dev 默认端口兜底 (跟 src/middleware.ts 的兜底一致):
  /// 至少是合法 URL; 真连不上时「我的 → 网络自检」会把服务地址显示出来, 一眼能看出漏了
  /// dart-define。
  static const String _fallbackOrigin = 'http://127.0.0.1:3003';

  /// 运行时 origin —— 只从 Uri.base 推导, 且**只认 http/https**。
  ///
  /// 为什么必须判断 scheme (2026-09-18 修):
  ///   `Uri.base.origin` 对非 http(s) 会直接 `StateError: Origin is only applicable
  ///   schemes http and https`。而下面两种场景 Uri.base 就不是 http(s):
  ///     1. widget 测试 (file:///.../flutter_app/)
  ///     2. native (Android/iOS) 的 Uri.base 也是 file:/// (APK 必须走 dart-define)
  ///   非 http(s) 时退回 `_fallbackOrigin` (见上)。
  static String get _runtimeOrigin {
    // ignore: do_not_use_environment
    final uri = Uri.base;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return uri.origin;
    }
    return _fallbackOrigin;
  }

  /// 规整后的 base URL (恒以 /api 结尾, dio 字符串拼接用)
  ///
  /// dart-define 优先, 空则 web 模式从 Uri.base.origin 自动推导.
  static String get baseUrl {
    if (_rawBaseUrl.isNotEmpty) {
      return normalizeApiBaseUrl(_rawBaseUrl);
    }
    // web 模式: 从当前页面 origin 推导 (运行时检测, IP 变不用 rebuild)
    return '${_runtimeOrigin}/api';
  }

  /// origin (去 /api 后缀) — Auth.js callbackUrl / 登录跳转用
  static String get baseOrigin {
    if (_rawBaseUrl.isNotEmpty) {
      // dart-define 模式: 去掉 /api 后缀
      final normalized = normalizeApiBaseUrl(_rawBaseUrl);
      return normalized.substring(0, normalized.length - 4);
    }
    // web 模式: 用当前 origin (非 http(s) 宿主→空串, 见 _runtimeOrigin)
    return _runtimeOrigin;
  }

  final Dio _dio;

  /// 内存 cookie jar: csrf / callback-url 等非持久 cookie
  final Map<String, String> _jar = {};

  ApiClient._(this._dio);

  /// 读 session token
  ///
  /// ⚠ Android 上 flutter_secure_storage 会在这些情况**抛异常**(不是返回 null):
  ///   系统升级/恢复出厂备份/换锁屏密码后 keystore 失效 → BadPaddingException 等。
  ///   以前异常会一路冒到 AuthNotifier._checkLogin → 用户"莫名被登出"还看不到原因。
  ///   现在: 吞掉异常 + 返回 null (当作没登录), 但**不删**数据 (下次可能就好了),
  ///   并在「网络自检」里能看到"本地没有登录凭证"。
  static Future<String?> sessionCookieName() async {
    try {
      return await storage.read(key: sessionCookieNameKey);
    } catch (e) {
      // ignore: avoid_print
      print('[session] read cookie name failed: $e');
      return null;
    }
  }

  static Future<String?> sessionToken() async {
    try {
      return await storage.read(key: sessionTokenKey);
    } catch (e) {
      // ignore: avoid_print
      print('[session] read token failed: $e');
      return null;
    }
  }

  /// 写 session (失败不抛: 安卓 keystore 偶发抽风不该让登录整体失败)
  static Future<void> saveSession({
    required String cookieName,
    required String token,
  }) async {
    try {
      await storage.write(key: sessionCookieNameKey, value: cookieName);
      await storage.write(key: sessionTokenKey, value: token);
    } catch (e) {
      // ignore: avoid_print
      print('[session] write failed: $e');
    }
  }

  /// 清空登录态 (logout / 换 session 前)
  static Future<void> clearSession() async {
    await storage.delete(key: sessionCookieNameKey);
    await storage.delete(key: sessionTokenKey);
  }

  /// R12 治本 (方案 B): web 平台从 document.cookie 读 Auth.js cookie
  /// 同步到 storage + 内存 jar。
  ///
  /// 调用时机:
  ///   1. AuthService.login() 成功后 (server 302 + 浏览器已写 cookie)
  ///   2. onResponse 拦截器 (作为 dio 拦截不到的 web 平台兑底)
  ///   3. App 启动 isLoggedIn() 前 (冷启动补一次)
  ///
  /// 边界:
  ///   - HttpOnly cookie 拿不到 (Auth.js session-token 是 HttpOnly, 平台限制)
  ///     → 这个限制让方案 B 在生产 web 上失败. 治本需方案 A (CORS ACAO)
  ///     或者换 cookie 策略 (非 HttpOnly).
  ///   - dev 模式 cookie 是 authjs.session-token (不 HttpOnly, 能读到)
  ///     → dev 模式 R12 治本有效, 跟 owner 调试场景贴齐
  static Future<void> syncCookiesFromBrowser() async {
    if (!kIsWeb) return;
    final cookies = web_cookie.WebCookieSync.readAll();
    // ignore: avoid_print
    print('[R12 debug] syncCookiesFromBrowser: cookies=${cookies.keys.toList()}');
    if (cookies.isEmpty) return;
    // fix-dev-web-login (2026-09-18 预览多账号时发现): storage.write 在 web 平台可能抛
    //   (flutter_secure_storage web 强制 AES, iframe/隐私模式常见)。以前异常会从
    //   onResponse 拦截器冒泡 → 把 200 的 /auth/flutter-login 响应带成异常 →
    //   login() 回退调 Auth.js callback (W1 mock 恒 user 1) → 多账号预览/联调全变 user 1。
    //   改成「失败即忽略」: 内存 session (setWebSession) + 浏览器自身 cookie 仍然生效。
    try {
      // 同步 cookie name + value (两个 key 分别存)
      if (cookies.containsKey('authjs.session-token')) {
        await saveSession(
          cookieName: 'authjs.session-token',
          token: cookies['authjs.session-token']!,
        );
        // ignore: avoid_print
        print('[R12 debug] wrote authjs.session-token, valueLen=${cookies['authjs.session-token']!.length}');
      } else if (cookies.containsKey('__Secure-authjs.session-token')) {
        await saveSession(
          cookieName: '__Secure-authjs.session-token',
          token: cookies['__Secure-authjs.session-token']!,
        );
        // ignore: avoid_print
        print('[R12 debug] wrote __Secure-authjs.session-token');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[R12 debug] storage 写入失败 (忽略, 用内存/浏览器 cookie): $e');
    }
  }

  /// R12 治本: web 平台 session token 存到内存 (flutter_secure_storage web 强制 AES 加密,
  /// 外部注入 / 跨会话冷启动拿不到). native 平台仍走 storage.
  /// dio 拦截器优先读这个, 没有再 fallback storage.
  static String? _webSessionToken;
  static String? _webSessionCookieName;
  // public getter 给 isLoggedIn / 其他模块读 (private static field 跨文件不可访问)
  static String? get webSessionToken => _webSessionToken;
  static String? get webSessionCookieName => _webSessionCookieName;
  static void setWebSession({required String cookieName, required String token}) {
    _webSessionCookieName = cookieName;
    _webSessionToken = token;
  }
  static void clearWebSession() {
    _webSessionCookieName = null;
    _webSessionToken = null;
  }

  /// R12 治本 dev 模式旁路: 从 URL query 读 ?_dev_token=... 注入 session
  /// (Playwright / 调试人手使用). 仅 web + dev mode 生效.
  ///
  /// 用法: POST /api/auth/flutter-login 拿 body.sessionToken, 填到 URL
  /// http://localhost:3003/app/customers?_dev_token=<jwt>
  ///
  /// 生产 HTTPS + HttpOnly cookie 这个方案走不了, 但生产本身不应该用 web.
  static Future<void> maybeInjectDevTokenFromUrl() async {
    if (!kIsWeb) return;
    // ignore: do_not_use_environment
    final uri = Uri.base;
    final token = uri.queryParameters['_dev_token'];
    if (token == null || token.isEmpty) return;
    final cookieName =
        uri.queryParameters['_dev_cookie_name'] ?? 'authjs.session-token';
    setWebSession(cookieName: cookieName, token: token);
    // ignore: avoid_print
    print('[R12 debug] injected dev token from URL: name=$cookieName tokenLen=${token.length}');
  }

  /// 会员功能被拒 (HTTP 402 + code=MEMBERSHIP_REQUIRED) 时的全局回调
  ///
  /// 由 app.dart 注册 (弹一条"这是会员功能"提示 + 去开通入口)。
  /// 为什么放在客户端拦截器里: 会员功能散落在多个页面 (AI 卡/互动/拍照/生日提醒),
  /// 与其每个页面写一遍 402 处理 (还会漏), 不如在**唯一出口**统一兜底。
  /// 真正的判权在服务端; 这里只是把失败翻译成人话。
  static void Function(String message)? onMembershipRequired;

  /// 防抖: 一屏里连点几个会员功能, 只提示一次 (2 秒内不重复弹)
  static DateTime? _lastMembershipToastAt;
  static void _notifyMembershipRequired(String message) {
    final now = DateTime.now();
    if (_lastMembershipToastAt != null &&
        now.difference(_lastMembershipToastAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastMembershipToastAt = now;
    try {
      onMembershipRequired?.call(message);
    } catch (_) {
      // 提示失败不能影响业务错误继续抛
    }
  }

  static ApiClient create() {
    // dio 超时 — web 预览模式 vs native APK 分开设置
    // (2026-09-20 加, w21 预览频繁「网络不太好」治本)
    //
    // 背景: Next.js dev mode 是懒编译 (lazy compilation), 每个 API 路由
    // 首次 hit 触发 webpack 编译, 实测最坏 43s (placement-requests 路由).
    // Flutter web 预览模式 (生产 build, URI.base.origin 推导) 直接消费
    // dev mode 后端, 所以首次进每个页面都可能撞上冷编译.
    //
    // 拆开:
    //   - web 预览: 60s connectTimeout (容下 dev 冷编译最坏情况 + 余量)
    //   - native APK: 10s connectTimeout (真用户蜂窝网络, 失败应快显)
    //
    // 修法说明: 本来想加 prewarm-dev-routes.sh 自动 curl 预编译,
    // 但路由集合会随代码变; 超时分平台是更稳的兜底.
    final connectTimeout = kIsWeb
        ? const Duration(seconds: 60)
        : const Duration(seconds: 10);
    final receiveTimeout = kIsWeb
        ? const Duration(seconds: 60)
        : const Duration(seconds: 30);

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
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
        // R12 治本 (web): 优先读内存里的 session (flutter_secure_storage 加密拿不到)
        // native: 走 storage
        String? name = _webSessionCookieName;
        String? token = _webSessionToken;
        if (name == null || token == null) {
          name = await sessionCookieName();
          token = await sessionToken();
        }
        final parts = <String>[];
        if (name != null && token != null) {
          parts.add('$name=$token');
        }
        for (final e in client._jar.entries) {
          parts.add('${e.key}=${e.value}');
        }
        if (parts.isNotEmpty) {
          options.headers['Cookie'] = parts.join('; ');
          // ignore: avoid_print
          final cookiePreview = parts.join('; ');
          print('[R12 debug] dio onRequest: Cookie=${cookiePreview.substring(0, cookiePreview.length < 80 ? cookiePreview.length : 80)}...');
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
              await saveSession(cookieName: c.name, token: c.value);
            } else {
              client._jar[c.name] = c.value;
            }
          }
        }
        // R12 治本: web 平台 XHR 拿不到 Set-Cookie 头, 同步从 document.cookie 兑底
        await syncCookiesFromBrowser();
        return handler.next(response);
      },
      onError: (e, handler) {
        // ADR-0012: 会员功能 402 → 全局提示 (客户端只做人话翻译, 不做判权)
        final res = e.response;
        if (res?.statusCode == 402) {
          final data = res?.data;
          final code = data is Map ? data['code']?.toString() : null;
          final msg = data is Map
              ? (data['error']?.toString() ?? '这是会员功能, 开通会员后可用')
              : '这是会员功能, 开通会员后可用';
          if (code == 'MEMBERSHIP_REQUIRED' || code == null) {
            _notifyMembershipRequired(msg);
          }
        }
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
