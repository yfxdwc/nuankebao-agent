import 'package:dio/dio.dart';

import 'api_client.dart';

class AuthService {
  final Dio _dio;

  AuthService(this._dio);

  /// 登录 (Auth.js v5 Credentials)
  ///
  /// 流程 (cookie 处理全在 ApiClient 拦截器):
  ///   1. GET /auth/csrf → csrf cookie + csrfToken 都被收下
  ///   2. POST /auth/callback/credentials → 拦截器自动带回 csrf cookie (否则 MissingCSRF)
  ///   3. 成功 Set-Cookie session-token → 拦截器持久化 (名 + 值), 后续请求自动带同名 cookie
  Future<void> login({
    required String phone,
    required String code,
  }) async {
    // 1. 拿 CSRF (csrf cookie 已由拦截器收进 jar)
    final csrfRes = await _dio.get('/auth/csrf');
    final csrf = csrfRes.data['csrfToken'] as String?;
    if (csrf == null) {
      throw Exception('获取安全令牌失败, 请检查网络后重试');
    }

    // 2. POST 登录 (不跟随 302, 由我们判断 location)
    final loginRes = await _dio.post(
      '/auth/callback/credentials',
      data: {
        'csrfToken': csrf,
        'phone': phone,
        'code': code,
        'callbackUrl': '${ApiClient.baseOrigin}/dashboard',
        'json': 'true',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    final statusCode = loginRes.statusCode ?? 0;
    if (statusCode != 302 && statusCode != 200) {
      throw ApiException(statusCode, '登录失败 ($statusCode)');
    }

    // 3. 302 location 带 ?error= 说明被拒 (MissingCSRF / CredentialsSignin / Configuration)
    final location = loginRes.headers.value('location') ?? '';
    final error = Uri.tryParse(location)?.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      throw Exception('登录失败: ${_errorText(error)}');
    }

    // 4. session cookie 由拦截器持久化, 这里只做终检
    final token = await ApiClient.sessionToken();
    if (token == null) {
      throw Exception('未获取到 session token');
    }
  }

  /// Auth.js error code → 人话
  static String _errorText(String code) {
    switch (code) {
      case 'MissingCSRF':
        return '安全校验失败, 请重试';
      case 'CredentialsSignin':
        return '验证码错误或已过期';
      case 'Configuration':
        return '服务端配置错误, 请联系管理员';
      default:
        return code;
    }
  }

  Future<void> logout() => ApiClient.clearSession();

  Future<bool> isLoggedIn() async {
    final token = await ApiClient.sessionToken();
    return token != null;
  }
}
