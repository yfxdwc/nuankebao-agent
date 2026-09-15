import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../http/api_client.dart';
import '../services/api.dart';
import 'service_providers.dart';

class AuthState {
  final bool isLoggedIn;
  final bool loading;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.loading = false,
    this.error,
  });

  AuthState copyWith({bool? isLoggedIn, bool? loading, String? error, bool clearError = false}) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _auth;
  AuthNotifier(this._auth) : super(const AuthState()) {
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    // R12 治本 dev 模式旁路: 从 URL query 读 ?_dev_token=... 注入 session
    // (Playwright / 调试人手能跳过登录页直接进 customer 验证 R12 后续逻辑)
    await ApiClient.maybeInjectDevTokenFromUrl();
    // R12 治本: 冷启动同步 (web 平台 service worker / page reload 后 storage 仍可能有 cookie)
    await ApiClient.syncCookiesFromBrowser();
    var logged = await _auth.isLoggedIn();
    // R12 时序: Flutter web 启动后 _checkLogin 第一次跑时, cookie 可能还没设 (用户刚在别处调
    // /api/auth/flutter-login 然后 navigate 到这里). 重试 1 次, 间隔 200ms, 覆盖时序问题.
    if (!logged) {
      await Future.delayed(const Duration(milliseconds: 200));
      await ApiClient.syncCookiesFromBrowser();
      logged = await _auth.isLoggedIn();
    }
    state = state.copyWith(isLoggedIn: logged);
  }

  Future<void> login({required String phone, required String code}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _auth.login(phone: phone, code: code);
      state = state.copyWith(isLoggedIn: true, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider));
});
